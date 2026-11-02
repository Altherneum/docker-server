# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 04-packages.sh - installation de paquets selon la distribution
# =============================================================================

# Met à jour les listes de paquets une seule fois par exécution.
update_package_lists() {
    case "$OS_FAMILY" in
        alpine) apk update ;;
        debian) env DEBIAN_FRONTEND=noninteractive apt-get update ;;
        arch) pacman -Sy --noconfirm ;;
    esac
}

# Installe une liste de paquets selon la distribution.
install_packages() {
    case "$OS_FAMILY" in
        alpine) apk add --no-cache "$@" ;;
        debian) env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        arch) pacman -S --needed --noconfirm "$@" ;;
    esac
}

# Installe des paquets en mettant à jour les listes une seule fois.
pkg_install() {
    if [ "$#" -eq 0 ]; then
        return 0
    fi

    if [ "$PKG_UPDATED" = "0" ]; then
        update_package_lists
        PKG_UPDATED=1
    fi

    install_packages "$@"
}
