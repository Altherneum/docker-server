#!/bin/sh
# =============================================================================
# Initialisation locale : .env, secrets, htpasswd et réseaux Docker.
# Idempotent : les valeurs déjà renseignées ne sont jamais écrasées.
# =============================================================================
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=".env"

if [ ! -f "$ENV_FILE" ]; then
    cp .env.example "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "→ .env créé à partir de .env.example"
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "Erreur : openssl est requis (apk add openssl)." >&2
    exit 1
fi

get_env() {
    sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

set_env() {
    key=$1
    value=$2
    current=$(get_env "$key")

    if [ -z "$current" ]; then
        write_env_value "$key" "$value"
        return 0
    fi

    if [ "$current" = "CHANGE_ME" ]; then
        write_env_value "$key" "$value"
    fi
}

write_env_value() {
    key=$1
    value=$2
    escaped=$(printf '%s' "$value" | sed 's/[&|\\]/\\&/g')

    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${escaped}|" "$ENV_FILE"
        return 0
    fi

    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
}

gen_hex() {
    openssl rand -hex "$1"
}

# --- Secrets applicatifs ----------------------------------------------------
set_env TRAEFIK_DASHBOARD_PASSWORD "$(gen_hex 16)"
set_env PMA_ADMIN_PASSWORD       "$(gen_hex 16)"

set_env PHP_DB_ROOT_PASSWORD      "$(gen_hex 24)"
set_env PHP_DB_PASSWORD           "$(gen_hex 24)"
set_env WEBSITE_ADMIN_PASSWORD    "$(gen_hex 16)"

set_env AZURIOM_DB_ROOT_PASSWORD  "$(gen_hex 24)"
set_env AZURIOM_DB_PASSWORD       "$(gen_hex 24)"
set_env AZURIOM_APP_KEY           "base64:$(openssl rand -base64 32 | tr -d '\n')"
set_env AZURIOM_ADMIN_PASSWORD    "$(gen_hex 16)"
set_env AZURIOM_MAIL_PASSWORD     "$(gen_hex 24)"

set_env FORGEJO_DB_ROOT_PASSWORD  "$(gen_hex 24)"
set_env FORGEJO_DB_PASSWORD       "$(gen_hex 24)"
set_env FORGEJO_SECRET_KEY        "$(gen_hex 32)"
set_env FORGEJO_INTERNAL_TOKEN    "$(gen_hex 48)"
set_env FORGEJO_LFS_JWT_SECRET    "$(gen_hex 32)"
set_env FORGEJO_OAUTH2_JWT_SECRET "$(gen_hex 32)"
set_env FORGEJO_HTTP_USER         "forgejo"
set_env FORGEJO_ADMIN_PASSWORD    "$(gen_hex 16)"
set_env FORGEJO_HTTP_PASSWORD     "$(gen_hex 16)"
set_env FORGEJO_MAIL_PASSWORD     "$(gen_hex 24)"

set_env CODE_SERVER_PASSWORD      "$(gen_hex 16)"
set_env KEEWEB_UI_PASSWORD        "$(gen_hex 16)"
set_env CODE_SERVER_HTTP_PASSWORD "$(gen_hex 32)"
set_env KEEWEB_WEBDAV_PASSWORD    "$(gen_hex 16)"
set_env PMA_BLOWFISH_SECRET       "$(gen_hex 16)"

set_env VELOCITY_SECRET           "$(gen_hex 32)"
set_env MINECRAFT_RCON_PASSWORD   "$(gen_hex 24)"
set_env HARDEN_ADMIN_PASSWORD     "$(gen_hex 24)"

# --- GID du socket Docker (runner Forgejo Actions) --------------------------
# Le runner tourne avec l'UID 1000 et doit pouvoir accéder au socket Docker.
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null \
        || stat -f '%g' /var/run/docker.sock 2>/dev/null \
        || true)
    if [ -n "$DOCKER_GID" ]; then
        write_env_value DOCKER_GID "$DOCKER_GID"
    fi
fi

chmod 600 "$ENV_FILE"

# --- Fichiers htpasswd ------------------------------------------------------
write_htpasswd() {
    file=$1
    user=$2
    password=$3
    hash=$(openssl passwd -apr1 "$password" 2>/dev/null || openssl passwd -1 "$password")
    printf '%s:%s\n' "$user" "$hash" > "$file"
    chmod 644 "$file"
}

mkdir -p stacks/proxy/auth stacks/web/keeweb/auth
write_htpasswd stacks/proxy/auth/dashboard.htpasswd \
    "$(get_env TRAEFIK_DASHBOARD_USER)" "$(get_env TRAEFIK_DASHBOARD_PASSWORD)"
write_htpasswd stacks/proxy/auth/phpmyadmin.htpasswd \
    "$(get_env PMA_ADMIN_USER)" "$(get_env PMA_ADMIN_PASSWORD)"
write_htpasswd stacks/proxy/auth/code-server.htpasswd \
    "$(get_env CODE_SERVER_HTTP_USER)" "$(get_env CODE_SERVER_HTTP_PASSWORD)"
write_htpasswd stacks/proxy/auth/forgejo.htpasswd \
    "$(get_env FORGEJO_HTTP_USER)" "$(get_env FORGEJO_HTTP_PASSWORD)"
write_htpasswd stacks/web/keeweb/auth/keeweb.htpasswd \
    "$(get_env KEEWEB_UI_USER)" "$(get_env KEEWEB_UI_PASSWORD)"
write_htpasswd stacks/web/keeweb/auth/webdav.htpasswd \
    "$(get_env KEEWEB_WEBDAV_USER)" "$(get_env KEEWEB_WEBDAV_PASSWORD)"

# --- Réseaux Docker ---------------------------------------------------------
ENV_FILE="$ENV_FILE" ./scripts/ensure-networks.sh

echo
echo "Initialisation terminée."
echo "  - secrets générés dans .env (chmod 600) ;"
echo "  - htpasswd dans stacks/proxy/auth et stacks/web/keeweb/auth ;"
echo "  - réseaux Docker vérifiés."
echo
echo "À renseigner manuellement avant le premier démarrage :"
echo "  - DISCORD_BOT_TOKEN (bot Discord général) ;"
echo "  - MINECRAFT_DISCORD_TOKEN_* (un bot par serveur Minecraft) ;"
echo "  - AZURIOM_ADMIN_GAME_ID (UUID Minecraft de l'admin, mode mc-online)."
echo
echo "Si mailcow est utilisé, créer les boîtes noreply@ et git@ avec les"
echo "mots de passe déjà générés : AZURIOM_MAIL_PASSWORD, FORGEJO_MAIL_PASSWORD."
