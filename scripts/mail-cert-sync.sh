#!/bin/sh
# =============================================================================
# mail-cert-sync.sh - utilise le certificat Let's Encrypt de Traefik pour
# SMTP/IMAP.
#
# Traefik obtient le certificat de mail.<domaine> en HTTP-01 (uniquement
# l'enregistrement A et le port 80). Ce script lit acme.json dans le conteneur
# traefik, extrait le certificat du domaine, l'écrit dans
# $MAILCOW_DIR/data/assets/ssl/ et redémarre postfix, dovecot et nginx-mailcow
# seulement si le certificat a changé.
#
# Sans certificat Traefik (Traefik arrêté, acme.json vide, certificat expiré),
# mailcow garde son certificat interne : aucune erreur, aucune action.
#
# Usage : sudo ./scripts/mail-cert-sync.sh [--quiet]
# =============================================================================
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MAIL_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/mail-lib.sh"
mail_load_env "$MAIL_ROOT"

quiet=0
case "${1:-}" in
    '') ;;
    --quiet) quiet=1 ;;
    *) mail_die "option inconnue : $1 (utilisez --quiet)" ;;
esac

say() {
    [ "$quiet" -eq 1 ] || mail_info "$*"
}

# Rien à faire si mailcow n'est pas utilisé sur cette machine.
[ -d "$MAILCOW_DIR" ] || {
    say "mailcow n'est pas installé dans $MAILCOW_DIR ; rien à faire."
    exit 0
}
[ -f "$MAILCOW_CONF" ] || {
    say "mailcow.conf absent ; rien à faire."
    exit 0
}
mail_enabled=$(env_get MAIL_ENABLED | tr '[:upper:]' '[:lower:]')
case "$mail_enabled" in
    false|no|0|off)
        say "MAIL_ENABLED=false ; rien à faire."
        exit 0
        ;;
esac

host=$(mailcow_get MAILCOW_HOSTNAME)
[ -n "$host" ] || host="mail.$DOMAIN"

command -v docker >/dev/null 2>&1 || mail_die "docker est requis."
command -v python3 >/dev/null 2>&1 || mail_die "python3 est requis pour lire acme.json."
command -v openssl >/dev/null 2>&1 || mail_die "openssl est requis."

if ! docker inspect traefik >/dev/null 2>&1; then
    say "conteneur traefik absent : mailcow garde son certificat interne."
    exit 0
fi
if [ "$(docker inspect -f '{{.State.Running}}' traefik 2>/dev/null || true)" != "true" ]; then
    say "Traefik est arrêté : mailcow garde son certificat interne."
    exit 0
fi

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/mail-cert.XXXXXX")
trap 'rm -rf "$tmpdir"' 0 1 2 15

if ! docker exec traefik cat /acme/acme.json > "$tmpdir/acme.json" 2>/dev/null; then
    say "acme.json illisible : mailcow garde son certificat interne."
    exit 0
fi

rc=0
python3 - "$host" "$tmpdir" "$tmpdir/acme.json" <<'PY' || rc=$?
import base64
import json
import os
import sys

host = sys.argv[1].strip().lower()
out = sys.argv[2]
acme_file = sys.argv[3]

try:
    with open(acme_file, encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    sys.exit(2)

found = None
for resolver in data.values():
    if not isinstance(resolver, dict):
        continue
    for cert in resolver.get("Certificates") or []:
        domain = cert.get("domain") or {}
        names = [domain.get("main", "")] + list(domain.get("sans") or [])
        if any(str(name).lower() == host for name in names):
            found = cert
            break
    if found:
        break

if not found:
    sys.exit(3)

try:
    pem_cert = base64.b64decode(found["certificate"])
    pem_key = base64.b64decode(found["key"])
except Exception:
    sys.exit(4)

with open(os.path.join(out, "cert.pem"), "wb") as handle:
    handle.write(pem_cert)
with open(os.path.join(out, "key.pem"), "wb") as handle:
    handle.write(pem_key)
PY

case "$rc" in
    0) ;;
    2|4)
        say "acme.json invalide : mailcow garde son certificat interne."
        exit 0
        ;;
    3)
        say "Traefik n'a pas encore de certificat pour $host : mailcow garde son certificat interne."
        exit 0
        ;;
    *)
        say "lecture d'acme.json impossible : mailcow garde son certificat interne."
        exit 0
        ;;
esac

# Refuse un certificat expiré ou incohérent avec sa clé.
if ! openssl x509 -in "$tmpdir/cert.pem" -noout -checkend 0 >/dev/null 2>&1; then
    say "certificat Traefik expiré pour $host : mailcow garde son certificat interne."
    exit 0
fi
cert_pub=$(openssl x509 -in "$tmpdir/cert.pem" -pubkey -noout 2>/dev/null || true)
key_pub=$(openssl pkey -in "$tmpdir/key.pem" -pubout 2>/dev/null || true)
if [ -z "$cert_pub" ] || [ "$cert_pub" != "$key_pub" ]; then
    mail_die "certificat et clé Traefik incohérents pour $host."
fi

ssl_dir="$MAILCOW_DIR/data/assets/ssl"
if [ -f "$ssl_dir/cert.pem" ] && [ -f "$ssl_dir/key.pem" ] \
    && cmp -s "$tmpdir/cert.pem" "$ssl_dir/cert.pem" \
    && cmp -s "$tmpdir/key.pem" "$ssl_dir/key.pem"; then
    say "certificat déjà à jour pour $host (aucun redémarrage)."
    exit 0
fi

mkdir -p "$ssl_dir" 2>/dev/null \
    || mail_die "impossible de créer $ssl_dir (droits root ? relancez avec sudo)."
install -m 644 "$tmpdir/cert.pem" "$ssl_dir/cert.pem" 2>/dev/null \
    || mail_die "impossible d'écrire $ssl_dir/cert.pem (droits root ? relancez avec sudo)."
install -m 600 "$tmpdir/key.pem" "$ssl_dir/key.pem" 2>/dev/null \
    || mail_die "impossible d'écrire $ssl_dir/key.pem (droits root ? relancez avec sudo)."

mail_info "certificat Traefik installé pour $host"

if mailcow_service_running postfix-mailcow; then
    if mailcow_compose restart postfix-mailcow dovecot-mailcow nginx-mailcow >/dev/null 2>&1; then
        mail_info "postfix, dovecot et nginx-mailcow redémarrés"
    else
        mail_warn "redémarrage impossible ; les services liront le certificat au prochain démarrage."
    fi
else
    say "mailcow est arrêté : le certificat sera utilisé au prochain démarrage."
fi
