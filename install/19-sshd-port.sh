# shellcheck shell=sh
# =============================================================================
# 19-sshd-port.sh - port SSH appliqué depuis .env
#
# SSH écoute sur plusieurs ports quand plusieurs directives Port existent.
# On commente donc les directives Port du fichier principal, puis on écrit
# notre port dans le fichier inclus en premier.
# =============================================================================

# Ajoute le port SSH en tête du fichier inclus.
add_port_to_dropin() {
    tmp="${SSHD_DROPIN}.port.$$"

    {
        printf 'Port %s\n' "$SSH_PORT"
        cat "$SSHD_DROPIN"
    } > "$tmp"

    cat "$tmp" > "$SSHD_DROPIN"
    rm -f "$tmp"
}

# Commente les anciennes directives Port du fichier principal.
comment_sshd_ports() {
    tmp="${SSHD_CONFIG}.ports.$$"

    sed 's/^\([[:space:]]*[Pp][Oo][Rr][Tt][[:space:]=]\)/# install.sh: \1/' \
        "$SSHD_CONFIG" > "$tmp"

    cat "$tmp" > "$SSHD_CONFIG"
    rm -f "$tmp"
}

# Applique le port SSH dans sshd.
set_sshd_port() {
    add_port_to_dropin
    comment_sshd_ports
    log "Port SSH configuré dans sshd : $SSH_PORT."
}

# Liste les ports réellement lus par sshd.
sshd_effective_ports() {
    sshd -T 2>/dev/null | awk 'tolower($1)=="port" {print $2}'
}

# Vérifie que sshd n’écoute que sur le port attendu.
verify_sshd_port() {
    ports=$(sshd_effective_ports)

    if [ -z "$ports" ]; then
        err "Aucun port SSH effectif trouvé."
        return 1
    fi

    for port in $ports; do
        if [ "$port" != "$SSH_PORT" ]; then
            err "Port SSH inattendu dans la configuration : $port"
            return 1
        fi
    done

    return 0
}
