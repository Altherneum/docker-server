# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 21-sshd-service.sh - redémarrage et restauration de SSH
# =============================================================================

# Repasse SSH en mode service classique.
# Sur Debian 13 et Ubuntu récents, ssh.socket possède le port d'écoute et la
# directive Port de sshd_config est ignorée. On désactive donc le socket une
# bonne fois pour toutes : ssh.service lit sshd_config et applique le port.
use_ssh_service() {
    if ! have_systemd; then
        return 0
    fi

    # Supprime le drop-in de port d'une ancienne version du script.
    if [ -e "$SSH_SOCKET_DROPIN" ]; then
        rm -f "$SSH_SOCKET_DROPIN"
        systemctl daemon-reload
    fi

    if systemctl cat ssh.socket >/dev/null 2>&1; then
        if systemctl disable --now ssh.socket 2>/dev/null; then
            log "Activation SSH par socket désactivée."
        else
            warn "Impossible de désactiver ssh.socket."
        fi
    fi
}

# Redémarre SSH via systemd.
reload_ssh_systemd() {
    use_ssh_service

    if systemctl enable ssh.service >/dev/null 2>&1 \
        && systemctl restart ssh.service 2>/dev/null; then
        log "Reload SSH OK"
        return 0
    fi

    if systemctl enable sshd.service >/dev/null 2>&1 \
        && systemctl restart sshd.service 2>/dev/null; then
        log "Reload SSHD OK"
        return 0
    fi

    return 1
}

# Recharge SSH via OpenRC.
reload_ssh_openrc() {
    if rc-service sshd reload 2>/dev/null; then
        log "Reload SSH OK"
        return 0
    fi

    if rc-service sshd restart 2>/dev/null; then
        log "Reload SSHD OK"
        return 0
    fi

    return 1
}

# Recharge SSH avec le gestionnaire disponible.
reload_ssh() {
    if have_systemd; then
        if reload_ssh_systemd; then
            log "Reload SSH OK SystemD"
            return 0
        fi
        return 1
    fi

    if have_openrc; then
        if reload_ssh_openrc; then
            log "Reload SSH OK OpenRC"
            return 0
        fi
        return 1
    fi

    warn "Rechargez SSH manuellement : systemctl restart ssh (ou sshd)."
    return 0
}

# Restaure la sauvegarde sshd en cas d’échec.
restore_sshd() {
    rm -f "$SSHD_DROPIN" 2>/dev/null || true

    if [ -n "$SSHD_BACKUP" ]; then
        if [ -f "$SSHD_BACKUP" ]; then
            cp -a "$SSHD_BACKUP" "$SSHD_CONFIG"
        fi
    fi

    log "Configuration SSH restaurée."
    reload_ssh || true
}
