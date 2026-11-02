# shellcheck shell=sh
# =============================================================================
# 14-admin-sudo.sh - règle sudo du compte admin
# =============================================================================

# Écrit et valide la règle sudo du compte admin.
ensure_sudoers() {
    if ! command_exists sudo; then
        pkg_install sudo
    fi

    file="/etc/sudoers.d/90-docker-server-$ADMIN_USER"

    write_file "$file" 440 <<EOF
# Généré par install.sh - ne pas modifier à la main
$ADMIN_USER ALL=(ALL:ALL) ALL
EOF

    if command_exists visudo; then
        if ! visudo -cf "$file" >/dev/null 2>&1; then
            err "Fichier sudoers invalide : $file"
            rm -f "$file"
            exit 1
        fi
    fi

    log "Règle sudo écrite dans $file."
}
