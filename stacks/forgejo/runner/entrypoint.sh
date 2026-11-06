#!/bin/sh
# =============================================================================
# Enregistre automatiquement le runner Forgejo Actions (une seule fois) puis
# démarre le daemon. L'enregistrement est stocké dans le volume /data.
#
# Variables :
#   FORGEJO_INSTANCE_URL       URL interne de Forgejo (http://forgejo:3000)
#   FORGEJO_ADMIN_NAME         Compte admin utilisé pour créer le runner
#   FORGEJO_ADMIN_PASSWORD     Mot de passe admin
#   FORGEJO_RUNNER_NAME        Nom affiché du runner
#   FORGEJO_RUNNER_LABELS      Labels séparés par des virgules
#   FORGEJO_RUNNER_CAPACITY    Jobs simultanés
#   FORGEJO_RUNNER_TIMEOUT     Durée max d'un job (ex: 3h)
#   FORGEJO_RUNNER_NETWORK     Réseau Docker des conteneurs de job
#   FORGEJO_RUNNER_DOCKER_HOST automount (socket Docker dans les jobs) ou -
# =============================================================================
set -eu

DATA_DIR=${DATA_DIR:-/data}
CONFIG=${FORGEJO_RUNNER_CONFIG:-$DATA_DIR/config.yml}
INSTANCE_URL=${FORGEJO_INSTANCE_URL:-http://forgejo:3000}
INSTANCE_URL=${INSTANCE_URL%/}
RUNNER_NAME=${FORGEJO_RUNNER_NAME:-forgejo-runner}
RUNNER_LABELS=${FORGEJO_RUNNER_LABELS:-ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-latest}
RUNNER_CAPACITY=${FORGEJO_RUNNER_CAPACITY:-2}
RUNNER_TIMEOUT=${FORGEJO_RUNNER_TIMEOUT:-3h}
RUNNER_NETWORK=${FORGEJO_RUNNER_NETWORK:-}
RUNNER_DOCKER_HOST=${FORGEJO_RUNNER_DOCKER_HOST:-automount}
RUNNER_LOG_LEVEL=${FORGEJO_RUNNER_LOG_LEVEL:-info}

log() {
    printf '%s\n' "$*"
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

yaml_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

api() {
    method=$1
    path=$2
    data=${3:-}
    if [ -n "$data" ]; then
        curl -sS -u "$FORGEJO_ADMIN_NAME:$FORGEJO_ADMIN_PASSWORD" \
            -H "Content-Type: application/json" \
            -X "$method" "$INSTANCE_URL/api/v1$path" -d "$data"
    else
        curl -sS -u "$FORGEJO_ADMIN_NAME:$FORGEJO_ADMIN_PASSWORD" \
            -X "$method" "$INSTANCE_URL/api/v1$path"
    fi
}

mkdir -p "$DATA_DIR/cache"
cd "$DATA_DIR"

log "→ attente de Forgejo ($INSTANCE_URL)"
tries=0
until curl -fsS -o /dev/null "$INSTANCE_URL/api/v1/version" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 90 ]; then
        echo "Forgejo injoignable : $INSTANCE_URL" >&2
        exit 1
    fi
    sleep 2
done

if [ -z "${FORGEJO_ADMIN_NAME:-}" ] || [ -z "${FORGEJO_ADMIN_PASSWORD:-}" ]; then
    echo "FORGEJO_ADMIN_NAME et FORGEJO_ADMIN_PASSWORD sont requis pour enregistrer le runner." >&2
    exit 1
fi

# Le compte admin est créé par forgejo-admin.sh juste après le démarrage de
# Forgejo : attendre que l'API admin réponde avant de tenter l'enregistrement.
tries=0
until api GET /admin/actions/runners | jq -e 'type == "array"' >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 60 ]; then
        echo "Authentification admin Forgejo impossible pour enregistrer le runner." >&2
        echo "Vérifier FORGEJO_ADMIN_NAME / FORGEJO_ADMIN_PASSWORD." >&2
        exit 1
    fi
    sleep 2
done

# Si le runner a été supprimé côté Forgejo, le fichier de configuration local
# n'est plus valide : on le supprime pour provoquer un nouvel enregistrement.
if [ -s "$CONFIG" ] && grep -q '^ *uuid:' "$CONFIG"; then
    OLD_UUID=$(sed -n 's/^ *uuid: *//p' "$CONFIG" | head -n 1)
    if ! api GET /admin/actions/runners \
            | jq -e --arg uuid "$OLD_UUID" \
                'type == "array" and any(.[]; .uuid == $uuid)' >/dev/null 2>&1; then
        log "→ runner $OLD_UUID absent de Forgejo : nouvel enregistrement"
        rm -f "$CONFIG"
    fi
fi

if [ ! -s "$CONFIG" ]; then
    # Supprime les anciens runners portant le même nom, pour éviter les
    # doublons après une suppression/recréation du volume (l'ancien runner peut
    # encore apparaître « idle » quelques minutes côté Forgejo).
    OLD_IDS=$(api GET /admin/actions/runners \
        | jq -r --arg name "$RUNNER_NAME" \
            'if type == "array" then [.[] | select(.name == $name) | .id] | .[] else empty end' \
            2>/dev/null || true)
    for old_id in $OLD_IDS; do
        log "→ suppression de l'ancien runner #$old_id"
        api DELETE "/admin/actions/runners/$old_id" >/dev/null || true
    done

    log "→ enregistrement du runner « $RUNNER_NAME »"
    RESPONSE=$(api POST /admin/actions/runners \
        "{\"name\":\"$(json_escape "$RUNNER_NAME")\"}")
    UUID=$(printf '%s' "$RESPONSE" | jq -r '.uuid // empty' 2>/dev/null || true)
    TOKEN=$(printf '%s' "$RESPONSE" | jq -r '.token // empty' 2>/dev/null || true)
    if [ -z "$UUID" ] || [ -z "$TOKEN" ]; then
        echo "Enregistrement du runner impossible. Réponse de Forgejo :" >&2
        printf '%s\n' "$RESPONSE" >&2
        exit 1
    fi

    LABELS_YAML=""
    OLD_IFS=$IFS
    IFS=','
    for label in $RUNNER_LABELS; do
        label=$(printf '%s' "$label" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$label" ] || continue
        LABELS_YAML="$LABELS_YAML
    - \"$(yaml_escape "$label")\""
    done
    IFS=$OLD_IFS

    cat > "$CONFIG" <<EOF
log:
  level: $RUNNER_LOG_LEVEL
  job_level: $RUNNER_LOG_LEVEL

runner:
  file: $DATA_DIR/.runner
  capacity: $RUNNER_CAPACITY
  timeout: $RUNNER_TIMEOUT
  fetch_interval: 2s
  labels:$LABELS_YAML

cache:
  enabled: true
  dir: $DATA_DIR/cache

container:
  network: "$RUNNER_NETWORK"
  privileged: false
  valid_volumes: []
  docker_host: "$RUNNER_DOCKER_HOST"

host:
  workdir_parent:

server:
  connections:
    forgejo:
      url: $INSTANCE_URL/
      uuid: $UUID
      token: $TOKEN
EOF
    chmod 600 "$CONFIG"
    log "→ runner enregistré (uuid: $UUID)"
fi

log "→ démarrage du runner Forgejo Actions"
exec forgejo-runner daemon --config "$CONFIG"
