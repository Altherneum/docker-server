# shellcheck shell=sh
# =============================================================================
# 10-services.sh - activation et redémarrage des services
# =============================================================================

# Active un service au démarrage et le lance maintenant.
service_enable() {
    name=$1

    # systemd : activer + démarrer en une commande.
    if have_systemd; then
        systemctl enable --now "$name" || warn "Impossible d'activer $name."
        return 0
    fi

    # OpenRC (Alpine).
    if have_openrc; then
        rc-update add "$name" default || warn "Impossible d'activer $name."
        rc-service "$name" start || warn "Impossible de démarrer $name."
        return 0
    fi

    # Dans un conteneur de test, les services ne peuvent pas démarrer.
    if is_container; then
        log "Conteneur détecté : $name ne peut pas être démarré ici (normal en test)."
        return 0
    fi

    warn "Aucun gestionnaire de service : démarrez $name manuellement."
}

# Active un service au démarrage et le redémarre.
service_restart() {
    name=$1

    if have_systemd; then
        systemctl enable "$name" >/dev/null 2>&1 || true
        systemctl restart "$name" || warn "Impossible de redémarrer $name."
        return 0
    fi

    if have_openrc; then
        rc-update add "$name" default || warn "Impossible d'activer $name."
        rc-service "$name" restart || warn "Impossible de redémarrer $name."
        return 0
    fi

    if is_container; then
        log "Conteneur détecté : $name ne peut pas être redémarré ici (normal en test)."
        return 0
    fi

    warn "Aucun gestionnaire de service : redémarrez $name manuellement."
}
