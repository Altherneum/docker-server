# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 18-sshd-config.sh - écriture de la configuration sshd
# =============================================================================

# Refuse de désactiver le mot de passe SSH sans clé installée.
ensure_admin_key_present() {
    home=$(admin_home)
    authorized="$home/.ssh/authorized_keys"
    count=$(count_keys "$authorized")

    if [ "$count" -eq 0 ]; then
        err "Aucune clé pour $ADMIN_USER : refus de désactiver le mot de passe SSH."
        exit 1
    fi
}

# Sauvegarde sshd_config avant modification.
backup_sshd_config() {
    mkdir -p "$BACKUP_DIR"
    SSHD_BACKUP=$(backup_path "$SSHD_CONFIG")
    backup_file "$SSHD_CONFIG"
}

# Écrit les réglages SSH dans le fichier inclus.
write_sshd_dropin() {
    write_file "$SSHD_DROPIN" 600 <<EOF
# Généré par install.sh - ne pas modifier à la main
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PermitRootLogin no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
EOF
}

# Restaure la sauvegarde et arrête le script.
fail_sshd() {
    err "$1"
    restore_sshd
    exit 1
}

# Ajoute l’Include des fichiers sshd_config.d si absent.
ensure_sshd_include() {
    if grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' "$SSHD_CONFIG"; then
        return 0
    fi

    tmp="${SSHD_CONFIG}.install.$$"
    {
        printf '# Ajouté par install.sh\n'
        printf 'Include /etc/ssh/sshd_config.d/*.conf\n\n'
        cat "$SSHD_CONFIG"
    } > "$tmp"
    cat "$tmp" > "$SSHD_CONFIG"
    rm -f "$tmp"
    log "Directive Include ajoutée à $SSHD_CONFIG."
}

# Configure, valide et recharge SSH.
configure_sshd() {
    section "Configuration SSH"

    if [ ! -f "$SSHD_CONFIG" ]; then
        err "$SSHD_CONFIG introuvable."
        exit 1
    fi

    ensure_admin_key_present
    backup_sshd_config
    mkdir -p /etc/ssh/sshd_config.d
    write_sshd_dropin
    ensure_sshd_include
    set_sshd_port

    if ! validate_sshd_config; then
        fail_sshd "Configuration SSH invalide."
    fi

    if ! verify_sshd_setting PasswordAuthentication no; then
        fail_sshd "PasswordAuthentication n'a pas pu être désactivé."
    fi

    if ! verify_sshd_setting PermitRootLogin no; then
        fail_sshd "PermitRootLogin n'a pas pu être désactivé."
    fi

    if ! verify_sshd_port; then
        fail_sshd "Le port SSH effectif ne correspond pas à $SSH_PORT."
    fi

    log "Restart SSH ----------------------------------"
    if ! reload_ssh; then
        fail_sshd "Rechargement SSH impossible."
    fi
    log "End restart SSH ----------------------------------"

    log "Configuration SSH validée (port $SSH_PORT, mot de passe désactivé, root bloqué)."
}
