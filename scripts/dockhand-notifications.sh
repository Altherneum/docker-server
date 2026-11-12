#!/bin/sh
# =============================================================================
# Configure le canal de notifications Dockhand depuis .env.
# Appelé automatiquement par `make up` et `make up-service SERVICE=dockhand`.
# Nécessite DOCKHAND_AUTO_NOTIFICATIONS=true dans .env.
# Idempotent : met à jour le canal correspondant à l'URL ou au nom, puis
# l'attache à l'environnement Docker local avec tous les événements actifs.
# =============================================================================
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=${ENV_FILE:-.env}
CONTAINER=${DOCKHAND_CONTAINER:-dockhand}
DATA_DB=${DOCKHAND_DB_PATH:-/app/data/db/dockhand.db}
SOCKET_PATH=/var/run/docker.sock
[ -f "$ENV_FILE" ] || { echo "Erreur : $ENV_FILE introuvable. Lancer make init." >&2; exit 1; }

# Docker Compose résout les variables du .env.
ENV_DUMP=$(docker compose --env-file "$ENV_FILE" config --environment)
get_env() {
    printf '%s\n' "$ENV_DUMP" | sed -n "s/^$1=//p" | tail -n 1
}

AUTO=$(get_env DOCKHAND_AUTO_NOTIFICATIONS)
[ "$AUTO" = "true" ] || exit 0

WEBHOOK_URL=$(get_env DOCKHAND_NOTIFICATION_WEBHOOK_URL)
NOTIFICATION_NAME=$(get_env DOCKHAND_NOTIFICATION_NAME)
[ -n "$NOTIFICATION_NAME" ] || NOTIFICATION_NAME=Dockhand

if [ -z "$WEBHOOK_URL" ] || [ "$WEBHOOK_URL" = "CHANGE_ME" ]; then
    echo "→ notifications Dockhand non configurées : DOCKHAND_NOTIFICATION_WEBHOOK_URL est vide."
    exit 0
fi

# Types d'événements connus de cette version de Dockhand.
# Les événements d'environnement sont attachés à l'environnement local ;
# les événements système restent attachés au canal de notification.
ENV_EVENT_TYPES="container_started,container_stopped,container_restarted,container_exited,container_unhealthy,container_healthy,container_oom,container_updated,image_pulled,container_scheduled_start,container_scheduled_stop,container_scheduled_failed,auto_update_success,auto_update_failed,auto_update_blocked,updates_detected,newer_version_available,batch_update_success,git_sync_success,git_sync_failed,git_sync_skipped,stack_started,stack_stopped,stack_deployed,stack_deploy_failed,vulnerability_critical,vulnerability_high,vulnerability_any,backup_success,backup_failed,restore_success,restore_failed,environment_offline,environment_online,disk_space_warning,image_prune_success,image_prune_failed"
SYSTEM_EVENT_TYPES="repo_prune_success,repo_prune_failed,repo_check_success,repo_check_failed,repo_verify_success,repo_verify_failed,license_expiring"
ALL_EVENT_TYPES="$ENV_EVENT_TYPES,$SYSTEM_EVENT_TYPES"

json_array() {
    printf '%s' "$1" | sed 's/,/","/g; s/^/["/; s/$/"]/'
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

sql_escape() {
    printf '%s' "$1" | sed "s/'/''/g"
}

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

# L'environnement Docker local doit exister pour recevoir les événements
# d'environnement. Il est normalement créé par dockhand-local-env.sh.
ENV_ID=
tries=0
while [ "$tries" -lt 30 ]; do
    ENV_ID=$(docker exec "$CONTAINER" sqlite3 "$DATA_DB" \
        "SELECT id FROM environments WHERE connection_type = 'socket' AND socket_path = '$SOCKET_PATH' ORDER BY id LIMIT 1;" \
        2>/dev/null) || ENV_ID=
    [ -n "$ENV_ID" ] && break
    tries=$((tries + 1))
    sleep 2
done

URL_SQL=$(sql_escape "$WEBHOOK_URL")
NAME_SQL=$(sql_escape "$NOTIFICATION_NAME")

# Retrouve le canal par URL (prioritaire) ou par nom pour rester idempotent.
NOTIF_ID=$(docker exec "$CONTAINER" sqlite3 "$DATA_DB" \
    "SELECT n.id FROM notification_settings n, json_each(n.config, '$.urls') u WHERE n.type = 'apprise' AND u.value = '$URL_SQL' ORDER BY n.id LIMIT 1;" \
    2>/dev/null) || NOTIF_ID=
if [ -z "$NOTIF_ID" ]; then
    NOTIF_ID=$(docker exec "$CONTAINER" sqlite3 "$DATA_DB" \
        "SELECT id FROM notification_settings WHERE type = 'apprise' AND name = '$NAME_SQL' ORDER BY id LIMIT 1;" \
        2>/dev/null) || NOTIF_ID=
fi

NAME_JSON=$(json_escape "$NOTIFICATION_NAME")
URL_JSON=$(json_escape "$WEBHOOK_URL")
EVENTS_JSON=$(json_array "$ALL_EVENT_TYPES")

if [ -n "$NOTIF_ID" ]; then
    METHOD=PUT
    API_PATH="/api/notifications/$NOTIF_ID"
    BODY=$(printf '{"name":"%s","enabled":true,"config":{"urls":["%s"]},"eventTypes":%s}' \
        "$NAME_JSON" "$URL_JSON" "$EVENTS_JSON")
else
    METHOD=POST
    API_PATH="/api/notifications"
    BODY=$(printf '{"type":"apprise","name":"%s","enabled":true,"config":{"urls":["%s"]},"eventTypes":%s}' \
        "$NAME_JSON" "$URL_JSON" "$EVENTS_JSON")
fi

RESULT=$(docker exec "$CONTAINER" curl -sS \
    -X "$METHOD" "http://127.0.0.1:3000$API_PATH" \
    -H 'Content-Type: application/json' \
    -d "$BODY" \
    -w '\n%{http_code}' 2>&1) || {
    echo "Erreur : configuration du canal de notifications Dockhand impossible." >&2
    printf '%s\n' "$RESULT" >&2
    exit 1
}

STATUS=$(printf '%s\n' "$RESULT" | tail -n 1)
RESPONSE_BODY=$(printf '%s\n' "$RESULT" | sed '$d')

case "$STATUS" in
    200|201)
        ;;
    401|403)
        echo "Attention : l'authentification Dockhand est déjà active ; notifications non configurées." >&2
        echo "            Configurer le canal manuellement dans Settings > Notifications." >&2
        exit 1
        ;;
    *)
        echo "Erreur : configuration du canal de notifications impossible (HTTP $STATUS)." >&2
        printf '%s\n' "$RESPONSE_BODY" >&2
        exit 1
        ;;
esac

# Après création, relit l'identifiant depuis la base.
if [ -z "$NOTIF_ID" ]; then
    NOTIF_ID=$(docker exec "$CONTAINER" sqlite3 "$DATA_DB" \
        "SELECT n.id FROM notification_settings n, json_each(n.config, '$.urls') u WHERE n.type = 'apprise' AND u.value = '$URL_SQL' ORDER BY n.id LIMIT 1;" \
        2>/dev/null) || NOTIF_ID=
fi
if [ -z "$NOTIF_ID" ]; then
    echo "Erreur : le canal de notifications créé est introuvable." >&2
    exit 1
fi

# Attache le canal à l'environnement local avec tous les événements.
if [ -z "$ENV_ID" ]; then
    echo "Attention : environnement Docker local introuvable ; notifications d'environnement non liées." >&2
    echo "            Vérifier DOCKHAND_AUTO_LOCAL_ENV puis lancer make dockhand-local-env." >&2
    exit 1
fi

EVENTS_ENV_JSON=$(json_array "$ENV_EVENT_TYPES")
LINK_COUNT=$(docker exec "$CONTAINER" sqlite3 "$DATA_DB" \
    "SELECT COUNT(*) FROM environment_notifications WHERE environment_id = $ENV_ID AND notification_id = $NOTIF_ID;" \
    2>/dev/null) || LINK_COUNT=0

if [ "$LINK_COUNT" -gt 0 ]; then
    LINK_METHOD=PUT
    LINK_PATH="/api/environments/$ENV_ID/notifications/$NOTIF_ID"
    LINK_BODY=$(printf '{"enabled":true,"eventTypes":%s}' "$EVENTS_ENV_JSON")
else
    LINK_METHOD=POST
    LINK_PATH="/api/environments/$ENV_ID/notifications"
    LINK_BODY=$(printf '{"notificationId":%s,"enabled":true,"eventTypes":%s}' \
        "$NOTIF_ID" "$EVENTS_ENV_JSON")
fi

RESULT=$(docker exec "$CONTAINER" curl -sS \
    -X "$LINK_METHOD" "http://127.0.0.1:3000$LINK_PATH" \
    -H 'Content-Type: application/json' \
    -d "$LINK_BODY" \
    -w '\n%{http_code}' 2>&1) || {
    echo "Erreur : liaison du canal de notifications à l'environnement local impossible." >&2
    printf '%s\n' "$RESULT" >&2
    exit 1
}

STATUS=$(printf '%s\n' "$RESULT" | tail -n 1)
RESPONSE_BODY=$(printf '%s\n' "$RESULT" | sed '$d')

case "$STATUS" in
    200|201)
        echo "→ notifications Dockhand configurées : $NOTIFICATION_NAME, tous les événements actifs"
        ;;
    401|403)
        echo "Attention : l'authentification Dockhand est déjà active ; notifications non configurées." >&2
        exit 1
        ;;
    *)
        echo "Erreur : liaison du canal de notifications impossible (HTTP $STATUS)." >&2
        printf '%s\n' "$RESPONSE_BODY" >&2
        exit 1
        ;;
esac
