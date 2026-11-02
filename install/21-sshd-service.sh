# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 21-sshd-service.sh - rechargement et restauration de SSH
# =============================================================================

# Recharge SSH via systemd.
reload_ssh_systemd() {
    if systemctl reload ssh 2>/dev/null; then
        return 0
    fi
    if systemctl reload sshd 2>/dev/null; then
        return 0
    fi
    if systemctl restart ssh 2>/dev/null; then
        return 0
    fi
    systemctl restart sshd 2>/dev/null
}

# Recharge SSH via OpenRC.
reload_ssh_openrc() {
    if rc-service sshd reload 2>/dev/null; then
        return 0
    fi
    rc-service sshd restart 2>/dev/null
}

# Recharge SSH avec le gestionnaire disponible.
reload_ssh() {
    if have_systemd; then
        reload_ssh_systemd
        return $?
    fi

    if have_openrc; then
        reload_ssh_openrc
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
