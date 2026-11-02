# shellcheck shell=sh
# =============================================================================
# 23-auto-updates.sh - mises à jour Linux automatiques
#
# Aucun redémarrage automatique n'est effectué.
# =============================================================================

# Active les mises à jour automatiques Debian.
configure_debian_updates() {
    pkg_install unattended-upgrades

    write_file /etc/apt/apt.conf.d/20auto-upgrades 644 <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    write_file /etc/apt/apt.conf.d/51docker-server-unattended 644 <<'EOF'
// Généré par install.sh
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
EOF

    log "unattended-upgrades activé (pas de redémarrage automatique)."
}

# Programme les mises à jour Alpine.
configure_alpine_updates() {
    write_file /etc/periodic/weekly/99-docker-server-upgrade 755 <<'EOF'
#!/bin/sh
# Généré par install.sh : mise à jour hebdomadaire des paquets Alpine.
apk -U upgrade -a
EOF

    service_enable crond
    log "Mise à jour hebdomadaire Alpine programmée (crond)."
}

# Programme les mises à jour Arch.
configure_arch_updates() {
    write_file /etc/systemd/system/docker-server-upgrade.service 644 <<'EOF'
[Unit]
Description=Mises à jour Arch Linux

[Service]
Type=oneshot
ExecStart=/usr/bin/pacman -Syu --noconfirm
EOF

    write_file /etc/systemd/system/docker-server-upgrade.timer 644 <<'EOF'
[Unit]
Description=Mises à jour Arch Linux hebdomadaires

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    if ! have_systemd; then
        warn "systemd absent : activez docker-server-upgrade.timer manuellement."
        return 0
    fi

    systemctl daemon-reload
    systemctl enable --now docker-server-upgrade.timer \
        || warn "Impossible d'activer les mises à jour Arch."
    log "Mises à jour Arch programmées chaque semaine."
}

# Choisit les mises à jour selon la distribution.
configure_auto_updates() {
    section "Mises à jour automatiques"

    case "$OS_FAMILY" in
        debian) configure_debian_updates ;;
        alpine) configure_alpine_updates ;;
        arch) configure_arch_updates ;;
    esac
}
