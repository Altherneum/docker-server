#!/bin/sh
# =============================================================================
# mail-dkim-key.sh - prépare la clé DKIM avant l'installation de mailcow.
#
# Permet de remplir le TXT DKIM dans le DNS dès le début, sans attendre que
# mailcow soit installé. La clé est ensuite importée par mail-dkim.sh
# (MAIL_CREATE_KEYS=no) : aucun changement DNS après l'installation.
#
# Usage : ./scripts/mail-dkim-key.sh
# =============================================================================
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MAIL_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/mail-lib.sh"
mail_load_env "$MAIL_ROOT"

trap 'mail_chown_user "$ENV_FILE"' 0

command -v openssl >/dev/null 2>&1 || mail_die "openssl est requis."

domain=$DOMAIN
mail_domain_valid "$domain" || mail_die "DOMAIN invalide : $domain (renseignez DOMAIN_NAME et TLD dans .env)"

selector=$(env_get MAIL_DKIM_SELECTOR)
[ -n "$selector" ] || selector=dkim
case "$selector" in
    *[!A-Za-z0-9._-]*) mail_die "MAIL_DKIM_SELECTOR invalide : $selector" ;;
esac

key_file=$(env_get MAIL_DKIM_PRIVATE_KEY_FILE)
if [ -n "$key_file" ]; then
    case "$key_file" in
        "~/"*) key_file="$HOME/${key_file#~/}" ;;
        /*) ;;
        *) key_file="$MAIL_ROOT/$key_file" ;;
    esac
    [ -f "$key_file" ] || mail_die "MAIL_DKIM_PRIVATE_KEY_FILE introuvable : $key_file (corrigez le chemin, ou videz la variable pour générer une nouvelle clé)"
    [ -r "$key_file" ] || mail_die "MAIL_DKIM_PRIVATE_KEY_FILE illisible : $key_file"
fi

if [ -z "$key_file" ]; then
    key_dir="$BACKUP_DIR/dkim"
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    key_file="$key_dir/$domain.pem"
    if [ ! -f "$key_file" ]; then
        mail_info "génération de la clé DKIM pour $domain"
        openssl genrsa -out "$key_file" 2048 2>/dev/null || mail_die "génération de la clé impossible."
    else
        mail_info "clé DKIM existante réutilisée : $key_file"
    fi
    env_set MAIL_DKIM_PRIVATE_KEY_FILE "$key_file"
    env_set MAIL_CREATE_KEYS no
    env_set MAIL_DKIM_SELECTOR "$selector"
else
    mail_info "clé DKIM existante réutilisée : $key_file"
    env_set MAIL_CREATE_KEYS no
fi

chmod 600 "$key_file"
pub_b64=$(openssl pkey -in "$key_file" -pubout 2>/dev/null | sed -e '1d' -e '$d' | tr -d '\r\n')
[ -n "$pub_b64" ] || mail_die "clé publique vide : $key_file"

txt_value="v=DKIM1;k=rsa;t=s;s=email;p=$pub_b64"
chunked=$(printf '%s' "$txt_value" | awk '{
    s = $0
    out = ""
    while (length(s) > 0) {
        out = out (out == "" ? "" : " ") "\"" substr(s, 1, 255) "\""
        s = substr(s, 256)
    }
    print out
}')

out_dir="$BACKUP_DIR/dkim"
mkdir -p "$out_dir"
chmod 700 "$out_dir"
txt_file="$out_dir/$domain.txt"
{
    printf '# Clé DKIM pré-générée pour %s\n' "$domain"
    printf '# Sélecteur : %s\n' "$selector"
    printf '# Privée    : %s\n' "$key_file"
    printf '%s._domainkey.%s. IN TXT %s\n' "$selector" "$domain" "$chunked"
} > "$txt_file"
chmod 644 "$txt_file"

printf '\n[%s] clé DKIM prête\n' "$domain"
printf '  Nom    : %s._domainkey.%s\n' "$selector" "$domain"
printf '  Valeur : %s\n' "$txt_value"
printf '  Découpé: %s\n' "$chunked"
printf '  Clé    : %s (600)\n' "$key_file"
printf '  TXT    : %s\n' "$txt_file"
printf '\nLe TXT peut être publié dès maintenant.\n'
printf 'Après installation de mailcow, lancez : sudo make mail-dkim\n'
printf 'La clé sera importée dans mailcow sans être régénérée.\n'

mail_chown_user "$out_dir"
