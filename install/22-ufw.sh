# shellcheck shell=sh
# =============================================================================
# 22-ufw.sh - pare-feu UFW
# =============================================================================

# Modifie une valeur de /etc/default/ufw.
set_ufw_default() {
    key=$1
    value=$2
    file=/etc/default/ufw

    if [ ! -f "$file" ]; then
        return 0
    fi

    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
        return 0
    fi

    printf '%s=%s\n' "$key" "$value" >> "$file"
}

# Autorise SSH avec une limite de connexions.
allow_ssh_port() {
    ufw limit "$SSH_PORT/tcp"
}

# Ouvre les ports TCP supplémentaires.
allow_tcp_ports() {
    for port in $TCP_PORTS; do
        if [ "$port" = "$SSH_PORT" ]; then
            continue
        fi
        ufw allow "$port/tcp"
    done
}

# Ouvre les ports UDP.
allow_udp_ports() {
    for port in $UDP_PORTS; do
        ufw allow "$port/udp"
    done
}

# Active UFW.
enable_ufw() {
    if ! ufw --force enable; then
        warn "UFW n'a pas pu être activé."
    fi
}

# Active UFW au démarrage.
enable_ufw_at_boot() {
    service_enable ufw
}

# Configure toutes les règles UFW.
configure_ufw() {
    section "Pare-feu UFW"

    pkg_install ufw

    # Docker a besoin du forwarding, sinon les conteneurs ne répondent plus.
    set_ufw_default DEFAULT_FORWARD_POLICY '"ACCEPT"'

    if [ -f /proc/net/if_inet6 ]; then
        set_ufw_default IPV6 yes
    fi

    ufw default deny incoming
    ufw default allow outgoing
    ufw logging low

    allow_ssh_port
    allow_tcp_ports
    allow_udp_ports
    enable_ufw
    enable_ufw_at_boot

    log "État UFW :"
    ufw status verbose || true
}
