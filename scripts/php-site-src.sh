#!/bin/sh
# Clone le dépôt du site PHP dans stacks/web/php-site/src et génère son .env.
# Idempotent : un clone existant et un .env existant sont conservés.
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=${ENV_FILE:-.env}
SRC="stacks/web/php-site/src"

if [ ! -f "$ENV_FILE" ]; then
    echo "Erreur : $ENV_FILE introuvable. Lancer make init." >&2
    exit 1
fi

get_env() {
    sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

REPO_URL=$(get_env PHP_SITE_REPO_URL)
REPO_URL=${REPO_URL:-https://github.com/lx78WyY0J5/website.git}
REPO_REF=$(get_env PHP_SITE_REPO_REF)
REPO_REF=${REPO_REF:-main}

if [ -d "$SRC/.git" ]; then
    echo "→ site PHP déjà cloné : $SRC"
else
    if [ -d "$SRC" ] && [ -n "$(find "$SRC" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        echo "Erreur : $SRC existe mais n'est pas un dépôt Git." >&2
        echo "  Déplacez ou supprimez ce dossier, puis relancez make php-site-src." >&2
        exit 1
    fi

    command -v git >/dev/null 2>&1 || {
        echo "Erreur : git est requis pour cloner $REPO_URL." >&2
        exit 1
    }

    echo "→ clonage de $REPO_URL ($REPO_REF) dans $SRC"
    mkdir -p "$(dirname "$SRC")"
    if [ -n "$REPO_REF" ]; then
        git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$SRC"
    else
        git clone --depth 1 "$REPO_URL" "$SRC"
    fi
fi

if [ ! -f "$SRC/public/index.php" ]; then
    echo "Erreur : $SRC/public/index.php absent ; le dépôt cloné n'est pas le site attendu." >&2
    exit 1
fi

chmod -R a+rX "$SRC"

# Le site charge ses variables depuis src/.env (hors racine web).
# Le fichier est régénéré uniquement s'il est absent, ou si l'on force :
#   make php-site-env
if [ -f "$SRC/.env" ] && [ "${PHP_SITE_ENV_OVERWRITE:-false}" != "true" ]; then
    echo "→ $SRC/.env existe déjà (conservé ; make php-site-env pour le régénérer)"
    exit 0
fi

DOMAIN_NAME=$(get_env DOMAIN_NAME) || DOMAIN_NAME="localhost"
TLD=$(get_env TLD) || TLD=""
DOMAIN="${DOMAIN_NAME}${TLD}"

# `docker compose` développe les références ${DOMAIN_NAME} / ${DOMAIN} du .env,
# mais `get_env` les lit littéralement. On les développe ici aussi.
expand_env_value() {
    value=$1
    value=$(printf '%s' "$value" | sed \
        -e "s|\${DOMAIN_NAME}|${DOMAIN_NAME}|g" \
        -e "s|\${TLD}|${TLD}|g" \
        -e "s|\${DOMAIN}|${DOMAIN}|g")
    printf '%s' "$value"
}

PHP_DB_NAME=$(get_env PHP_DB_NAME)
PHP_DB_USER=$(get_env PHP_DB_USER)
PHP_DB_PASSWORD=$(get_env PHP_DB_PASSWORD)
WEBSITE_ADMIN_USERNAME=$(get_env WEBSITE_ADMIN_USERNAME)
WEBSITE_ADMIN_USERNAME=$(expand_env_value "$WEBSITE_ADMIN_USERNAME")
WEBSITE_ADMIN_USERNAME=${WEBSITE_ADMIN_USERNAME:-$DOMAIN_NAME}
WEBSITE_ADMIN_PASSWORD=$(get_env WEBSITE_ADMIN_PASSWORD)
WEBSITE_ADMIN_DISCORD_USER_ID=$(get_env WEBSITE_ADMIN_DISCORD_USER_ID)
WEBSITE_DISCORD_CLIENT_ID=$(get_env WEBSITE_DISCORD_CLIENT_ID)
WEBSITE_DISCORD_CLIENT_SECRET=$(get_env WEBSITE_DISCORD_CLIENT_SECRET)

for pair in \
    "DOMAIN=$DOMAIN" \
    "PHP_DB_NAME=$PHP_DB_NAME" \
    "PHP_DB_USER=$PHP_DB_USER" \
    "PHP_DB_PASSWORD=$PHP_DB_PASSWORD" \
    "WEBSITE_ADMIN_USERNAME=$WEBSITE_ADMIN_USERNAME" \
    "WEBSITE_ADMIN_PASSWORD=$WEBSITE_ADMIN_PASSWORD"
do
    key=${pair%%=*}
    value=${pair#*=}
    if [ -z "$value" ] || [ "$value" = "CHANGE_ME" ]; then
        echo "Erreur : $key manquant ou encore égal à CHANGE_ME dans $ENV_FILE." >&2
        echo "  Lancer make init pour générer les secrets." >&2
        exit 1
    fi
done

REDIRECT_URI=$(get_env WEBSITE_DISCORD_REDIRECT_URI)
REDIRECT_URI=$(expand_env_value "$REDIRECT_URI")
REDIRECT_URI=${REDIRECT_URI:-https://php.${DOMAIN}/discord/callback}

# Le site (dépôt website) lit des noms sans préfixe WEBSITE_ : on traduit ici.
{
    printf 'FORCE_DB_INIT=true'
    printf '\n'
    printf 'DB_IP="db-php"\n'
    printf 'DB_USER="%s"\n' "$PHP_DB_USER"
    printf 'DB_PASS="%s"\n' "$PHP_DB_PASSWORD"
    printf 'DB_NAME="%s"\n' "$PHP_DB_NAME"
    printf 'ADMIN_USERNAME="%s"\n' "$WEBSITE_ADMIN_USERNAME"
    printf 'ADMIN_PASSWORD="%s"\n' "$WEBSITE_ADMIN_PASSWORD"
    printf 'ADMIN_EMAIL="%s@%s"\n' "$WEBSITE_ADMIN_USERNAME" "$DOMAIN"
    printf 'ADMIN_DISCORD_USER_ID="%s"\n' "$WEBSITE_ADMIN_DISCORD_USER_ID"
    printf 'WEB_DOMAIN="%s"\n' "$DOMAIN"
    printf '\n'
    printf '# OAuth Discord\n'
    printf 'DISCORD_CLIENT_ID="%s"\n' "$WEBSITE_DISCORD_CLIENT_ID"
    printf 'DISCORD_CLIENT_SECRET="%s"\n' "$WEBSITE_DISCORD_CLIENT_SECRET"
    printf 'DISCORD_REDIRECT_URI="%s"\n' "$REDIRECT_URI"
} > "$SRC/.env"

echo "→ .env généré pour php-site : $SRC/.env"
