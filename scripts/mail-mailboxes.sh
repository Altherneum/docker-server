#!/bin/sh
# =============================================================================
# mail-mailboxes.sh - crée les boîtes mail de base dans mailcow.
#
# Le domaine est unique (DOMAIN). Les boîtes sont définies par MAIL_MAILBOXES
# (séparées par des virgules) et créées via l'API mailcow, sans passer par
# l'interface.
#
# Les mots de passe sont lus dans .env :
#   - MAILBOX_<NOM>_PASSWORD pour les boîtes de base ;
#   - AZURIOM_MAIL_PASSWORD pour noreply ;
#   - FORGEJO_MAIL_PASSWORD pour git ;
#   - NEXTCLOUD_MAIL_PASSWORD pour cloud.
# S'ils sont vides, un mot de passe est généré et écrit dans .env.
#
# Usage : ./scripts/mail-mailboxes.sh
# =============================================================================
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MAIL_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/mail-lib.sh"
mail_load_env "$MAIL_ROOT"

trap 'mail_chown_user "$ENV_FILE"' 0

[ -d "$MAILCOW_DIR" ] || mail_die "mailcow n'est pas installé dans $MAILCOW_DIR."
[ -f "$MAILCOW_CONF" ] || mail_die "$MAILCOW_CONF introuvable."
command -v openssl >/dev/null 2>&1 || mail_die "openssl est requis."
command -v docker >/dev/null 2>&1 || mail_die "docker est requis."

domain=$DOMAIN
mail_domain_valid "$domain" || mail_die "DOMAIN invalide : $domain (renseignez DOMAIN_NAME et TLD dans .env)"

if ! mail_api_available; then
    mail_die "API mailcow indisponible. Lancez sudo make mail-setup, puis vérifiez MAILCOW_API_KEY."
fi

# Crée le domaine s'il n'existe pas encore (sans clé DKIM automatique).
mail_api_add_domain "$domain" || mail_die "impossible de créer/vérifier le domaine $domain via l'API mailcow."

mailboxes=$(env_get MAIL_MAILBOXES)
[ -n "$mailboxes" ] || mailboxes="admin,contact,root,postmaster,abuse"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

password_var_for() {
    case "$1" in
        noreply) printf 'AZURIOM_MAIL_PASSWORD\n' ;;
        git) printf 'FORGEJO_MAIL_PASSWORD\n' ;;
        cloud) printf 'NEXTCLOUD_MAIL_PASSWORD\n' ;;
        *) printf 'MAILBOX_%s_PASSWORD\n' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | sed 's/[.-]/_/g')" ;;
    esac
}

failed=0
created=0
existing=0

old_ifs=$IFS
IFS=', '
for local_part in $mailboxes; do
    local_part=$(printf '%s' "$local_part" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    [ -n "$local_part" ] || continue

    case "$local_part" in
        *[!a-z0-9._-]*)
            mail_warn "adresse ignorée (caractères invalides) : $local_part"
            failed=1
            continue
            ;;
    esac

    password_var=$(password_var_for "$local_part")
    password=$(env_get "$password_var")
    generated=0
    case "$password" in
        ''|CHANGE_ME)
            password=$(openssl rand -hex 20)
            env_set "$password_var" "$password"
            generated=1
            ;;
    esac

    name=$(printf '%s' "$local_part" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')
    address="$local_part@$domain"
    json=$(printf '{"local_part":"%s","domain":"%s","name":"%s","authsource":"mailcow","password":"%s","password2":"%s","quota":1024,"active":1,"force_pw_update":0,"tls_enforce_in":0,"tls_enforce_out":0}' \
        "$(json_escape "$local_part")" "$(json_escape "$domain")" "$(json_escape "$name")" \
        "$(json_escape "$password")" "$(json_escape "$password")")

    if ! out=$(mail_api_post add/mailbox "$json" 2>&1); then
        mail_warn "création impossible pour $address : $out"
        failed=1
        continue
    fi

    case "$out" in
        *mailbox_added*)
            if [ "$generated" -eq 1 ]; then
                mail_info "boîte $address créée (mot de passe généré : $password_var dans .env)"
            else
                mail_info "boîte $address créée (mot de passe : $password_var dans .env)"
            fi
            created=$((created + 1))
            ;;
        *object_exists*)
            if [ "$generated" -eq 1 ]; then
                env_set "$password_var" ""
            fi
            mail_info "boîte $address déjà présente (mot de passe inchangé)"
            existing=$((existing + 1))
            ;;
        *)
            # Ne pas laisser dans .env un mot de passe qui n'a pas été appliqué.
            if [ "$generated" -eq 1 ]; then
                env_set "$password_var" ""
            fi
            mail_warn "API mailcow pour $address : $out"
            failed=1
            ;;
    esac
done
IFS=$old_ifs

printf '\n'
mail_info "domaine $domain : $created boîte(s) créée(s), $existing déjà présente(s)"
if [ "$failed" -ne 0 ]; then
    mail_warn "certaines boîtes n'ont pas pu être créées. Vérifiez les messages ci-dessus."
    exit 1
fi
printf 'Les mots de passe sont dans .env, variables MAILBOX_*_PASSWORD\n'
printf '(ou AZURIOM/FORGEJO/NEXTCLOUD_MAIL_PASSWORD pour noreply, git et cloud).\n'
