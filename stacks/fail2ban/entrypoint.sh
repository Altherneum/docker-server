#!/bin/sh
set -eu

mkdir -p /var/lib/fail2ban /run/fail2ban /var/log/traefik
# Le volume de logs est partagé avec Traefik. Le créer ici évite que fail2ban
# refuse de démarrer s'il est lancé avant Traefik.
touch /var/log/traefik/access.log

# Traefik écrit l'access log dans un volume : sans rotation il peut remplir le
# disque. copytruncate garde le même inode pour que fail2ban continue de lire.
logrotate -s /var/lib/fail2ban/logrotate.status /etc/logrotate.d/traefik 2>/dev/null || true
(
    while :; do
        sleep 3600
        logrotate -s /var/lib/fail2ban/logrotate.status /etc/logrotate.d/traefik 2>/dev/null || true
    done
) &

# Cherche le journal SSH de l'hôte monté dans /host/var/log.
# Debian/Ubuntu : auth.log. Alpine : messages. Certains systèmes : secure.
find_ssh_log() {
    if [ -n "${FAIL2BAN_SSH_LOG:-}" ]; then
        case "$FAIL2BAN_SSH_LOG" in
            /host/*) printf '%s\n' "$FAIL2BAN_SSH_LOG" ;;
            *) printf '/host%s\n' "$FAIL2BAN_SSH_LOG" ;;
        esac
        return 0
    fi

    for path in \
        /host/var/log/auth.log \
        /host/var/log/secure \
        /host/var/log/messages \
        /host/var/log/syslog
    do
        if [ -f "$path" ]; then
            printf '%s\n' "$path"
            return 0
        fi
    done

    return 1
}

# Écrit la jail SSH. Le SSH de l'hôte passe par INPUT, pas par DOCKER-USER.
write_ssh_jail() {
    log_path=$(find_ssh_log || true)
    jail_file=/etc/fail2ban/jail.d/00-host-sshd.local

    if [ -z "$log_path" ]; then
        cat > "$jail_file" <<EOF
[sshd]
enabled = false
EOF
        echo "fail2ban: aucun journal SSH trouvé dans /host/var/log (jail SSH désactivée)." >&2
        return 0
    fi

    cat > "$jail_file" <<EOF
[sshd]
enabled = true
filter = sshd
port = ${FAIL2BAN_SSH_PORT:-22}
backend = polling
logpath = $log_path
chain = INPUT
maxretry = ${FAIL2BAN_MAXRETRY:-3}
findtime = ${FAIL2BAN_FINDTIME:-10m}
bantime = ${FAIL2BAN_BANTIME:-1h}
EOF

    echo "fail2ban: SSH surveillé sur le port ${FAIL2BAN_SSH_PORT:-22} ($log_path)."
}

write_ssh_jail

exec fail2ban-server -f -c /etc/fail2ban
