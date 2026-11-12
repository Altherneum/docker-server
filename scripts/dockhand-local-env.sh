#!/bin/sh
# =============================================================================
# Enregistre automatiquement l'environnement Docker local dans Dockhand.
# Appelé automatiquement par `make up` et `make up-service SERVICE=dockhand`.
# Nécessite DOCKHAND_AUTO_LOCAL_ENV=true dans .env.
# Idempotent : ne touche pas à un environnement socket déjà configuré.
# =============================================================================
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=${ENV_FILE:-.env}
CONTAINER=${DOCKHAND_CONTAINER:-dockhand}
DATA_DB=${DOCKHAND_DB_PATH:-/app/data/db/dockhand.db}
SOCKET_PATH=/var/run/docker.sock
ENV_NAME=local
[ -f "$ENV_FILE" ] || { echo "Erreur : $ENV_FILE introuvable. Lancer make init." >&2; exit 1; }

# Docker Compose résout les variables du .env.
ENV_DUMP=$(docker compose --env-file "$ENV_FILE" config --environment)
get_env() {
    printf '%s\n' "$ENV_DUMP" | sed -n "s/^$1=//p" | tail -n 1
}

AUTO=$(get_env DOCKHAND_AUTO_LOCAL_ENV)
[ "$AUTO" = "true" ] || exit 0

# Attend que le conteneur soit démarré.
tries=0
while [ "$tries" -lt 90 ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" = "true" ]; then
        break
    fi
    tries=$((tries + 1))
    sleep 2
done
if [ "$tries" -ge 90 ]; then
    echo "Erreur : le conteneur $CONTAINER n'est pas démarré." >&2
    echo "Vérifier : make ps-service SERVICE=dockhand" >&2
    exit 1
fi

# Attend que l'API réponde (migrations et base SQLite prêtes).
tries=0
while [ "$tries" -lt 90 ]; do
    if docker exec "$CONTAINER" curl -fsS http://127.0.0.1:3000/api/health >/dev/null 2>&1; then
        break
    fi
    tries=$((tries + 1))
    sleep 2
done
if [ "$tries" -ge 90 ]; then
    echo "Erreur : l'API Dockhand ne répond pas après 180 secondes." >&2
    echo "Vérifier : make logs-service SERVICE=dockhand" >&2
    exit 1
fi

# Un environnement socket vers le socket Docker de l'hôte est-il déjà déclaré ?
# La lecture SQLite ne dépend pas de l'authentification Dockhand : le script
# reste donc sans effet une fois le premier lancement terminé.
COUNT=
tries=0
while [ "$tries" -lt 30 ]; do
    if COUNT=$(docker exec "$CONTAINER" sqlite3 "$DATA_DB" \
        "SELECT COUNT(*) FROM environments WHERE connection_type = 'socket' AND socket_path = '$SOCKET_PATH';" \
        2>/dev/null); then
        break
    fi
    COUNT=
    tries=$((tries + 1))
    sleep 2
done

case "$COUNT" in
    ''|*[!0-9]*)
        echo "Attention : impossible de lire la base Dockhand ; environnement local non vérifié." >&2
        exit 1
        ;;
esac

if [ "$COUNT" -gt 0 ]; then
    echo "→ environnement Docker local Dockhand déjà configuré ($SOCKET_PATH)"
    exit 0
fi

# Création via l'API locale. L'authentification Dockhand est désactivée sur une
# installation neuve, ce qui permet cet appel avant la création du compte admin.
RESULT=$(docker exec "$CONTAINER" curl -sS \
    -X POST http://127.0.0.1:3000/api/environments \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$ENV_NAME\",\"connectionType\":\"socket\",\"socketPath\":\"$SOCKET_PATH\",\"icon\":\"server\"}" \
    -w '\n%{http_code}' 2>&1) || {
    echo "Erreur : création de l'environnement Docker local impossible." >&2
    printf '%s\n' "$RESULT" >&2
    exit 1
}

STATUS=$(printf '%s\n' "$RESULT" | tail -n 1)
BODY=$(printf '%s\n' "$RESULT" | sed '$d')

case "$STATUS" in
    200|201)
        echo "→ environnement Docker local Dockhand créé : $ENV_NAME ($SOCKET_PATH)"
        ;;
    401|403)
        echo "Attention : l'authentification Dockhand est déjà active ; environnement local non créé." >&2
        echo "            Créer l'environnement manuellement dans Settings > Environments." >&2
        exit 1
        ;;
    409)
        echo "Attention : un environnement nommé « $ENV_NAME » existe déjà avec une autre connexion." >&2
        printf '%s\n' "$BODY" >&2
        exit 1
        ;;
    *)
        echo "Erreur : création de l'environnement Docker local impossible (HTTP $STATUS)." >&2
        printf '%s\n' "$BODY" >&2
        exit 1
        ;;
esac
