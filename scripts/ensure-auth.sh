#!/bin/sh
# =============================================================================
# Garantit la présence des fichiers htpasswd utilisés par Traefik et KeeWeb.
#
# Les fichiers sont ignorés par Git : après un `git pull`, un nouveau service
# n'a donc pas son fichier d'authentification. Si un fichier manque (ou ne
# contient pas d'utilisateur), ce script relance init.sh, qui est idempotent.
# =============================================================================
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=${ENV_FILE:-.env}

[ -f "$ENV_FILE" ] || {
    echo "Erreur : $ENV_FILE introuvable. Lancer make init." >&2
    exit 1
}

PROXY_TEMPLATE="stacks/proxy/templates/dynamic/dynamic.yml.template"
KEEWEB_HTTPD="stacks/web/keeweb/httpd.conf"

# Déduire les chemins des références réelles pour ne pas maintenir une seconde
# liste de fichiers htpasswd à la main.
proxy_files=$(sed -n \
    's|.*usersFile:[[:space:]]*"/etc/traefik/auth/\([^"]*\)".*|stacks/proxy/auth/\1|p' \
    "$PROXY_TEMPLATE")
keeweb_files=$(sed -n \
    's|.*AuthUserFile[[:space:]]*"/usr/local/apache2/auth/\([^"]*\)".*|stacks/web/keeweb/auth/\1|p' \
    "$KEEWEB_HTTPD")

is_valid_file() {
    file=$1
    [ -s "$file" ] || return 1
    user=$(sed -n '1s/:.*//p' "$file")
    [ -n "$user" ]
}

missing=""
for file in $proxy_files $keeweb_files; do
    if ! is_valid_file "$file"; then
        missing="$missing $file"
    fi
done

if [ -z "$missing" ]; then
    exit 0
fi

echo "→ fichiers d'authentification absents ou invalides :$missing"
echo "  génération avec make init..."

# init.sh crée aussi les secrets absents de .env (nouveaux services).
# Les réseaux sont gérés séparément par make up / make up-service.
SKIP_NETWORKS=true ./scripts/init.sh

for file in $proxy_files $keeweb_files; do
    if ! is_valid_file "$file"; then
        echo "Erreur : $file est toujours absent ou invalide après make init." >&2
        exit 1
    fi
done

echo "→ fichiers d'authentification prêts."
