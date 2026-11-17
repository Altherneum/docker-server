#!/bin/sh
# =============================================================================
# mail-setup.sh - installe et configure Mailcow en une seule commande.
#
# Suppose que le DNS est déjà prêt (A, MX, SPF, DKIM, DMARC, PTR). Pour le
# DKIM, lancer make mail-dkim-key avant, ou fournir une ancienne clé.
#
# - installe Mailcow si absent ;
# - installe l'override Traefik et la clé API ;
# - démarre la stack et attend les services ;
# - importe/crée la clé DKIM ;
# - crée les boîtes de base ;
# - lance la vérification.
#
# Usage : ./scripts/mail-setup.sh
# =============================================================================
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MAIL_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/mail-lib.sh"
mail_load_env "$MAIL_ROOT"

wait_for_service() {
    service=$1
    tries=180
    while [ "$tries" -gt 0 ]; do
        if mailcow_service_running "$service"; then
            return 0
        fi
        tries=$((tries - 1))
        sleep 2
    done
    return 1
}

wait_for_api() {
    tries=180
    while [ "$tries" -gt 0 ]; do
        out=$(mail_api_get get/status/version 2>/dev/null || true)
        case "$out" in
            *'"version"'*) return 0 ;;
        esac
        tries=$((tries - 1))
        sleep 2
    done
    return 1
}

mail_info "installation de Mailcow"
"$SCRIPT_DIR/mail-install.sh"

mail_info "intégration Traefik"
"$SCRIPT_DIR/mail-integrate.sh"

mail_info "démarrage de Mailcow"
(
    cd "$MAILCOW_DIR"
    docker compose -f docker-compose.yml -f docker-compose.override.yml up -d
)

mail_info "attente des services Mailcow"
for service in redis-mailcow mysql-mailcow php-fpm-mailcow rspamd-mailcow nginx-mailcow postfix-mailcow dovecot-mailcow; do
    if wait_for_service "$service"; then
        printf '  [OK] %s\n' "$service"
    else
        mail_die "$service ne démarre pas. Consultez : sudo make mail-logs"
    fi
done

# Laisse à MySQL/php-fpm le temps de finir l'initialisation avant l'API.
sleep 5
mail_info "attente de l'API Mailcow"
if wait_for_api; then
    printf '  [OK] API Mailcow\n'
else
    mail_die "l'API Mailcow ne répond pas. Vérifiez MAILCOW_API_KEY et : sudo make mail-logs"
fi

mail_info "clé DKIM"
created_new=0
create_keys=$(env_get MAIL_CREATE_KEYS | tr '[:upper:]' '[:lower:]')
[ -n "$create_keys" ] || create_keys=no
case "$create_keys" in
    yes)
        created_new=1
        ;;
    no)
        if ! mail_dkim_key_available; then
            mail_info "aucune clé DKIM fournie : pré-génération dans backups/dkim"
            "$SCRIPT_DIR/mail-dkim-key.sh"
            created_new=1
        fi
        ;;
    *)
        mail_die "MAIL_CREATE_KEYS doit valoir yes ou no (valeur : $create_keys)."
        ;;
esac
"$SCRIPT_DIR/mail-dkim.sh"
if [ "$created_new" -eq 1 ]; then
    env_set MAIL_CREATE_KEYS no
    mail_info "MAIL_CREATE_KEYS=no enregistré pour éviter une rotation accidentelle"
fi

mail_info "boîtes mail de base"
"$SCRIPT_DIR/mail-mailboxes.sh"

mail_info "certificat SMTP/IMAP depuis Traefik"
"$SCRIPT_DIR/mail-cert-sync.sh" || mail_warn "synchro du certificat Traefik impossible ; mailcow garde son certificat interne."
if [ "$(id -u)" -eq 0 ]; then
    "$SCRIPT_DIR/mail-cert-timer.sh" || mail_warn "timer certificat non installé ; lancez sudo make mail-cert-timer."
else
    mail_info "timer certificat : lancez sudo make mail-cert-timer (une seule fois) pour le renouvellement automatique."
fi

mail_info "vérification"
check_ok=1
"$SCRIPT_DIR/mail-check.sh" || check_ok=0

printf '\n'
mail_info "Mailcow est configuré"
mailboxes=$(env_get MAIL_MAILBOXES)
[ -n "$mailboxes" ] || mailboxes="admin,contact,root,postmaster,abuse"
interface_host=$(mailcow_get MAILCOW_HOSTNAME 2>/dev/null || true)
[ -n "$interface_host" ] || interface_host="mail.$DOMAIN"
printf '  Interface : https://%s\n' "$interface_host"
printf '  Admin     : admin / moohoo (à changer immédiatement)\n'
printf '  Boîtes    : %s\n' "$mailboxes"
if [ "$check_ok" -eq 0 ]; then
    printf '  Vérification : incomplète, voir les erreurs ci-dessus\n'
else
    printf '  Vérification : OK\n'
fi
printf '\n'
if [ "$created_new" -eq 1 ]; then
    printf 'DKIM : un nouveau TXT a été généré. Ajoute-le au DNS, puis relance :\n'
    printf '  sudo make mail-check\n'
else
    printf 'DKIM : clé existante/pré-générée importée, le DNS ne change pas.\n'
fi

printf 'SMTP/IMAP : certificat Traefik synchronisé si disponible (sinon interne).\n'
