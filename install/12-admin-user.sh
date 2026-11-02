# shellcheck shell=sh
# =============================================================================
# 12-admin-user.sh - validation et création du compte administrateur
# =============================================================================

# Vérifie que le nom du compte admin est compatible avec Linux.
is_valid_username() {
    name=$1

    case "$name" in
        '') return 1 ;;
        [0-9-]*) return 1 ;;
        *[!a-z0-9_-]*) return 1 ;;
    esac

    return 0
}

# Vérifie que le compte admin n’est pas root et que le nom est valide.
validate_username() {
    if [ "$ADMIN_USER" = "root" ]; then
        err "HARDEN_ADMIN_USER=root est interdit : utilisez admin, puis « su - » pour root."
        exit 1
    fi

    if ! is_valid_username "$ADMIN_USER"; then
        err "Nom d'utilisateur invalide : $ADMIN_USER"
        exit 1
    fi
}

# Retourne le dossier personnel d'un utilisateur.
get_user_home() {
    awk -F: -v user="$1" '$1==user {print $6; exit}' /etc/passwd
}

# Crée le compte admin avec bash si disponible, sinon sh.
create_admin_user() {
    user_shell=/bin/sh

    if [ -x /bin/bash ]; then
        user_shell=/bin/bash
    fi

    log "Création du compte $ADMIN_USER..."

    if [ "$OS_FAMILY" = "alpine" ]; then
        adduser -D -s "$user_shell" -h "/home/$ADMIN_USER" "$ADMIN_USER"
        return 0
    fi

    useradd -m -s "$user_shell" "$ADMIN_USER"
}

# Crée le compte, puis applique les groupes, sudo et mot de passe.
ensure_admin_user() {
    section "Compte administrateur"

    if id "$ADMIN_USER" >/dev/null 2>&1; then
        log "Le compte $ADMIN_USER existe déjà."
    else
        create_admin_user
    fi

    ensure_sudo_group
    ensure_docker_group
    ensure_sudoers
    ensure_admin_password
}
