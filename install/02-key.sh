# shellcheck shell=sh
# =============================================================================
# 02-key.sh - validation de la clé SSH obligatoire
#
# La clé est vérifiée avant l'installation des paquets et avant toute
# modification du système. Sans clé valide, install.sh s'arrête.
# =============================================================================

# Détermine le fichier de clé à utiliser (option ou .env) et le rend absolu.
resolve_pubkey_file() {
    if [ -z "$HARDEN_PUBKEY_FILE" ]; then
        HARDEN_PUBKEY_FILE=$(read_env HARDEN_SSH_PUBKEY_FILE)
    fi

    if [ -z "$HARDEN_PUBKEY_FILE" ]; then
        err "Clé SSH obligatoire : --pubkey-file /tmp/id_ed25519.pub"
        exit 1
    fi

    case "$HARDEN_PUBKEY_FILE" in
        /*) ;;
        *) HARDEN_PUBKEY_FILE="$(pwd)/$HARDEN_PUBKEY_FILE" ;;
    esac
}

# Vrai si le fichier contient au moins une clé publique OpenSSH connue.
pubkey_file_is_valid() {
    file=$1
    grep -Eq '(^|[[:space:]])(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[^ ]+|sk-(ssh|ecdsa)-[^ ]+)[[:space:]]' "$file"
}

# Vérifie la présence, la lisibilité et le format de la clé.
require_ssh_key() {
    resolve_pubkey_file

    if [ ! -r "$HARDEN_PUBKEY_FILE" ]; then
        err "Fichier de clé publique illisible : $HARDEN_PUBKEY_FILE"
        exit 1
    fi

    if [ ! -s "$HARDEN_PUBKEY_FILE" ]; then
        err "Fichier de clé publique vide : $HARDEN_PUBKEY_FILE"
        exit 1
    fi

    if ! pubkey_file_is_valid "$HARDEN_PUBKEY_FILE"; then
        err "Aucune clé SSH publique valide dans : $HARDEN_PUBKEY_FILE"
        exit 1
    fi

    log "Clé SSH publique validée : $HARDEN_PUBKEY_FILE"
}
