#!/bin/sh
# =============================================================================
# mail-integrate.sh - prépare mailcow derrière Traefik.
#
# - installe docker-compose.override.yml dans MAILCOW_DIR ;
# - retire les ports 80/443 de nginx-mailcow (Traefik les publie) ;
# - connecte nginx-mailcow au réseau proxy ;
# - choisit un sous-réseau mailcow qui ne rentre pas en conflit avec Docker ;
# - désactive l'ACME de mailcow (certificat fourni par Traefik, web et SMTP/IMAP) ;
# - prépare une clé API mailcow pour créer le domaine sans l'interface.
#
# Usage : ./scripts/mail-integrate.sh
# =============================================================================
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MAIL_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/mail-lib.sh"
mail_load_env "$MAIL_ROOT"

# Même en cas d'erreur plus loin, .env doit rester modifiable par l'utilisateur.
trap 'mail_chown_user "$ENV_FILE"' 0

[ -n "$DOMAIN_NAME" ] || mail_die "DOMAIN_NAME manquant dans $ENV_FILE"
mail_domain_valid "$DOMAIN" || mail_die "DOMAIN invalide : $DOMAIN (renseignez DOMAIN_NAME et TLD dans .env, ex: monprojet et .fr)"

[ -d "$MAILCOW_DIR" ] || {
    cat >&2 <<EOF
Erreur : mailcow n'est pas installé dans $MAILCOW_DIR.

Installez-le d'abord :
  sudo make mail-setup
ou seulement préparer le dossier :
  sudo make mail-install

Puis relancez : sudo make mail-integrate
EOF
    exit 1
}

[ -f "$MAILCOW_DIR/docker-compose.yml" ] || mail_die "$MAILCOW_DIR/docker-compose.yml introuvable."
[ -f "$MAILCOW_CONF" ] || mail_die "$MAILCOW_CONF introuvable. Lancez ./generate_config.sh dans $MAILCOW_DIR."

# Mailcow récent lit .env, qui doit être un lien vers mailcow.conf.
if [ -L "$MAILCOW_DIR/.env" ] && [ ! -e "$MAILCOW_DIR/.env" ]; then
    rm -f "$MAILCOW_DIR/.env"
fi
if [ ! -e "$MAILCOW_DIR/.env" ] && [ ! -L "$MAILCOW_DIR/.env" ]; then
    ( cd "$MAILCOW_DIR" && ln -s mailcow.conf .env )
    mail_info "lien $MAILCOW_DIR/.env -> mailcow.conf créé"
elif [ ! -L "$MAILCOW_DIR/.env" ]; then
    mail_warn "$MAILCOW_DIR/.env n'est pas un lien vers mailcow.conf ; vérifiez votre installation mailcow."
fi

docker network inspect "$PROXY_NETWORK" >/dev/null 2>&1 || {
    mail_die "réseau Docker $PROXY_NETWORK introuvable. Lancez : sudo make ensure-networks"
}

# Hôte web de mailcow.
MAILCOW_HOSTNAME=$(mailcow_get MAILCOW_HOSTNAME)
if [ -z "$MAILCOW_HOSTNAME" ]; then
    MAILCOW_HOSTNAME="mail.$DOMAIN"
    mailcow_set MAILCOW_HOSTNAME "$MAILCOW_HOSTNAME"
    mail_info "MAILCOW_HOSTNAME=$MAILCOW_HOSTNAME ajouté à mailcow.conf"
fi
mail_domain_valid "$MAILCOW_HOSTNAME" || mail_die "MAILCOW_HOSTNAME invalide : $MAILCOW_HOSTNAME"

# --- ACME de mailcow -------------------------------------------------------
# Traefik gère le HTTPS web. Mailcow garde son certificat interne pour
# SMTP/IMAP : aucun ACME côté mailcow, donc aucune API DNS nécessaire.
mailcow_set SKIP_LETS_ENCRYPT y
mailcow_set ACME_DNS_CHALLENGE n
mail_info "ACME mailcow désactivé : certificat fourni par Traefik (copie via mail-cert-sync)"

HTTPS_PORT=$(mailcow_get HTTPS_PORT)
[ -n "$HTTPS_PORT" ] || HTTPS_PORT=443
case "$HTTPS_PORT" in
    ''|*[!0-9]*) mail_die "HTTPS_PORT invalide dans mailcow.conf : $HTTPS_PORT" ;;
esac

# --- Sous-réseau interne mailcow -------------------------------------------
current_subnet=$(mailcow_current_subnet)
if [ -n "$current_subnet" ]; then
    mailcow_base=$(mail_normalize_ipv4 "$current_subnet") || mail_die "sous-réseau mailcow illisible : $current_subnet"
    configured=$(env_get MAILCOW_IPV4_NETWORK)
    if [ -n "$configured" ]; then
        configured_base=$(mail_normalize_ipv4 "$configured" || true)
        if [ -n "$configured_base" ] && [ "$configured_base" != "$mailcow_base" ]; then
            mail_warn "le réseau mailcow existe déjà en ${mailcow_base}.0/24 ; MAILCOW_IPV4_NETWORK=$configured est ignoré."
        fi
    fi
    env_set MAILCOW_IPV4_NETWORK "$mailcow_base"
    mailcow_set IPV4_NETWORK "$mailcow_base"
    mail_info "sous-réseau mailcow existant : ${mailcow_base}.0/24"
else
    configured=$(env_get MAILCOW_IPV4_NETWORK)
    [ -n "$configured" ] || configured=$(mailcow_get IPV4_NETWORK)
    [ -n "$configured" ] || configured=172.22.1

    mailcow_base=$(mail_normalize_ipv4 "$configured") || mail_die "MAILCOW_IPV4_NETWORK invalide : $configured (attendu : 172.30.1 ou 172.30.1.0/24)"
    if mail_subnet_free "${mailcow_base}.0/24"; then
        mail_info "sous-réseau mailcow : ${mailcow_base}.0/24"
    else
        # 172.22.1 est le défaut mailcow, souvent en conflit avec un ancien réseau.
        if [ "$mailcow_base" = "172.22.1" ] && [ -z "$(env_get MAILCOW_IPV4_NETWORK)" ]; then
            mailcow_base=$(mail_pick_ipv4) || mail_die "aucun sous-réseau /24 libre trouvé dans 172.30.0.0/16 et 172.31.0.0/16."
            mail_info "172.22.1.0/24 est déjà utilisé ; sous-réseau mailcow choisi automatiquement : ${mailcow_base}.0/24"
        else
            mail_die "${mailcow_base}.0/24 est déjà utilisé par Docker. Choisissez un autre MAILCOW_IPV4_NETWORK dans .env (ex: 172.30.1)."
        fi
    fi

    env_set MAILCOW_IPV4_NETWORK "$mailcow_base"
    mailcow_set IPV4_NETWORK "$mailcow_base"
fi

# --- Clé API mailcow -------------------------------------------------------
# Elle permet à make mail-dkim de créer le domaine sans passer par l'UI.
api_key=$(env_get MAILCOW_API_KEY)
mailcow_api_key=$(mailcow_get API_KEY)
if [ -z "$api_key" ] && [ -n "$mailcow_api_key" ]; then
    api_key=$mailcow_api_key
    env_set MAILCOW_API_KEY "$api_key"
fi
if [ -z "$api_key" ]; then
    command -v openssl >/dev/null 2>&1 || mail_die "openssl est requis pour générer MAILCOW_API_KEY."
    api_key=$(openssl rand -hex 16)
    env_set MAILCOW_API_KEY "$api_key"
    mail_info "MAILCOW_API_KEY généré dans .env"
fi
case "$api_key" in
    *[!A-Za-z0-9-]*) mail_die "MAILCOW_API_KEY contient des caractères interdits (autorisés : a-z, A-Z, 0-9, -)." ;;
esac
mailcow_set API_KEY "$api_key"

api_allow=$(mailcow_get API_ALLOW_FROM | tr -d '[:space:]')
[ "$api_allow" = "invalid" ] && api_allow=""
case ",$api_allow," in
    *",${mailcow_base}.0/24,"*) ;;
    *) api_allow="${api_allow:+$api_allow,}${mailcow_base}.0/24" ;;
esac
case ",$api_allow," in
    *",127.0.0.1,"*) ;;
    *) api_allow="${api_allow:+$api_allow,}127.0.0.1" ;;
esac

# Si le réseau mailcow est en IPv6, php-fpm peut joindre nginx en IPv6.
ipv6_enabled=$(mailcow_get ENABLE_IPV6 | tr '[:upper:]' '[:lower:]')
case "$ipv6_enabled" in
    true|yes|y|1)
        ipv6_network=$(mailcow_get IPV6_NETWORK)
        [ -n "$ipv6_network" ] || ipv6_network="fd4d:6169:6c63:6f77::/64"
        case ",$api_allow," in
            *",$ipv6_network,"*) ;;
            *) api_allow="${api_allow:+$api_allow,}$ipv6_network" ;;
        esac
        ;;
esac
mailcow_set API_ALLOW_FROM "$api_allow"

# Recharge php-fpm uniquement si sa clé API ou sa liste d'IP a changé : c'est
# lui qui valide les appels, et son environnement est figé à la création.
if mailcow_service_running php-fpm-mailcow; then
    fpm_id=$(mailcow_compose ps -q php-fpm-mailcow 2>/dev/null | head -n1)
    fpm_env=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$fpm_id" 2>/dev/null || true)
    fpm_key=$(printf '%s\n' "$fpm_env" | sed -n 's/^API_KEY=//p' | head -n1)
    fpm_allow=$(printf '%s\n' "$fpm_env" | sed -n 's/^API_ALLOW_FROM=//p' | head -n1)

    if [ "$fpm_key" = "$api_key" ] && [ "$fpm_allow" = "$api_allow" ]; then
        mail_info "php-fpm-mailcow déjà à jour (clé API et IP autorisées inchangées)"
    elif mailcow_compose up -d php-fpm-mailcow >/dev/null 2>&1; then
        mail_info "php-fpm-mailcow recréé pour synchroniser la clé API"
    else
        mail_warn "impossible de recréer php-fpm-mailcow ; relancez make mail-up."
    fi
fi

# --- Override Traefik ------------------------------------------------------
template="$MAIL_ROOT/stacks/mail/traefik.override.yaml.template"
[ -f "$template" ] || mail_die "template introuvable : $template"

sed \
    -e "s|@@PROXY_NETWORK@@|$PROXY_NETWORK|g" \
    -e "s|@@DOMAIN_REGEX@@|$(printf '%s' "$DOMAIN" | sed 's/\./[.]/g')|g" \
    -e "s|@@MAILCOW_HOSTNAME@@|$MAILCOW_HOSTNAME|g" \
    -e "s|@@DOMAIN@@|$DOMAIN|g" \
    -e "s|@@MAILCOW_HTTPS_PORT@@|$HTTPS_PORT|g" \
    "$template" > "$MAILCOW_DIR/docker-compose.override.yml"

mail_info "override écrit dans $MAILCOW_DIR/docker-compose.override.yml"

# Valide le merge Compose avant de laisser l'utilisateur démarrer mailcow.
if ! config_err=$( cd "$MAILCOW_DIR" && docker compose -f docker-compose.yml -f docker-compose.override.yml config 2>&1 >/dev/null ); then
    printf '%s\n' "$config_err" >&2
    mail_die "docker compose config a échoué : l'override mailcow est invalide."
fi
mail_info "docker compose config : OK"

cat <<EOF

Mailcow est prêt :
  sudo make mail-setup
  sudo make mail-check

Rappel :
  - MAIL_CREATE_KEYS=yes régénère les clés DKIM et affiche les TXT à publier.
  - MAIL_CREATE_KEYS=no importe la clé privée existante (DNS inchangé).
  - SMTP/IMAP réutilisent le certificat de Traefik (mail-cert-sync). Aucune API
    DNS n'est nécessaire.
EOF

mail_chown_user "$ENV_FILE"
