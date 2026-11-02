# shellcheck shell=sh
# =============================================================================
# 17-ssh-keys.sh - installation des clés SSH autorisées
# =============================================================================

# Retourne le dossier personnel du compte admin.
admin_home() {
    get_user_home "$ADMIN_USER"
}

# Retourne le groupe principal d’un utilisateur.
user_group() {
    id -gn "$1" 2>/dev/null || printf '%s\n' "$1"
}

# Nettoie les espaces et les retours chariot d’une clé.
clean_key_line() {
    printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Vrai si la ligne ressemble à une clé publique OpenSSH.
is_key_line() {
    printf '%s\n' "$1" | grep -Eq \
        '(^|[[:space:]])(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[^ ]+|sk-(ssh|ecdsa)-[^ ]+)[[:space:]]'
}

# Ajoute une clé valide si elle n’est pas déjà présente.
add_authorized_key() {
    line=$(clean_key_line "$1")
    key_file=$2

    if [ -z "$line" ]; then
        return 0
    fi

    case "$line" in
        \#*) return 0 ;;
    esac

    if ! is_key_line "$line"; then
        warn "Clé ignorée (format inattendu) : ${line%% *}"
        return 0
    fi

    if grep -qxF "$line" "$key_file" 2>/dev/null; then
        return 0
    fi

    printf '%s\n' "$line" >> "$key_file"
    log "Clé SSH ajoutée dans $key_file."
}

# Compte les clés publiques valides d’un fichier.
count_keys() {
    file=$1
    count=0

    if [ ! -f "$file" ]; then
        printf '0\n'
        return 0
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        if is_key_line "$line"; then
            count=$((count + 1))
        fi
    done < "$file"

    printf '%s\n' "$count"
}

# Prépare ~/.ssh/authorized_keys avec les bons droits.
prepare_authorized_keys() {
    home=$(admin_home)

    if [ -z "$home" ]; then
        err "Dossier personnel de $ADMIN_USER introuvable."
        exit 1
    fi

    group=$(user_group "$ADMIN_USER")
    authorized="$home/.ssh/authorized_keys"

    mkdir -p "$home/.ssh"
    touch "$authorized"
    chown "$ADMIN_USER:$group" "$home/.ssh" "$authorized" 2>/dev/null || true
    chmod 700 "$home/.ssh"
    chmod 600 "$authorized"

    printf '%s\n' "$authorized"
}

# Installe toutes les clés valides du fichier fourni à install.sh.
ensure_ssh_keys() {
    section "Clés SSH"

    if [ -z "$HARDEN_PUBKEY_FILE" ]; then
        err "Aucune clé SSH publique fournie."
        exit 1
    fi

    authorized=$(prepare_authorized_keys)

    while IFS= read -r line || [ -n "$line" ]; do
        add_authorized_key "$line" "$authorized"
    done < "$HARDEN_PUBKEY_FILE"

    count=$(count_keys "$authorized")

    if [ "$count" -eq 0 ]; then
        err "Aucune clé publique valide n'a été installée pour $ADMIN_USER."
        exit 1
    fi

    log "$count clé(s) publique(s) autorisée(s) pour $ADMIN_USER."
}
