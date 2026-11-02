# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 01-cli.sh - dossier du projet et options de la ligne de commande
# =============================================================================

# Si install.sh est lancé depuis un clone, utiliser ce clone au lieu de /opt.
detect_script_dir() {
    if [ ! -f "$0" ]; then
        return 0
    fi

    script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)

    if [ -z "$script_dir" ]; then
        return 0
    fi

    # Un vrai dépôt contient compose.yaml à sa racine.
    if [ ! -f "$script_dir/compose.yaml" ]; then
        return 0
    fi

    SERVER_DIR="$script_dir"
    REPO_DIR="$SERVER_DIR"
    USE_SCRIPT_DIR=1
}

# Vérifie qu'une option qui attend une valeur en a bien une.
need_value() {
    if [ "$#" -lt 2 ]; then
        err "Valeur manquante pour $1"
        exit 1
    fi

    case "$2" in
        -*) err "Valeur manquante pour $1"; exit 1 ;;
    esac
}

# Seule option acceptée : --pubkey-file.
parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --pubkey-file)
                need_value "$@"
                HARDEN_PUBKEY_FILE=$2
                shift 2
                ;;
            *)
                err "Option inconnue : $1"
                err "Usage : sudo ./install.sh --pubkey-file /tmp/id_ed25519.pub"
                exit 1
                ;;
        esac
    done
}
