# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 15-admin-password.sh - mot de passe sudo du compte admin
# =============================================================================

# Vrai si le compte possède déjà un mot de passe utilisable.
user_has_password() {
    hash=$(awk -F: -v user="$ADMIN_USER" '$1==user {print $2; exit}' /etc/shadow 2>/dev/null || true)

    case "$hash" in
        ''|'!'*|'*'*) return 1 ;;
        *) return 0 ;;
    esac
}

# Génère un mot de passe aléatoire en hexadécimal.
generate_password() {
    openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

# Applique le mot de passe fourni ou en génère un.
ensure_admin_password() {
    # CHANGE_ME est la valeur du modèle .env : la traiter comme « non fourni ».
    if [ -n "$ADMIN_PASSWORD" ] && [ "$ADMIN_PASSWORD" != "CHANGE_ME" ]; then
        log "Application du mot de passe fourni pour $ADMIN_USER..."
        if ! printf '%s:%s\n' "$ADMIN_USER" "$ADMIN_PASSWORD" | chpasswd; then
            err "Impossible d'appliquer le mot de passe de $ADMIN_USER."
            exit 1
        fi
        return 0
    fi

    if user_has_password; then
        log "Le compte $ADMIN_USER a déjà un mot de passe (conservé)."
        return 0
    fi

    ADMIN_INITIAL_PASSWORD=$(generate_password)
    log "Génération d'un mot de passe pour $ADMIN_USER (nécessaire pour sudo)."
    if ! printf '%s:%s\n' "$ADMIN_USER" "$ADMIN_INITIAL_PASSWORD" | chpasswd; then
        err "Impossible de définir le mot de passe de $ADMIN_USER."
        exit 1
    fi
}
