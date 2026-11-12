#!/bin/sh
# =============================================================================
# Restauration d'une sauvegarde produite par scripts/backup.sh.
# Commande : CONFIRM=yes ./scripts/restore.sh backups/AAAA-MM-JJ_HHMMSS
# =============================================================================
set -eu

cd "$(dirname "$0")/.."
BACKUP=${1:-}
[ -n "$BACKUP" ] || { echo "Usage : CONFIRM=yes $0 backups/AAAA-MM-JJ_HHMMSS" >&2; exit 1; }
[ -f "$BACKUP/manifest.txt" ] || { echo "Erreur : $BACKUP ne contient pas de manifest.txt" >&2; exit 1; }
[ "${CONFIRM:-no}" = "yes" ] || { echo "Restauration destructive. Relancer avec CONFIRM=yes." >&2; exit 1; }

ENV_FILE=".env"
[ -f "$ENV_FILE" ] || { echo "Erreur : .env introuvable." >&2; exit 1; }
get_env() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1; }

echo "ATTENTION : les données actuelles vont être remplacées par $BACKUP"
echo "→ arrêt des applications"
docker compose stop || true

echo "→ démarrage des bases"
docker compose up -d db-php db-azuriom db-nextcloud db-forgejo

for db in db-php db-azuriom db-nextcloud db-forgejo; do
    i=0
    until [ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$db" 2>/dev/null || true)" = "healthy" ]; do
        i=$((i + 1))
        [ "$i" -gt 60 ] && { echo "Erreur : $db n'est pas prêt." >&2; exit 1; }
        sleep 2
    done
done

# Sur un volume neuf, PostgreSQL/MariaDB peuvent répondre « healthy » pendant
# l'initialisation temporaire. Attendre une vraie requête SQL avant d'importer.
wait_mariadb() {
    db=$1
    pass=$2
    i=0
    until docker exec -e MYSQL_PWD="$pass" "$db" mariadb -uroot -e 'SELECT 1' >/dev/null 2>&1; do
        i=$((i + 1))
        [ "$i" -gt 120 ] && { echo "Erreur : $db ne répond pas aux requêtes SQL." >&2; exit 1; }
        sleep 2
    done
}

wait_postgres() {
    i=0
    until docker exec -e PGPASSWORD="$(get_env FORGEJO_DB_PASSWORD)" db-forgejo \
        psql -U "$(get_env FORGEJO_DB_USER)" -d "$(get_env FORGEJO_DB_NAME)" \
        -c 'SELECT 1' >/dev/null 2>&1; do
        i=$((i + 1))
        [ "$i" -gt 120 ] && { echo "Erreur : db-forgejo ne répond pas aux requêtes SQL." >&2; exit 1; }
        sleep 2
    done
}

wait_mariadb db-php "$(get_env PHP_DB_ROOT_PASSWORD)"
wait_mariadb db-azuriom "$(get_env AZURIOM_DB_ROOT_PASSWORD)"
wait_mariadb db-nextcloud "$(get_env NEXTCLOUD_DB_ROOT_PASSWORD)"
wait_postgres

if [ -s "$BACKUP/db-php.sql" ]; then
    echo "→ restauration db-php"
    docker exec -i -e MYSQL_PWD="$(get_env PHP_DB_ROOT_PASSWORD)" db-php \
        mariadb -uroot < "$BACKUP/db-php.sql"
fi

if [ -s "$BACKUP/db-azuriom.sql" ]; then
    echo "→ restauration db-azuriom"
    docker exec -i -e MYSQL_PWD="$(get_env AZURIOM_DB_ROOT_PASSWORD)" db-azuriom \
        mariadb -uroot < "$BACKUP/db-azuriom.sql"
fi

if [ -s "$BACKUP/db-nextcloud.sql" ]; then
    echo "→ restauration db-nextcloud"
    docker exec -i -e MYSQL_PWD="$(get_env NEXTCLOUD_DB_ROOT_PASSWORD)" db-nextcloud \
        mariadb -uroot < "$BACKUP/db-nextcloud.sql"
fi

if [ -s "$BACKUP/db-forgejo.sql" ]; then
    echo "→ restauration db-forgejo"
    docker exec -i -e PGPASSWORD="$(get_env FORGEJO_DB_PASSWORD)" db-forgejo \
        psql -v ON_ERROR_STOP=1 -U "$(get_env FORGEJO_DB_USER)" \
        -d "$(get_env FORGEJO_DB_NAME)" < "$BACKUP/db-forgejo.sql"
fi

for archive in "$BACKUP"/volume-*.tar.gz; do
    [ -e "$archive" ] || continue
    name=${archive##*/}
    name=${name#volume-}
    name=${name%.tar.gz}
    echo "→ restauration du volume $name"
    docker run --rm \
        -v "$name":/target \
        -v "$(pwd)/$BACKUP":/backup:ro \
        alpine:3.24 \
        sh -c "rm -rf /target/* /target/.[!.]* /target/..?* 2>/dev/null || true; tar xzf /backup/$(basename "$archive") -C /target"
done

echo "→ redémarrage de l'infrastructure"
docker compose up -d --remove-orphans
echo "Restauration terminée."
