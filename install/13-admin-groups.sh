# shellcheck shell=sh
# =============================================================================
# 13-admin-groups.sh - groupes docker, sudo et wheel
# =============================================================================

# Vrai si l'utilisateur appartient déjà au groupe.
user_in_group() {
    user=$1
    group=$2
    id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"
}

# Ajoute un utilisateur à un groupe (commande différente sur Alpine).
add_user_to_group() {
    user=$1
    group=$2

    if [ "$OS_FAMILY" = "alpine" ]; then
        addgroup "$user" "$group"
        return 0
    fi

    usermod -aG "$group" "$user"
}

# Ajoute l'utilisateur qui a lancé sudo au groupe docker.
add_user_to_docker() {
    if [ -z "${SUDO_USER:-}" ]; then
        return 0
    fi

    if [ "$SUDO_USER" = "root" ]; then
        return 0
    fi

    if user_in_group "$SUDO_USER" docker; then
        log "Utilisateur $SUDO_USER déjà dans le groupe docker."
        return 0
    fi

    add_user_to_group "$SUDO_USER" docker
    log "Utilisateur $SUDO_USER ajouté au groupe docker (reconnectez-vous pour appliquer)."
}

# Groupe privilégié : sudo sur Debian, wheel sur Alpine et Arch.
sudo_group_name() {
    case "$OS_FAMILY" in
        alpine|arch) printf 'wheel\n' ;;
        *) printf 'sudo\n' ;;
    esac
}

# Ajoute le compte admin au groupe privilégié (sudo ou wheel).
ensure_sudo_group() {
    group=$(sudo_group_name)

    if ! grep -q "^${group}:" /etc/group; then
        if [ "$OS_FAMILY" = "alpine" ]; then
            addgroup "$group"
        else
            groupadd "$group"
        fi
    fi

    if user_in_group "$ADMIN_USER" "$group"; then
        log "Le compte $ADMIN_USER est déjà dans le groupe $group."
        return 0
    fi

    log "Ajout de $ADMIN_USER au groupe $group..."
    add_user_to_group "$ADMIN_USER" "$group"
}

# Le groupe docker permet d'utiliser docker ps/stats dans le MOTD.
ensure_docker_group() {
    if ! grep -q '^docker:' /etc/group; then
        return 0
    fi

    if user_in_group "$ADMIN_USER" docker; then
        log "Le compte $ADMIN_USER est déjà dans le groupe docker."
        return 0
    fi

    log "Ajout de $ADMIN_USER au groupe docker..."
    add_user_to_group "$ADMIN_USER" docker
}
