#!/bin/sh
# =============================================================================
# Vérifie que le runner Forgejo Actions est enregistré et en ligne.
#
# Le runner s'enregistre tout seul au premier démarrage (entrypoint du
# conteneur forgejo-runner). Ce script attend qu'il soit visible côté Forgejo,
# puis affiche ses labels. Appelé automatiquement par `make up` et
# `make up-service SERVICE=forgejo` avant l'import des dépôts GitHub.
#
# Lancement manuel :
#   make forgejo-runner
# =============================================================================
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=${ENV_FILE:-.env}
[ -f "$ENV_FILE" ] || { echo "Erreur : $ENV_FILE introuvable. Lancer make init." >&2; exit 1; }

ENV_DUMP=$(docker compose --env-file "$ENV_FILE" config --environment)
get_env() {
    printf '%s\n' "$ENV_DUMP" | sed -n "s/^$1=//p" | tail -n 1
}

FORGEJO_ADMIN_NAME=$(get_env FORGEJO_ADMIN_NAME)
FORGEJO_ADMIN_PASSWORD=$(get_env FORGEJO_ADMIN_PASSWORD)
FORGEJO_API_TOKEN=$(get_env FORGEJO_API_TOKEN)
RUNNER_NAME=$(get_env FORGEJO_RUNNER_NAME)
[ -n "$RUNNER_NAME" ] || RUNNER_NAME=forgejo-runner
WAIT=$(get_env FORGEJO_RUNNER_WAIT)
[ -n "$WAIT" ] || WAIT=120

case "$WAIT" in
    ''|*[!0-9]*)
        echo "Erreur : FORGEJO_RUNNER_WAIT doit être un nombre de secondes." >&2
        exit 1
        ;;
esac

compose() {
    docker compose --env-file "$ENV_FILE" "$@"
}

api_get() {
    compose exec -T \
        -e FG_USER="$FORGEJO_ADMIN_NAME" \
        -e FG_PASS="$FORGEJO_ADMIN_PASSWORD" \
        -e FG_TOKEN="$FORGEJO_API_TOKEN" \
        forgejo sh -c '
            path=$1
            if [ -n "${FG_TOKEN:-}" ]; then
                set -- -H "Authorization: token $FG_TOKEN"
            else
                set -- -u "$FG_USER:$FG_PASS"
            fi
            curl -sS "$@" "http://127.0.0.1:3000/api/v1$path"
        ' sh "$1" < /dev/null
}

if [ -z "$FORGEJO_ADMIN_NAME" ] || { [ -z "$FORGEJO_ADMIN_PASSWORD" ] && [ -z "$FORGEJO_API_TOKEN" ]; }; then
    echo "Erreur : identifiants API Forgejo manquants (FORGEJO_ADMIN_* ou FORGEJO_API_TOKEN)." >&2
    exit 1
fi

echo "→ vérification du runner Forgejo Actions"
tries=0
while [ "$tries" -lt "$WAIT" ]; do
    RUNNERS=$(api_get /admin/actions/runners 2>/dev/null || true)
    if command -v jq >/dev/null 2>&1 && printf '%s' "$RUNNERS" | jq -e 'type == "array"' >/dev/null 2>&1; then
        ONLINE=$(printf '%s' "$RUNNERS" | jq -r --arg name "$RUNNER_NAME" \
            '[.[] | select(.name == $name and (.status == "idle" or .status == "active"))] | length')
        if [ "$ONLINE" -gt 0 ]; then
            printf '%s' "$RUNNERS" | jq -r --arg name "$RUNNER_NAME" \
                '.[] | select(.name == $name and (.status == "idle" or .status == "active")) | "  - \(.name) : \(.status) (\(.labels // [] | join(", ")))"'
            echo "→ runner Forgejo Actions en ligne"
            exit 0
        fi
    else
        if printf '%s' "$RUNNERS" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"(idle|active)"'; then
            echo "→ runner Forgejo Actions en ligne"
            exit 0
        fi
    fi

    tries=$((tries + 2))
    sleep 2
done

echo "Attention : le runner « $RUNNER_NAME » n'est pas encore en ligne après ${WAIT}s." >&2
echo "Vérifier : sudo make logs-service SERVICE=forgejo-runner" >&2
if [ -n "${RUNNERS:-}" ]; then
    echo "État renvoyé par Forgejo :" >&2
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$RUNNERS" | jq . >&2 2>/dev/null || printf '%s\n' "$RUNNERS" >&2
    else
        printf '%s\n' "$RUNNERS" >&2
    fi
fi
exit 1
