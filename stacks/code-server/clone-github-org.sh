#!/bin/sh
# =============================================================================
# Clone les dépôts d'une organisation GitHub dans le workspace de code-server.
#
# Lancé par entrypoint.sh à chaque démarrage. Le script est idempotent : un
# dépôt déjà présent n'est jamais écrasé. Un remote « forgejo » est ajouté pour
# pouvoir pousser vers Forgejo depuis le terminal de code-server.
# =============================================================================
set -eu

[ "${CODE_SERVER_CLONE_GITHUB_ORG:-true}" = "true" ] || exit 0

ORG_URL=${CODE_SERVER_GITHUB_ORG_URL:-}
if [ -z "$ORG_URL" ]; then
    echo "→ CODE_SERVER_GITHUB_ORG_URL est vide : aucun dépôt GitHub à cloner."
    exit 0
fi

GITHUB_ORG=$(printf '%s' "$ORG_URL" | sed 's#/$##; s#\.git$##')
case "$GITHUB_ORG" in
    *github.com/*) GITHUB_ORG=${GITHUB_ORG#*github.com/} ;;
    *github.com:*) GITHUB_ORG=${GITHUB_ORG#*github.com:} ;;
esac
GITHUB_ORG=${GITHUB_ORG%%/*}
if [ -z "$GITHUB_ORG" ]; then
    echo "Attention : impossible d'extraire l'organisation depuis CODE_SERVER_GITHUB_ORG_URL=$ORG_URL." >&2
    exit 0
fi

GITHUB_TOKEN=${GITHUB_TOKEN:-}
GITHUB_USER=${GITHUB_USER:-x-access-token}
WORKSPACE=${DEFAULT_WORKSPACE:-/home/coder/workspace}
FORGEJO_INTERNAL_URL=${FORGEJO_INTERNAL_URL:-http://forgejo:3000}
FORGEJO_OWNER=${FORGEJO_OWNER:-${FORGEJO_ADMIN_NAME:-}}

mkdir -p "$WORKSPACE"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

# Convertit la réponse JSON de GitHub en lignes tabulées.
parse_github_repos() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '.[] | [.name, .clone_url, (.private|tostring), (.archived|tostring), (.fork|tostring), (.disabled|tostring)] | @tsv'
        return
    fi

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

# Ajoute le remote interne Forgejo s'il n'existe pas encore.
ensure_forgejo_remote() {
    target=$1
    repo=$2

    [ -n "$FORGEJO_OWNER" ] || return 0
    if git -C "$target" remote get-url forgejo >/dev/null 2>&1; then
        return 0
    fi
    git -C "$target" remote add forgejo \
        "${FORGEJO_INTERNAL_URL%/}/${FORGEJO_OWNER}/${repo}.git"
    echo "   remote forgejo ajouté"
}

CLONED=0
SKIPPED=0
FAILED=0
PAGE=1

echo "→ clonage GitHub : $GITHUB_ORG -> $WORKSPACE"

while :; do
    GITHUB_URL="https://api.github.com/orgs/$GITHUB_ORG/repos?per_page=100&page=$PAGE&type=all"
    if ! BODY=$(github_api_get "$GITHUB_URL"); then
        echo "Attention : impossible de lister les dépôts GitHub de $GITHUB_ORG." >&2
        exit 0
    fi

    REPO_COUNT=$(printf '%s\n' "$BODY" | grep -c '"clone_url"' || true)
    if [ "$REPO_COUNT" -eq 0 ]; then
        break
    fi

    printf '%s\n' "$BODY" | parse_github_repos > "$TMP_DIR/repos.tsv"
    while IFS=$(printf '\t') read -r REPO CLONE_URL IS_PRIVATE IS_ARCHIVED IS_FORK IS_DISABLED; do
        [ -n "$REPO" ] || continue
        [ "$IS_DISABLED" = "true" ] && continue

        TARGET="$WORKSPACE/$REPO"
        if [ -d "$TARGET/.git" ]; then
            echo "  - $REPO : déjà cloné"
            ensure_forgejo_remote "$TARGET" "$REPO"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        if [ -e "$TARGET" ]; then
            echo "  - $REPO : $TARGET existe sans être un dépôt Git, ignoré." >&2
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        echo "  - $REPO : clonage"
        if [ -n "$GITHUB_TOKEN" ] && [ "${CLONE_URL#https://}" != "$CLONE_URL" ]; then
            AUTH_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@${CLONE_URL#https://}"
            if git clone "$AUTH_URL" "$TARGET"; then
                # Ne conserve pas le jeton dans le remote.
                git -C "$TARGET" remote set-url origin "$CLONE_URL"
            else
                echo "    échec du clone" >&2
                rm -rf "$TARGET"
                FAILED=$((FAILED + 1))
                continue
            fi
        else
            if ! git clone "$CLONE_URL" "$TARGET"; then
                echo "    échec du clone" >&2
                rm -rf "$TARGET"
                FAILED=$((FAILED + 1))
                continue
            fi
        fi

        ensure_forgejo_remote "$TARGET" "$REPO"
        CLONED=$((CLONED + 1))
    done < "$TMP_DIR/repos.tsv"

    if [ "$REPO_COUNT" -lt 100 ]; then
        break
    fi
    PAGE=$((PAGE + 1))
done

echo "→ clonage terminé : $CLONED cloné(s), $SKIPPED ignoré(s), $FAILED échec(s)"
