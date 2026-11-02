# shellcheck shell=sh
# =============================================================================
# 24-webhooks.sh - notifications Discord des connexions SSH
# =============================================================================

# Vrai si au moins un webhook Discord est configuré.
has_webhook() {
    if [ -n "$DISCORD_WEBHOOK_SSH" ]; then
        return 0
    fi
    if [ -n "$DISCORD_WEBHOOK_SESSION" ]; then
        return 0
    fi
    return 1
}

# Installe curl si nécessaire.
ensure_curl() {
    if command_exists curl; then
        return 0
    fi
    pkg_install curl
}

# Écrit les URL des webhooks.
write_webhook_config() {
    write_file /etc/docker-server/ssh-webhooks.conf 640 <<EOF
# Généré par install.sh - URL des webhooks Discord.
DISCORD_WEBHOOK_SSH='$DISCORD_WEBHOOK_SSH'
DISCORD_WEBHOOK_SESSION='$DISCORD_WEBHOOK_SESSION'
EOF

    admin_group=$(user_group "$ADMIN_USER")
    chown root:"$admin_group" /etc/docker-server/ssh-webhooks.conf 2>/dev/null || true
}

# Installe la notification des connexions non interactives.
write_sshrc() {
    write_file /etc/ssh/sshrc 755 <<'EOF'
#!/bin/sh
# Généré par install.sh - notification des connexions SSH non interactives.
CONF=/etc/docker-server/ssh-webhooks.conf
if [ ! -r "$CONF" ]; then
    exit 0
fi
. "$CONF"

URL=${DISCORD_WEBHOOK_SSH:-}
if [ -z "$URL" ]; then
    exit 0
fi

# Une session interactive a un terminal : elle est notifiée par profile.d.
if [ -n "$SSH_TTY" ]; then
    exit 0
fi

ip=${SSH_CONNECTION%% *}
user=$(id -un 2>/dev/null || echo inconnu)
host=$(hostname 2>/dev/null || echo serveur)
payload=$(printf '{"content":"SSH non interactif : `%s` sur `%s` depuis `%s`"}' \
    "$user" "$host" "${ip:-inconnue}")

curl -fsS --max-time 5 \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "$URL" >/dev/null 2>&1 || true
exit 0
EOF
}

# Installe la notification des sessions interactives.
write_session_notification() {
    write_file /etc/profile.d/00-docker-server-session.sh 644 <<'EOF'
# shellcheck shell=sh
# Généré par install.sh - notification des sessions interactives.

case $- in
    *i*) ;;
    *) return 0 ;;
esac

CONF=/etc/docker-server/ssh-webhooks.conf
if [ ! -r "$CONF" ]; then
    return 0
fi
. "$CONF"

URL=${DISCORD_WEBHOOK_SESSION:-${DISCORD_WEBHOOK_SSH:-}}
if [ -z "$URL" ]; then
    return 0
fi

if [ -n "${DOCKER_SESSION_NOTIFIED:-}" ]; then
    return 0
fi
export DOCKER_SESSION_NOTIFIED=1

current_user=$(id -un 2>/dev/null || echo inconnu)
login_user=$(who am i 2>/dev/null | awk '{print $1; exit}')
if [ -z "$login_user" ]; then
    login_user=${LOGNAME:-$current_user}
fi

tty_name=$(who am i 2>/dev/null | awk '{print $2; exit}')
if [ -z "$tty_name" ]; then
    tty_name=${SSH_TTY:-local}
fi

ip=""
kind="locale"
if [ -n "$SSH_CONNECTION" ]; then
    ip=${SSH_CONNECTION%% *}
    kind="SSH"
fi

if [ "$login_user" = "$current_user" ]; then
    who_text="$current_user"
else
    who_text="$login_user > $current_user"
fi

payload=$(printf '{"content":"Session %s : `%s` depuis `%s` (%s)"}' \
    "$kind" "$who_text" "${ip:-local}" "$tty_name")

curl -fsS --max-time 5 \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "$URL" >/dev/null 2>&1 || true
EOF
}

# Écrit les hooks et sauvegarde les anciens fichiers.
configure_webhooks() {
    section "Notifications Discord"

    if has_webhook; then
        ensure_curl
    fi

    backup_file /etc/ssh/sshrc
    backup_file /etc/profile.d/00-docker-server-session.sh

    write_webhook_config
    write_sshrc
    write_session_notification

    if ! has_webhook; then
        warn "Aucun webhook Discord configuré (DISCORD_WEBHOOK_SSH dans .env)."
        return 0
    fi

    log "Notifications Discord SSH activées."
}
