# shellcheck shell=sh
# =============================================================================
# 25-motd.sh - message affiché à l'ouverture d'une session SSH
# =============================================================================

# Écrit le script du MOTD SSH.
write_motd() {
    write_file /etc/profile.d/00-docker-server-motd.sh 644 <<'EOF'
# shellcheck shell=sh
# Généré par install.sh - MOTD simple pour SSH.

case $- in
    *i*) ;;
    *) return 0 ;;
esac

if [ -n "${DOCKER_MOTD_SHOWN:-}" ]; then
    return 0
fi
export DOCKER_MOTD_SHOWN=1

echo
echo "============================================================"
echo " Serveur : $(hostname 2>/dev/null || echo serveur)"
if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo " OS      : ${PRETTY_NAME:-${NAME:-inconnu}}"
fi
echo " Noyau   : $(uname -r) $(uname -m)"
echo " Uptime  : $(uptime -p 2>/dev/null || uptime)"
echo " Charge  : $(uptime | sed 's/.*load average: //')"

mem=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2}')
if [ -z "$mem" ]; then
    mem=$(free -m 2>/dev/null | awk '/^Mem:/ {print $3 "M / " $2 "M"}')
fi
echo " RAM     : ${mem:-inconnue}"
echo " Disque  : $(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"

ip_addr=$(hostname -I 2>/dev/null | cut -d' ' -f1)
if [ -z "$ip_addr" ]; then
    ip_addr=$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2; exit}')
fi
echo " IP      : ${ip_addr:-inconnue}"
echo "============================================================"
echo

echo "Conteneurs Docker :"
if command -v docker >/dev/null 2>&1; then
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null \
        || echo "  (docker inaccessible)"
    echo
    echo "Utilisation Docker :"
    docker stats --no-stream \
        --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' 2>/dev/null \
        || true
else
    echo "  Docker non installé."
fi

echo
echo "Utilisateurs en ligne :"
who 2>/dev/null || echo "  (aucun)"
echo
EOF
}

# Sauvegarde puis installe le MOTD.
configure_motd() {
    section "MOTD SSH"

    backup_file /etc/profile.d/00-docker-server-motd.sh
    write_motd

    log "MOTD installé : /etc/profile.d/00-docker-server-motd.sh."
}
