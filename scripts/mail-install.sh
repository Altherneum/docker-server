#!/bin/sh
# =============================================================================
# mail-install.sh - installe la stack officielle mailcow si nécessaire.
#
# - clone mailcow dans MAILCOW_DIR quand le dossier est absent ;
# - génère mailcow.conf sans passer par les questions interactives ;
# - prépare le certificat interne, app_info.inc.php et le lien .env ;
# - ne touche pas à une installation mailcow existante.
#
# L'override Traefik et le démarrage restent gérés par mail-integrate.sh et
# mail-setup.sh. Appelé par make mail-setup / mail-up / make up-service SERVICE=mailcow.
#
# Usage : ./scripts/mail-install.sh
# =============================================================================
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MAIL_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/mail-lib.sh"
mail_load_env "$MAIL_ROOT"

trap 'mail_chown_user "$ENV_FILE"' 0

command -v git >/dev/null 2>&1 || mail_die "git est requis pour installer mailcow."
command -v openssl >/dev/null 2>&1 || mail_die "openssl est requis pour installer mailcow."
command -v docker >/dev/null 2>&1 || mail_die "docker est requis pour installer mailcow."

mail_domain_valid "$DOMAIN" || mail_die "DOMAIN invalide : $DOMAIN (renseignez DOMAIN_NAME et TLD dans .env)"

mailcow_hostname=$(env_get MAILCOW_HOSTNAME)
[ -n "$mailcow_hostname" ] || mailcow_hostname="mail.$DOMAIN"
mail_domain_valid "$mailcow_hostname" || mail_die "MAILCOW_HOSTNAME invalide : $mailcow_hostname"

mailcow_tz=$(env_get TZ)
[ -n "$mailcow_tz" ] || mailcow_tz=$(cat /etc/timezone 2>/dev/null || true)
[ -n "$mailcow_tz" ] || mailcow_tz=Europe/Paris

# --- Clone de la stack officielle -----------------------------------------
if [ -f "$MAILCOW_DIR/docker-compose.yml" ]; then
    mail_info "mailcow déjà présent dans $MAILCOW_DIR"
else
    if [ -d "$MAILCOW_DIR" ] && [ -n "$(ls -A "$MAILCOW_DIR" 2>/dev/null || true)" ]; then
        mail_die "$MAILCOW_DIR existe mais ne contient pas docker-compose.yml. Choisissez un autre MAILCOW_DIR ou videz ce dossier."
    fi
    parent=$(dirname "$MAILCOW_DIR")
    mkdir -p "$parent"
    mail_info "clone de mailcow dans $MAILCOW_DIR"
    git clone https://github.com/mailcow/mailcow-dockerized.git "$MAILCOW_DIR" \
        || mail_die "clone de mailcow impossible."
fi

# --- Lien .env -> mailcow.conf --------------------------------------------
if [ -L "$MAILCOW_DIR/.env" ] && [ ! -e "$MAILCOW_DIR/.env" ]; then
    rm -f "$MAILCOW_DIR/.env"
fi
if [ ! -e "$MAILCOW_DIR/.env" ] && [ ! -L "$MAILCOW_DIR/.env" ]; then
    ( cd "$MAILCOW_DIR" && ln -s mailcow.conf .env )
    mail_info "lien $MAILCOW_DIR/.env -> mailcow.conf créé"
elif [ ! -L "$MAILCOW_DIR/.env" ]; then
    mail_warn "$MAILCOW_DIR/.env n'est pas un lien vers mailcow.conf ; vérifiez votre installation mailcow."
fi

# --- Configuration mailcow.conf -------------------------------------------
if [ -f "$MAILCOW_CONF" ]; then
    mail_info "mailcow.conf déjà présent, configuration conservée"
else
    command -v awk >/dev/null 2>&1 || mail_die "awk est requis."
    block=$(sed -n '/^cat << EOF > mailcow.conf$/,/^EOF$/p' "$MAILCOW_DIR/generate_config.sh" | sed '1d;$d')
    [ -n "$block" ] || mail_die "impossible d'extraire le modèle mailcow.conf depuis generate_config.sh."

    db_pass=$(openssl rand -hex 20)
    db_root=$(openssl rand -hex 20)
    redis_pass=$(openssl rand -hex 20)
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    # Mailcow recommande 6 Go avec ClamAV. En dessous de 4 Go, ClamAV est
    # désactivé pour éviter un OOM ; l'interface et les mails restent complets.
    if [ "$mem_kb" -gt 0 ] && [ "$mem_kb" -le 4194304 ]; then
        skip_clamd=y
    else
        skip_clamd=n
    fi

    tmp_render=$(mktemp "${TMPDIR:-/tmp}/mailcow-render.XXXXXX")
    {
        printf 'MAILCOW_HOSTNAME=%s\n' "$(printf "'%s'" "$mailcow_hostname")"
        printf 'MAILCOW_TZ=%s\n' "$(printf "'%s'" "$mailcow_tz")"
        printf 'SKIP_CLAMD=%s\n' "$skip_clamd"
        printf 'COMPOSE_VERSION=native\n'
        printf 'IPV6_BOOL=false\n'
        printf 'MAILCOW_DBPASS=%s\n' "$db_pass"
        printf 'MAILCOW_DBROOT=%s\n' "$db_root"
        printf 'MAILCOW_REDISPASS=%s\n' "$redis_pass"
        printf 'cat <<EOF\n'
        printf '%s\n' "$block"
        printf 'EOF\n'
    } > "$tmp_render"
    sh "$tmp_render" > "$MAILCOW_CONF"
    rm -f "$tmp_render"
    chmod 600 "$MAILCOW_CONF"
    mail_info "mailcow.conf généré pour $mailcow_hostname"
    if [ "$skip_clamd" = "y" ]; then
        mail_info "RAM totale <= 4 Go : ClamAV désactivé (SKIP_CLAMD=y) pour éviter un OOM. Pour l'activer : SKIP_CLAMD=n dans $MAILCOW_CONF puis redémarrer mailcow."
    fi
fi

# --- Fichiers attendus par mailcow ----------------------------------------
mkdir -p "$MAILCOW_DIR/data/assets/ssl" "$MAILCOW_DIR/data/conf/rspamd/override.d"
if [ ! -f "$MAILCOW_DIR/data/conf/rspamd/override.d/worker-controller-password.inc" ]; then
    printf '# Placeholder\n' > "$MAILCOW_DIR/data/conf/rspamd/override.d/worker-controller-password.inc"
fi

if [ ! -f "$MAILCOW_DIR/data/assets/ssl/cert.pem" ] || [ ! -f "$MAILCOW_DIR/data/assets/ssl/key.pem" ]; then
    if [ -f "$MAILCOW_DIR/data/assets/ssl-example/cert.pem" ] && [ -f "$MAILCOW_DIR/data/assets/ssl-example/key.pem" ]; then
        for pem in "$MAILCOW_DIR/data/assets/ssl-example/"*.pem; do
            [ -f "$pem" ] || continue
            dest="$MAILCOW_DIR/data/assets/ssl/$(basename "$pem")"
            [ -e "$dest" ] || cp "$pem" "$dest"
        done
    else
        openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 365 \
            -keyout "$MAILCOW_DIR/data/assets/ssl/key.pem" \
            -out "$MAILCOW_DIR/data/assets/ssl/cert.pem" \
            -subj "/CN=$mailcow_hostname" >/dev/null 2>&1
    fi
fi
chmod 600 "$MAILCOW_DIR/data/assets/ssl/key.pem" 2>/dev/null || true

git_version=$(git -C "$MAILCOW_DIR" describe --tags --always 2>/dev/null || echo unknown)
git_branch=$(git -C "$MAILCOW_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)
git_commit=$(git -C "$MAILCOW_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
{
    printf '<?php\n'
    printf '  $MAILCOW_GIT_VERSION="%s";\n' "$git_version"
    printf '  $MAILCOW_LAST_GIT_VERSION="";\n'
    printf '  $MAILCOW_GIT_OWNER="mailcow";\n'
    printf '  $MAILCOW_GIT_REPO="mailcow-dockerized";\n'
    printf '  $MAILCOW_GIT_URL="https://github.com/mailcow/mailcow-dockerized";\n'
    printf '  $MAILCOW_GIT_COMMIT="%s";\n' "$git_commit"
    printf '  $MAILCOW_GIT_COMMIT_DATE="";\n'
    printf '  $MAILCOW_BRANCH="%s";\n' "$git_branch"
    printf '  $MAILCOW_UPDATEDAT=%s;\n' "$(date +%s)"
    printf '?>\n'
} > "$MAILCOW_DIR/data/web/inc/app_info.inc.php"

mail_info "mailcow prêt dans $MAILCOW_DIR"
printf '  Configuration : %s\n' "$MAILCOW_CONF"
printf '  Hôte          : %s\n' "$mailcow_hostname"
printf '  Démarrage     : sudo make mail-setup\n'
