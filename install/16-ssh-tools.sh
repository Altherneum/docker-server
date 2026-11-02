# shellcheck shell=sh
# =============================================================================
# 16-ssh-tools.sh - installation d'OpenSSH, des clés d'hôte et des journaux
# =============================================================================

# Vrai si OpenSSH doit être installé.
need_openssh_package() {
    if ! command_exists ssh-keygen; then
        return 0
    fi
    if ! command_exists sshd; then
        return 0
    fi
    return 1
}

# Installe le paquet OpenSSH selon la distribution.
install_openssh() {
    case "$OS_FAMILY" in
        alpine) pkg_install openssh ;;
        debian) pkg_install openssh-client openssh-server ;;
        arch) pkg_install openssh ;;
    esac
}

# Installe OpenSSH et crée les clés d’hôte manquantes.
# Installe rsyslog sur Debian/Arch pour fournir auth.log au conteneur fail2ban.
ensure_host_ssh_logs() {
    case "$OS_FAMILY" in
        debian|arch)
            pkg_install rsyslog
            service_enable rsyslog
            ;;
    esac
}

ensure_ssh_tools() {
    if need_openssh_package; then
        install_openssh
    fi

    # -A crée seulement les clés d'hôte absentes.
    if command_exists ssh-keygen; then
        ssh-keygen -A
    fi

    ensure_host_ssh_logs
}
