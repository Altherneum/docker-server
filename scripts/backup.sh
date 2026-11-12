#!/bin/sh
# =============================================================================
# Sauvegarde : dumps SQL + volumes applicatifs labellisés.
# Les volumes de bases ne sont pas archivés : les dumps sont la source de vérité.
# =============================================================================
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=".env"
[ -f "$ENV_FILE" ] || { echo "Erreur : .env introuvable. Lancer make init." >&2; exit 1; }

get_env() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1; }

DOMAIN_NAME=$(get_env DOMAIN_NAME)
TLD=$(get_env TLD)
DOMAIN="${DOMAIN_NAME}${TLD}"

STAMP=$(date +%Y-%m-%d_%H%M%S)
DIR="backups/$STAMP"
mkdir -p "$DIR"

running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)" = "true" ]
}

echo "→ sauvegarde dans $DIR"

# --- Bases de données -------------------------------------------------------
if running db-php; then
    echo "  - dump db-php"
    docker exec -e MYSQL_PWD="$(get_env PHP_DB_ROOT_PASSWORD)" db-php \
        mariadb-dump -uroot --all-databases --single-transaction --quick \
        --routines --events --triggers > "$DIR/db-php.sql"
else
    echo "  ! db-php non démarré : dump ignoré" >&2
fi

if running db-azuriom; then
    echo "  - dump db-azuriom"
    docker exec -e MYSQL_PWD="$(get_env AZURIOM_DB_ROOT_PASSWORD)" db-azuriom \
        mariadb-dump -uroot --all-databases --single-transaction --quick \
        --routines --events --triggers > "$DIR/db-azuriom.sql"
else
    echo "  ! db-azuriom non démarré : dump ignoré" >&2
fi

if running db-nextcloud; then
    echo "  - dump db-nextcloud"
    docker exec -e MYSQL_PWD="$(get_env NEXTCLOUD_DB_ROOT_PASSWORD)" db-nextcloud \
        mariadb-dump -uroot --all-databases --single-transaction --quick \
        --routines --events --triggers > "$DIR/db-nextcloud.sql"
else
    echo "  ! db-nextcloud non démarré : dump ignoré" >&2
fi

if running db-forgejo; then
    echo "  - dump db-forgejo"
    docker exec -e PGPASSWORD="$(get_env FORGEJO_DB_PASSWORD)" db-forgejo \
        pg_dump -U "$(get_env FORGEJO_DB_USER)" -d "$(get_env FORGEJO_DB_NAME)" \
        --clean --if-exists --no-owner --no-privileges > "$DIR/db-forgejo.sql"
else
    echo "  ! db-forgejo non démarré : dump ignoré" >&2
fi

# --- Volumes applicatifs ----------------------------------------------------
VOLUMES=$(docker volume ls -q --filter label=should.backup=true)
for volume in $VOLUMES; do
    echo "  - volume $volume"
    docker run --rm \
        -v "$volume":/source:ro \
        -v "$(pwd)/$DIR":/backup \
        alpine:3.24 \
        tar czf "/backup/volume-$volume.tar.gz" -C /source .
done

# Les archives sont créées par un conteneur root : les remettre à l'utilisateur
# courant avant de restreindre les permissions.
docker run --rm -v "$(pwd)/$DIR":/backup alpine:3.24 \
    sh -c 'chown -R "$1" /backup' _ "$(id -u):$(id -g)"

# --- Manifeste --------------------------------------------------------------
{
    echo "date=$STAMP"
    echo "host=$(uname -n)"
    echo "domain=$DOMAIN"
    echo "docker=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo inconnu)"
    echo "volumes:"
    for volume in $VOLUMES; do echo "  - $volume"; done
    echo "dumps:"
    for dump in "$DIR"/*.sql; do
        [ -e "$dump" ] || continue
        echo "  - $(basename "$dump")"
    done
} > "$DIR/manifest.txt"

chmod -R go-rwx "$DIR"
echo "Sauvegarde terminée : $DIR"
