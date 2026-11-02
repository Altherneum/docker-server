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

# Vrai si un groupe du nom donné existe déjà.
group_already_exists() {
    grep -q "^$1:" /etc/group
}

# Crée le compte admin avec bash si disponible, sinon sh.
# Un groupe du même nom peut déjà exister (image VPS, ancien compte) : dans ce
# cas useradd doit l'utiliser explicitement, sinon il refuse de créer le compte.
create_admin_user() {
    user_shell=/bin/sh

    if [ -x /bin/bash ]; then
        user_shell=/bin/bash
    fi

    log "Création du compte $ADMIN_USER..."

    if [ "$OS_FAMILY" = "alpine" ]; then
        if group_already_exists "$ADMIN_USER"; then
            adduser -D -s "$user_shell" -h "/home/$ADMIN_USER" \
                -G "$ADMIN_USER" "$ADMIN_USER"
        else
            adduser -D -s "$user_shell" -h "/home/$ADMIN_USER" "$ADMIN_USER"
        fi
        return 0
    fi

    if group_already_exists "$ADMIN_USER"; then
        useradd -m -s "$user_shell" -g "$ADMIN_USER" "$ADMIN_USER"
    else
        useradd -m -s "$user_shell" "$ADMIN_USER"
    fi
}

# Crée le compte, puis applique les groupes, sudo et mot de passe.
ensure_admin_user() {
    section "Compte administrateur"

    if id "$ADMIN_USER" >/dev/null 2>&1; then
        log "Le compte $ADMIN_USER existe déjà."
    else
        create_admin_user
    fi

    # Vérifie réellement le résultat : une erreur de useradd ne doit pas
    # laisser le script continuer sans compte administrateur.
    if ! id "$ADMIN_USER" >/dev/null 2>&1; then
        err "Le compte $ADMIN_USER n'a pas pu être créé."
        exit 1
    fi

    ensure_sudo_group
    ensure_docker_group
    ensure_sudoers
    ensure_admin_password
}
