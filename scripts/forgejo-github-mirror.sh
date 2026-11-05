#!/bin/sh
# =============================================================================
# Importe les dépôts d'une organisation GitHub dans Forgejo, puis configure un
# miroir push Forgejo -> GitHub.
#
# Appelé automatiquement par `make up` et `make up-service SERVICE=forgejo`.
# Lancement manuel :
#   make forgejo-mirror
#   make forgejo-mirror FORGEJO_MIRROR_ARGS=--dry-run
#   make forgejo-mirror FORGEJO_MIRROR_ARGS=--reset-stuck
#
# Le script est idempotent : un dépôt déjà présent n'est pas réimporté, et un
# miroir push déjà configuré n'est pas recréé.
#
# Sans GITHUB_TOKEN, l'API GitHub est limitée à 60 requêtes/heure. L'import des
# issues, commentaires et réactions peut alors durer des heures (Forgejo attend
# chaque remise à zéro du quota). Le script importe donc uniquement le code Git
# dans ce cas ; renseignez GITHUB_TOKEN pour un import complet.
# =============================================================================
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=${ENV_FILE:-.env}
[ -f "$ENV_FILE" ] || { echo "Erreur : $ENV_FILE introuvable. Lancer make init." >&2; exit 1; }

DRY_RUN=0
RESET_STUCK=0
FORCE_ALL=0
FORCE_REPOS=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --reset-stuck) RESET_STUCK=1 ;;
        --force) FORCE_ALL=1 ;;
        --force=*)
            FORCE_REPOS="$FORCE_REPOS $(printf '%s' "${arg#--force=}" | tr ',' ' ')"
            ;;
        -h|--help)
            echo "Usage : $0 [--dry-run] [--reset-stuck] [--force | --force=depot1,depot2]"
            echo
            echo "  --dry-run       liste les dépôts et les actions sans rien modifier"
            echo "  --reset-stuck   supprime les dépôts restés bloqués en migration"
            echo "  --force         réimporte tous les dépôts (suppression préalable)"
            echo "  --force=nom     réimporte uniquement le ou les dépôts indiqués"
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
FORGEJO_DB_NAME=$(get_env FORGEJO_DB_NAME)
FORGEJO_DB_USER=$(get_env FORGEJO_DB_USER)
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

# auto = métadonnées uniquement si GITHUB_TOKEN est présent ; true = toujours ;
# false = code Git seul (rapide, aucune limite d'API GitHub).
MIGRATE_METADATA=$(get_env FORGEJO_GITHUB_MIGRATE_METADATA)
[ -n "$MIGRATE_METADATA" ] || MIGRATE_METADATA=auto
case "$MIGRATE_METADATA" in
    auto)
        if [ -n "$GITHUB_TOKEN" ]; then IMPORT_METADATA=true; else IMPORT_METADATA=false; fi
        ;;
    true) IMPORT_METADATA=true ;;
    false) IMPORT_METADATA=false ;;
    *)
        echo "Erreur : FORGEJO_GITHUB_MIGRATE_METADATA doit valoir auto, true ou false." >&2
        exit 1
        ;;
esac

# Durée maximale d'attente de l'appel de migration (en secondes). Au-delà, le
# script continue : Forgejo poursuit la migration côté serveur. 0 = illimité.
MIGRATE_TIMEOUT=$(get_env FORGEJO_GITHUB_MIGRATE_TIMEOUT)
[ -n "$MIGRATE_TIMEOUT" ] || MIGRATE_TIMEOUT=1800
case "$MIGRATE_TIMEOUT" in
    ''|*[!0-9]*)
        echo "Erreur : FORGEJO_GITHUB_MIGRATE_TIMEOUT doit être un nombre de secondes." >&2
        exit 1
        ;;
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
    max_time=${4:-}

    compose exec -T \
        -e FG_USER="$FORGEJO_ADMIN_NAME" \
        -e FG_PASS="$FORGEJO_ADMIN_PASSWORD" \
        -e FG_TOKEN="$FORGEJO_API_TOKEN" \
        -e FG_DATA="$data" \
        -e FG_MAX_TIME="$max_time" \
        forgejo sh -c '
            method=$1
            path=$2
            if [ -n "${FG_TOKEN:-}" ]; then
                set -- -H "Authorization: token $FG_TOKEN"
            else
                set -- -u "$FG_USER:$FG_PASS"
            fi
            if [ -n "${FG_MAX_TIME:-}" ]; then
                set -- "$@" --max-time "$FG_MAX_TIME"
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
        ' sh "$method" "$path" < /dev/null
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

sql_escape() {
    printf '%s' "$1" | sed "s/'/''/g"
}

# Liste les dépôts dont la migration n'a jamais abouti (status = 1). Utile
# après un redémarrage de Forgejo : le processus de migration est interrompu,
# mais le dépôt reste marqué « en cours de migration » dans la base.
forgejo_stuck_repos() {
    [ -n "$FORGEJO_DB_NAME" ] && [ -n "$FORGEJO_DB_USER" ] || return 0
    compose exec -T db-forgejo \
        psql -U "$FORGEJO_DB_USER" -d "$FORGEJO_DB_NAME" -tAc \
        "SELECT r.lower_name FROM repository r
         JOIN \"user\" u ON u.id = r.owner_id
         WHERE u.lower_name = lower('$(sql_escape "$FORGEJO_OWNER")')
           AND r.status = 1;" < /dev/null 2>/dev/null \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | sed '/^$/d'
}

force_repo() {
    [ "$FORCE_ALL" -eq 1 ] && return 0
    for forced in $FORCE_REPOS; do
        [ "$forced" = "$1" ] && return 0
    done
    return 1
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

IMPORTED=0
SKIPPED=0
MIRRORS=0
FAILED=0
PAGE=1

if [ "$RESET_STUCK" -eq 0 ]; then
    STUCK_REPOS=$(forgejo_stuck_repos || true)
    if [ -n "$STUCK_REPOS" ]; then
        echo "Attention : dépôt(s) encore marqué(s) « en migration » :"
        for STUCK_REPO in $STUCK_REPOS; do
            echo "  - $STUCK_REPO"
        done
        echo "  Si la migration est interrompue, redémarrer Forgejo puis relancer avec --reset-stuck."
    fi
fi

if [ "$RESET_STUCK" -eq 1 ]; then
    STUCK_REPOS=$(forgejo_stuck_repos || true)
    if [ -z "$STUCK_REPOS" ]; then
        echo "→ aucun dépôt bloqué en migration"
    else
        echo "→ dépôts bloqués en migration :"
        for STUCK_REPO in $STUCK_REPOS; do
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "  - $STUCK_REPO : serait supprimé"
                continue
            fi
            echo "  - $STUCK_REPO : suppression"
            RESPONSE=$(forgejo_api DELETE "/repos/$FORGEJO_OWNER/$STUCK_REPO")
            CODE=$(api_code "$RESPONSE")
            case "$CODE" in
                200|204) ;;
                *)
                    echo "      échec de la suppression (HTTP $CODE)" >&2
                    FAILED=$((FAILED + 1))
                    ;;
            esac
        done
        echo "  (si la migration tourne encore, redémarrer Forgejo avant : make restart-service SERVICE=forgejo)"
    fi
fi

echo "→ import GitHub : $GITHUB_ORG -> Forgejo ($FORGEJO_OWNER)"
[ "$DRY_RUN" -eq 1 ] && echo "  (mode --dry-run : aucune modification)"

if [ "$IMPORT_METADATA" = "true" ]; then
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "  Attention : métadonnées importées sans GITHUB_TOKEN."
        echo "  GitHub limite à 60 requêtes/heure : l'import peut durer plusieurs heures."
        echo "  Définir GITHUB_TOKEN (scope repo) pour accélérer."
    fi
else
    if [ "$MIGRATE_METADATA" = "auto" ]; then
        echo "  GITHUB_TOKEN vide : import du code Git uniquement."
        echo "  Issues, PR, releases, labels et wiki désactivés ; miroir push désactivé."
        echo "  Définir GITHUB_TOKEN (scope repo) pour l'import complet."
    else
        echo "  Métadonnées désactivées (FORGEJO_GITHUB_MIGRATE_METADATA=false)."
    fi
fi

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
    while IFS=$(printf '\t') read -r REPO CLONE_URL IS_PRIVATE IS_ARCHIVED IS_FORK IS_DISABLED <&3; do
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

        if [ "$CODE" = "200" ] && force_repo "$REPO"; then
            echo "      réimport demandé (--force) : suppression du dépôt existant"
            RESPONSE=$(forgejo_api DELETE "/repos/$FORGEJO_OWNER/$REPO")
            CODE=$(api_code "$RESPONSE")
            case "$CODE" in
                200|204) CODE=404 ;;
                *)
                    echo "      échec de la suppression (HTTP $CODE)" >&2
                    FAILED=$((FAILED + 1))
                    continue
                    ;;
            esac
        fi

        if [ "$CODE" = "200" ]; then
            echo "      dépôt déjà présent"
            SKIPPED=$((SKIPPED + 1))
        elif [ "$CODE" = "404" ]; then
            if [ "$IMPORT_METADATA" = "true" ]; then
                IMPORT_ISSUES=true
                IMPORT_PRS=true
                IMPORT_RELEASES=true
                IMPORT_LABELS=true
                IMPORT_MILESTONES=true
                IMPORT_WIKI=true
            else
                IMPORT_ISSUES=false
                IMPORT_PRS=false
                IMPORT_RELEASES=false
                IMPORT_LABELS=false
                IMPORT_MILESTONES=false
                IMPORT_WIKI=false
            fi

            PAYLOAD=$(printf '{"clone_addr":"%s","repo_name":"%s","repo_owner":"%s","service":"github","mirror":false,"private":%s,"issues":%s,"pull_requests":%s,"releases":%s,"labels":%s,"milestones":%s,"wiki":%s,"lfs":true' \
                "$(json_escape "$CLONE_URL")" \
                "$(json_escape "$REPO")" \
                "$(json_escape "$FORGEJO_OWNER")" \
                "$IS_PRIVATE" \
                "$IMPORT_ISSUES" \
                "$IMPORT_PRS" \
                "$IMPORT_RELEASES" \
                "$IMPORT_LABELS" \
                "$IMPORT_MILESTONES" \
                "$IMPORT_WIKI")
            if [ -n "$GITHUB_TOKEN" ]; then
                PAYLOAD="$PAYLOAD,\"auth_username\":\"$(json_escape "$GITHUB_USER")\",\"auth_password\":\"$(json_escape "$GITHUB_TOKEN")\""
            fi
            PAYLOAD="$PAYLOAD}"

            MAX_TIME=""
            [ "$MIGRATE_TIMEOUT" -gt 0 ] && MAX_TIME="$MIGRATE_TIMEOUT"

            if RESPONSE=$(forgejo_api POST /repos/migrate "$PAYLOAD" "$MAX_TIME"); then
                CODE=$(api_code "$RESPONSE")
            else
                RC=$?
                if [ "$RC" -eq 28 ]; then
                    echo "      délai d'attente dépassé (${MIGRATE_TIMEOUT}s)"
                    echo "      la migration continue côté Forgejo ; relancer plus tard pour le miroir push"
                    IMPORTED=$((IMPORTED + 1))
                    continue
                fi
                echo "      échec de l'appel de migration (code $RC)" >&2
                FAILED=$((FAILED + 1))
                continue
            fi

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
    done 3< "$TMP_DIR/repos.tsv"

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
if [ -z "$GITHUB_TOKEN" ]; then
    echo "→ Pour importer les issues/PR/releases et activer le miroir push :"
    echo "  renseigner GITHUB_TOKEN (scope repo), puis relancer make forgejo-mirror."
    echo "  Un dépôt déjà importé peut être réimporté avec --force=nom."
fi
