#!/bin/sh
# =============================================================================
# Importe les dépôts d'une organisation GitHub dans Forgejo, puis configure un
# miroir push Forgejo -> GitHub.
#
# Appelé automatiquement par `make up` et `make up-service SERVICE=forgejo`.
# Lancement manuel :
#   make forgejo-mirror
#   make forgejo-mirror FORGEJO_MIRROR_ARGS=--dry-run
#
# Le script est idempotent : un dépôt déjà présent n'est pas réimporté, et un
# miroir push déjà configuré n'est pas recréé.
# =============================================================================
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=${ENV_FILE:-.env}
[ -f "$ENV_FILE" ] || { echo "Erreur : $ENV_FILE introuvable. Lancer make init." >&2; exit 1; }

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            echo "Usage : $0 [--dry-run]"
            exit 0
            ;;
        *)
            echo "Option inconnue : $arg" >&2
            exit 1
            ;;
    esac
done

# Docker Compose résout les variables du .env (ex: FORGEJO_OWNER=${FORGEJO_ADMIN_NAME}).
ENV_DUMP=$(docker compose --env-file "$ENV_FILE" config --environment)
get_env() {
    printf '%s\n' "$ENV_DUMP" | sed -n "s/^$1=//p" | tail -n 1
}

ORG_URL=$(get_env FORGEJO_GITHUB_ORG_URL | sed 's/[[:space:]]*$//')
if [ -z "$ORG_URL" ]; then
    echo "→ FORGEJO_GITHUB_ORG_URL est vide : import GitHub dans Forgejo ignoré."
    exit 0
fi

# Extrait le nom de l'organisation depuis une URL GitHub ou un nom simple.
GITHUB_ORG=$(printf '%s' "$ORG_URL" | sed 's#/$##; s#\.git$##')
case "$GITHUB_ORG" in
    *github.com/*) GITHUB_ORG=${GITHUB_ORG#*github.com/} ;;
    *github.com:*) GITHUB_ORG=${GITHUB_ORG#*github.com:} ;;
esac
GITHUB_ORG=${GITHUB_ORG%%/*}
if [ -z "$GITHUB_ORG" ]; then
    echo "Erreur : impossible d'extraire l'organisation depuis FORGEJO_GITHUB_ORG_URL=$ORG_URL." >&2
    exit 1
fi

GITHUB_TOKEN=$(get_env GITHUB_TOKEN)
GITHUB_USER=$(get_env GITHUB_USER)
[ -n "$GITHUB_USER" ] || GITHUB_USER=x-access-token
FORGEJO_OWNER=$(get_env FORGEJO_OWNER)
[ -n "$FORGEJO_OWNER" ] || FORGEJO_OWNER=$(get_env FORGEJO_ADMIN_NAME)
FORGEJO_ADMIN_NAME=$(get_env FORGEJO_ADMIN_NAME)
FORGEJO_ADMIN_PASSWORD=$(get_env FORGEJO_ADMIN_PASSWORD)
FORGEJO_API_TOKEN=$(get_env FORGEJO_API_TOKEN)
PUSH_MIRROR=$(get_env FORGEJO_GITHUB_PUSH_MIRROR)
[ -n "$PUSH_MIRROR" ] || PUSH_MIRROR=true
MIRROR_INTERVAL=$(get_env FORGEJO_GITHUB_MIRROR_INTERVAL)
[ -n "$MIRROR_INTERVAL" ] || MIRROR_INTERVAL=8h
SYNC_ON_COMMIT=$(get_env FORGEJO_GITHUB_MIRROR_SYNC_ON_COMMIT)
[ -n "$SYNC_ON_COMMIT" ] || SYNC_ON_COMMIT=true

case "$SYNC_ON_COMMIT" in
    true|false) ;;
    *) SYNC_ON_COMMIT=true ;;
esac

[ -n "$FORGEJO_OWNER" ] || { echo "Erreur : FORGEJO_OWNER est vide." >&2; exit 1; }
[ -n "$FORGEJO_ADMIN_NAME" ] || { echo "Erreur : FORGEJO_ADMIN_NAME est vide." >&2; exit 1; }
if [ -z "$FORGEJO_API_TOKEN" ] && [ -z "$FORGEJO_ADMIN_PASSWORD" ]; then
    echo "Erreur : FORGEJO_ADMIN_PASSWORD est vide (et FORGEJO_API_TOKEN aussi)." >&2
    exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

compose() {
    docker compose --env-file "$ENV_FILE" "$@"
}

# -----------------------------------------------------------------------------
# API Forgejo, appelée depuis le conteneur : on contourne Traefik et sa
# protection HTTP Basic. Le script ne dépend donc pas du DNS ni du certificat.
# -----------------------------------------------------------------------------
forgejo_api() {
    method=$1
    path=$2
    data=${3:-}

    compose exec -T \
        -e FG_USER="$FORGEJO_ADMIN_NAME" \
        -e FG_PASS="$FORGEJO_ADMIN_PASSWORD" \
        -e FG_TOKEN="$FORGEJO_API_TOKEN" \
        -e FG_DATA="$data" \
        forgejo sh -c '
            method=$1
            path=$2
            if [ -n "${FG_TOKEN:-}" ]; then
                set -- -H "Authorization: token $FG_TOKEN"
            else
                set -- -u "$FG_USER:$FG_PASS"
            fi
            if [ -n "${FG_DATA:-}" ]; then
                printf "%s" "$FG_DATA" | curl -sS -w "\n%{http_code}" "$@" \
                    -H "Content-Type: application/json" \
                    -X "$method" "http://127.0.0.1:3000/api/v1$path" \
                    --data-binary @-
            else
                curl -sS -w "\n%{http_code}" "$@" \
                    -X "$method" "http://127.0.0.1:3000/api/v1$path"
            fi
        ' sh "$method" "$path"
}

# Sépare le corps JSON et le code HTTP renvoyés par forgejo_api.
api_body() {
    printf '%s\n' "$1" | sed '$d'
}
api_code() {
    printf '%s\n' "$1" | tail -n 1
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Convertit la réponse JSON de GitHub en lignes tabulées :
# nom, clone_url, private, archived, fork, disabled.
parse_github_repos() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '.[] | [.name, .clone_url, (.private|tostring), (.archived|tostring), (.fork|tostring), (.disabled|tostring)] | @tsv'
        return
    fi

    # Repli sans jq : le JSON de l'API GitHub est indenté de deux espaces.
    awk '
        /^  \{$/ {
            inobj = 1
            name = ""; clone = ""; private = "false"
            archived = "false"; fork = "false"; disabled = "false"
            next
        }
        /^  \},?$/ {
            if (inobj) {
                print name "\t" clone "\t" private "\t" archived "\t" fork "\t" disabled
                inobj = 0
            }
            next
        }
        inobj && /^    "name": / {
            v = $0; sub(/^    "name": "/, "", v); sub(/",$/, "", v); name = v
        }
        inobj && /^    "clone_url": / {
            v = $0; sub(/^    "clone_url": "/, "", v); sub(/",$/, "", v); clone = v
        }
        inobj && /^    "private": / {
            v = $0; sub(/^    "private": /, "", v); sub(/,$/, "", v); private = v
        }
        inobj && /^    "archived": / {
            v = $0; sub(/^    "archived": /, "", v); sub(/,$/, "", v); archived = v
        }
        inobj && /^    "fork": / {
            v = $0; sub(/^    "fork": /, "", v); sub(/,$/, "", v); fork = v
        }
        inobj && /^    "disabled": / {
            v = $0; sub(/^    "disabled": /, "", v); sub(/,$/, "", v); disabled = v
        }
    '
}

# Télécharge une page de l'API GitHub.
github_api_get() {
    url=$1
    if [ -n "$GITHUB_TOKEN" ]; then
        curl -fsSL \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$url"
    else
        curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$url"
    fi
}

# -----------------------------------------------------------------------------
# Attente de Forgejo (sauf en mode --dry-run).
# -----------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 0 ]; then
    READY=0
    tries=0
    while [ "$tries" -lt 60 ]; do
        if compose exec -T forgejo curl -fsS \
                http://127.0.0.1:3000/api/v1/version >/dev/null 2>&1; then
            READY=1
            break
        fi
        tries=$((tries + 1))
        sleep 2
    done
    if [ "$READY" -ne 1 ]; then
        echo "Erreur : Forgejo n'est pas prêt (API version)." >&2
        echo "Vérifier : make ps-service SERVICE=forgejo" >&2
        exit 1
    fi

    AUTH_CHECK=$(forgejo_api GET /user)
    AUTH_CODE=$(api_code "$AUTH_CHECK")
    if [ "$AUTH_CODE" != "200" ]; then
        echo "Erreur : authentification API Forgejo impossible (HTTP $AUTH_CODE)." >&2
        echo "Vérifier FORGEJO_ADMIN_NAME / FORGEJO_ADMIN_PASSWORD, ou lancer :" >&2
        echo "  make forgejo-admin" >&2
        exit 1
    fi
fi

echo "→ import GitHub : $GITHUB_ORG -> Forgejo ($FORGEJO_OWNER)"
[ "$DRY_RUN" -eq 1 ] && echo "  (mode --dry-run : aucune modification)"

IMPORTED=0
SKIPPED=0
MIRRORS=0
FAILED=0
PAGE=1

while :; do
    GITHUB_URL="https://api.github.com/orgs/$GITHUB_ORG/repos?per_page=100&page=$PAGE&type=all"
    if ! BODY=$(github_api_get "$GITHUB_URL"); then
        echo "Erreur : impossible de lister les dépôts GitHub de $GITHUB_ORG." >&2
        echo "Vérifier FORGEJO_GITHUB_ORG_URL, le réseau et GITHUB_TOKEN." >&2
        exit 1
    fi

    REPO_COUNT=$(printf '%s\n' "$BODY" | grep -c '"clone_url"' || true)
    if [ "$REPO_COUNT" -eq 0 ]; then
        break
    fi

    printf '%s\n' "$BODY" | parse_github_repos > "$TMP_DIR/repos.tsv"
    while IFS=$(printf '\t') read -r REPO CLONE_URL IS_PRIVATE IS_ARCHIVED IS_FORK IS_DISABLED; do
        [ -n "$REPO" ] || continue

        if [ "$IS_DISABLED" = "true" ]; then
            echo "  - $REPO : ignoré (dépôt GitHub désactivé)"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        echo "  - $REPO"

        if [ "$DRY_RUN" -eq 1 ]; then
            echo "      [dry-run] migration depuis $CLONE_URL"
            IMPORTED=$((IMPORTED + 1))
            if [ "$PUSH_MIRROR" = "true" ] && [ -n "$GITHUB_TOKEN" ]; then
                echo "      [dry-run] miroir push vers $CLONE_URL"
                MIRRORS=$((MIRRORS + 1))
            fi
            continue
        fi

        RESPONSE=$(forgejo_api GET "/repos/$FORGEJO_OWNER/$REPO")
        CODE=$(api_code "$RESPONSE")
        if [ "$CODE" = "200" ]; then
            echo "      dépôt déjà présent"
            SKIPPED=$((SKIPPED + 1))
        elif [ "$CODE" = "404" ]; then
            PAYLOAD=$(printf '{"clone_addr":"%s","repo_name":"%s","repo_owner":"%s","service":"github","mirror":false,"private":%s,"issues":true,"pull_requests":true,"releases":true,"labels":true,"milestones":true,"wiki":true,"lfs":true' \
                "$(json_escape "$CLONE_URL")" \
                "$(json_escape "$REPO")" \
                "$(json_escape "$FORGEJO_OWNER")" \
                "$IS_PRIVATE")
            if [ -n "$GITHUB_TOKEN" ]; then
                PAYLOAD="$PAYLOAD,\"auth_username\":\"$(json_escape "$GITHUB_USER")\",\"auth_password\":\"$(json_escape "$GITHUB_TOKEN")\""
            fi
            PAYLOAD="$PAYLOAD}"

            RESPONSE=$(forgejo_api POST /repos/migrate "$PAYLOAD")
            CODE=$(api_code "$RESPONSE")
            if [ "$CODE" = "201" ]; then
                echo "      migré"
                IMPORTED=$((IMPORTED + 1))
            else
                echo "      échec de la migration (HTTP $CODE)" >&2
                printf '%s\n' "$(api_body "$RESPONSE")" | head -c 500 >&2
                echo >&2
                FAILED=$((FAILED + 1))
                continue
            fi
        else
            echo "      erreur API Forgejo (HTTP $CODE)" >&2
            FAILED=$((FAILED + 1))
            continue
        fi

        if [ "$PUSH_MIRROR" != "true" ]; then
            continue
        fi
        if [ -z "$GITHUB_TOKEN" ]; then
            echo "      miroir push ignoré : GITHUB_TOKEN vide"
            continue
        fi

        RESPONSE=$(forgejo_api GET "/repos/$FORGEJO_OWNER/$REPO/push_mirrors")
        CODE=$(api_code "$RESPONSE")
        if [ "$CODE" = "200" ] && printf '%s' "$(api_body "$RESPONSE")" | grep -Fq "$CLONE_URL"; then
            echo "      miroir push déjà configuré"
            continue
        fi

        PAYLOAD=$(printf '{"remote_address":"%s","remote_username":"%s","remote_password":"%s","interval":"%s","sync_on_commit":%s}' \
            "$(json_escape "$CLONE_URL")" \
            "$(json_escape "$GITHUB_USER")" \
            "$(json_escape "$GITHUB_TOKEN")" \
            "$(json_escape "$MIRROR_INTERVAL")" \
            "$SYNC_ON_COMMIT")

        RESPONSE=$(forgejo_api POST "/repos/$FORGEJO_OWNER/$REPO/push_mirrors" "$PAYLOAD")
        CODE=$(api_code "$RESPONSE")
        if [ "$CODE" = "200" ] || [ "$CODE" = "201" ]; then
            echo "      miroir push configuré"
            MIRRORS=$((MIRRORS + 1))
        else
            echo "      échec du miroir push (HTTP $CODE)" >&2
            printf '%s\n' "$(api_body "$RESPONSE")" | head -c 500 >&2
            echo >&2
            FAILED=$((FAILED + 1))
        fi
    done < "$TMP_DIR/repos.tsv"

    # L'API GitHub renvoie au maximum 100 dépôts par page.
    if [ "$REPO_COUNT" -lt 100 ]; then
        break
    fi
    PAGE=$((PAGE + 1))
done

echo
echo "→ import terminé : $IMPORTED migré(s), $SKIPPED ignoré(s), $MIRRORS miroir(s), $FAILED échec(s)"
if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
