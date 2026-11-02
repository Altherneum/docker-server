# shellcheck shell=sh
# =============================================================================
# 05-docker-install.sh - installation de Docker et des outils
# =============================================================================

# Alpine : Docker est fourni par plusieurs paquets et OpenRC.
install_alpine() {
    log "Installation des paquets Alpine..."
    apk update && apk upgrade
    apk add tzdata
    ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
    echo "Europe/Paris" > /etc/timezone
    # docker-openrc fournit /etc/init.d/docker (absent du méta-paquet docker).
    apk add git curl openssl make docker docker-cli-compose docker-cli-buildx docker-openrc
    rc-update add docker default
    service docker start
}

# Arch : dépôt officiel.
install_arch() {
    log "Installation des paquets Arch..."
    pacman -Syu --needed --noconfirm docker docker-compose git make openssl curl
    systemctl enable --now docker
}

# Debian/Ubuntu : dépôt officiel Docker.
install_debian() {
    log "Installation des paquets Debian/Ubuntu..."
    apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    docker_repo="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc]"
    docker_repo="$docker_repo https://download.docker.com/linux/${OS_ID} $(lsb_release -cs) stable"
    echo "$docker_repo" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin \
        git make openssl
    systemctl enable --now docker
}

# Choisit l'installation selon la distribution détectée.
install_os_packages() {
    case "$OS_ID" in
        alpine) install_alpine ;;
        arch) install_arch ;;
        debian|ubuntu) install_debian ;;
        *)
            err "OS non supporté : $OS_ID (Alpine, Arch, Debian, Ubuntu uniquement)."
            exit 1
            ;;
    esac
}
