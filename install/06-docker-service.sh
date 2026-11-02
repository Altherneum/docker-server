# shellcheck shell=sh
# =============================================================================
# 06-docker-service.sh - configuration du service Docker
# =============================================================================

# Vérifie que la commande `docker compose` est disponible.
ensure_compose_plugin() {
    if docker compose version >/dev/null 2>&1; then
        return 0
    fi

    # Certaines distributions fournissent encore l'ancien binaire.
    if command_exists docker-compose; then
        compose_bin=$(command -v docker-compose)
        mkdir -p /usr/lib/docker/cli-plugins
        ln -sf "$compose_bin" /usr/lib/docker/cli-plugins/docker-compose
        log "Plugin Docker Compose lié depuis docker-compose."
        return 0
    fi

    err "Docker Compose est introuvable."
    exit 1
}

# Redémarre Docker selon le gestionnaire de services disponible.
reload_docker_service() {
    if have_systemd; then
        systemctl daemon-reload
        systemctl restart docker
        return 0
    fi

    if command_exists rc-service; then
        rc-service docker restart
        return 0
    fi

    if command_exists service; then
        service docker restart
        return 0
    fi

    warn "Aucun gestionnaire de service détecté : redémarrez Docker manuellement."
}

# Écrit une configuration de logs Docker si aucune n'existe déjà.
# On ne fusionne pas un fichier existant pour ne pas écraser la configuration
# de l'utilisateur.
configure_docker() {
    log "Configuration de Docker daemon..."
    mkdir -p /etc/docker

    if [ -f /etc/docker/daemon.json ]; then
        warn "/etc/docker/daemon.json existe déjà : fichier conservé (pas de fusion automatique)."
        warn "Ajoutez-y log-driver=json-file et log-opts max-size=10m/max-file=3 si nécessaire."
    else
        cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
    fi

    reload_docker_service
}

# Attend que le démon Docker réponde avant de continuer.
wait_for_docker() {
    log "Attente du démarrage de Docker..."
    i=0

    while [ "$i" -lt 30 ]; do
        if docker info >/dev/null 2>&1; then
            log "Docker est prêt."
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done

    err "Docker ne répond pas après 30 secondes."
    exit 1
}
