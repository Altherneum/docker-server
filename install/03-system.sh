# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 03-system.sh - droits root, OS et gestionnaire de services
# =============================================================================

# L'installation doit être lancée avec sudo.
need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "Lancez avec sudo : sudo ./install.sh --pubkey-file /tmp/id_ed25519.pub"
        exit 1
    fi
}

# Vrai si une commande existe dans le PATH.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Détecte un conteneur Docker/Podman pour éviter d'échouer sur les services.
is_container() {
    [ -f /.dockerenv ] || [ -f /run/.containerenv ]
}

# Vrai si systemd est réellement utilisé (et pas seulement installé).
have_systemd() {
    [ -d /run/systemd/system ] && command_exists systemctl
}

# Vrai si OpenRC est disponible (Alpine).
have_openrc() {
    command_exists rc-service
}

# Traduit ID / ID_LIKE en famille de distribution.
detect_os_family() {
    id=$1
    like=$2

    case "$id" in
        alpine) printf 'alpine\n'; return 0 ;;
        arch|archarm) printf 'arch\n'; return 0 ;;
        debian|ubuntu) printf 'debian\n'; return 0 ;;
    esac

    case " $like " in
        *debian*|*ubuntu*) printf 'debian\n' ;;
        *arch*) printf 'arch\n' ;;
    esac
}

# Lit /etc/os-release et remplit OS_ID et OS_FAMILY.
detect_os() {
    if [ ! -f /etc/os-release ]; then
        err "Impossible de détecter l'OS (/etc/os-release manquant)."
        exit 1
    fi

    . /etc/os-release
    OS_ID="${ID:-}"
    OS_FAMILY=$(detect_os_family "${ID:-}" "${ID_LIKE:-}")

    if [ -z "$OS_FAMILY" ]; then
        err "OS non supporté : ${PRETTY_NAME:-${ID:-inconnu}}"
        exit 1
    fi

    log "OS détecté : ${PRETTY_NAME:-${ID:-inconnu}} ($OS_FAMILY)"
}
