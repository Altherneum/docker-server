# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 21-sshd-service.sh - rechargement et restauration de SSH
# =============================================================================

# Redémarre SSH via systemd.
# Un simple reload ne recrée pas toujours le socket d'écoute : le nouveau port
# n'est réellement pris en compte qu'après un redémarrage complet du service.
reload_ssh_systemd() {
    if systemctl restart ssh 2>/dev/null; then
        log "Reload SSH OK"
        return 0
    fi
    
    if systemctl systemctl restart sshd 2>/dev/null; then
        log "Reload SSHD OK"
        return 0
    fi
}

# Recharge SSH via OpenRC.
reload_ssh_openrc() {
    if rc-service sshd reload 2>/dev/null; then
        log "Reload SSH OK"
        return 0
    fi

    if rc-service sshd reload 2>/dev/null; then
        log "Reload SSHD OK"
        return 0
    fi
}

# Recharge SSH avec le gestionnaire disponible.
reload_ssh() {
    if have_systemd; then
        reload_ssh_systemd
        log "Reload SSH OK SystemD"
        return $?
    fi

    if have_openrc; then
        reload_ssh_openrc
        log "Reload SSH OK OpenRC"
        return $?
    fi

    warn "Rechargez SSH manuellement : systemctl reload ssh (ou sshd)."
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
