#!/bin/sh
# =============================================================================
# Diagnostic réseau en lecture seule : ports publiés par Docker, UFW,
# iptables/ip6tables et routage IPv4/IPv6.
# Usage : sudo make net-diag
# =============================================================================
set -u

cd "$(dirname "$0")/.."
ENV_FILE=${ENV_FILE:-.env}

get_env() {
    [ -f "$ENV_FILE" ] || return 0
    sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

# Compose développe les références ${DOMAIN_NAME} / ${TLD} / ${DOMAIN} du .env ;
# `get_env` les lit littéralement. On les développe ici aussi.
expand_env_value() {
    value=$1
    domain_name=$(get_env DOMAIN_NAME)
    tld=$(get_env TLD)
    printf '%s' "$value" | sed \
        -e "s|\${DOMAIN_NAME}|${domain_name}|g" \
        -e "s|\${TLD}|${tld}|g" \
        -e "s|\${DOMAIN}|${domain_name}${tld}|g"
}

PROXY_NETWORK=$(expand_env_value "${PROXY_NETWORK:-$(get_env PROXY_NETWORK)}")
PROXY_NETWORK=${PROXY_NETWORK:-proxy}

SS_PORTS=':(80|443|25565)\b'
IPT_PORTS='--dport (80|443|25565)\b'

section() {
    printf '\n=== %s ===\n' "$1"
}

if [ "$(id -u)" -ne 0 ]; then
    echo "! UFW et iptables demandent les droits root : relancer avec 'sudo make net-diag'" >&2
fi

section "Interfaces réseau"
if command -v ip >/dev/null 2>&1; then
    ip -br addr
else
    echo "(commande ip indisponible)"
fi

section "Ports en écoute sur l'hôte (80, 443, 25565)"
if command -v ss >/dev/null 2>&1; then
    # 0.0.0.0:443 = IPv4, [::]:443 = IPv6 ; les deux sont attendus.
    # Colonne 4 = adresse locale:port. Pas de \b : mawk ne le gère pas.
    ss -lntp 2>/dev/null | awk 'NR == 1 || $4 ~ /:(80|443|25565)$/'
    echo "-- processus docker-proxy --"
    ss -lntp 2>/dev/null | grep -E 'docker-proxy' | head -20 \
        || echo "(aucun docker-proxy visible ; lancer avec sudo)"
else
    echo "(commande ss indisponible)"
fi

section "UFW"
if command -v ufw >/dev/null 2>&1; then
    ufw status verbose 2>/dev/null || echo "(ufw n'a pas pu répondre)"
else
    echo "(ufw indisponible)"
fi
if [ -f /etc/default/ufw ]; then
    grep -E '^(DEFAULT_INPUT_POLICY|DEFAULT_FORWARD_POLICY|IPV6)=' /etc/default/ufw 2>/dev/null
fi

section "Docker"
if command -v docker >/dev/null 2>&1; then
    docker version --format 'Server {{.Server.Version}}' 2>/dev/null \
        || echo "(démon Docker injoignable)"
    docker info --format 'FirewallBackend={{json .FirewallBackend}}' 2>/dev/null \
        || true
else
    echo "(docker indisponible)"
fi
if [ -f /etc/docker/daemon.json ]; then
    cat /etc/docker/daemon.json
else
    echo "(pas de /etc/docker/daemon.json)"
fi

section "Conteneurs et ports publiés"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | head -40 \
    || echo "(docker ps indisponible)"

section "IP des conteneurs (doit correspondre aux cibles DNAT)"
docker ps --format '{{.Names}}' 2>/dev/null | while read -r name; do
    ips=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$name" 2>/dev/null)
    printf '%-42s %s\n' "$name" "$ips"
done

section "Réseau Docker ${PROXY_NETWORK}"
docker network inspect "$PROXY_NETWORK" \
    --format 'EnableIPv4={{.EnableIPv4}} EnableIPv6={{.EnableIPv6}} IPAM={{json .IPAM.Config}}' \
    2>/dev/null || echo "(réseau introuvable)"

section "iptables IPv4 : NAT Docker"
if command -v iptables >/dev/null 2>&1; then
    iptables -t nat -S DOCKER 2>/dev/null | grep -E -e "$IPT_PORTS" \
        || echo "aucune règle IPv4 pour ces ports"
else
    echo "(iptables indisponible)"
fi

section "iptables IPv4 : PREROUTING (le saut vers DOCKER applique le NAT)"
if ! iptables -t nat -S PREROUTING >/dev/null 2>&1; then
    echo "(non vérifié : iptables requiert root)"
elif iptables -t nat -S PREROUTING 2>/dev/null | grep -q -- '-j DOCKER'; then
    echo "OK : PREROUTING -> DOCKER présent"
else
    echo "PROBLÈME : PREROUTING ne saute pas vers DOCKER, le NAT IPv4 est inactif"
    echo "  correction immédiate :"
    echo "    sudo iptables -t nat -I PREROUTING 1 -m addrtype --dst-type LOCAL -j DOCKER"
    echo "  ou redémarrage propre : sudo systemctl restart docker"
fi
iptables -t nat -S PREROUTING 2>/dev/null | head -20 || true

section "iptables IPv4 : chaîne FORWARD"
iptables -S FORWARD 2>/dev/null | head -10 || echo "(iptables indisponible)"

section "iptables IPv4 : chaîne DOCKER-FORWARD (ACCEPT des ports publiés)"
if iptables -S DOCKER-FORWARD >/dev/null 2>&1; then
    iptables -S DOCKER-FORWARD 2>/dev/null | grep -E -e "$IPT_PORTS" \
        || echo "aucune règle pour ces ports dans DOCKER-FORWARD"
else
    echo "(chaîne absente)"
fi

section "iptables IPv4 : chaîne INPUT"
iptables -S INPUT 2>/dev/null | head -20 || echo "(iptables indisponible)"

section "iptables IPv4 : chaîne MAILCOW (netfilter mailcow)"
if ! iptables -S MAILCOW >/dev/null 2>&1; then
    echo "(non vérifié : iptables requiert root)"
elif iptables -S MAILCOW 2>/dev/null | grep -q .; then
    iptables -S MAILCOW 2>/dev/null | head -30
else
    echo "(chaîne MAILCOW absente)"
fi

section "iptables IPv4 : règles REJECT (source possible de « Connection refused »)"
if iptables -S >/dev/null 2>&1; then
    iptables -S 2>/dev/null | grep -- '-j REJECT' | head -20 \
        || echo "(aucune règle REJECT)"
else
    echo "(non vérifié : iptables requiert root)"
fi

section "ip6tables IPv6 : NAT Docker"
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -t nat -S DOCKER 2>/dev/null | grep -E -e "$IPT_PORTS" \
        || echo "aucune règle IPv6 pour ces ports (normal si le réseau est IPv4 seul :
   l'IPv6 passe alors par docker-proxy)"
else
    echo "(ip6tables indisponible)"
fi

section "Backends iptables"
if command -v update-alternatives >/dev/null 2>&1; then
    update-alternatives --display iptables 2>/dev/null | sed -n '1,3p'
    update-alternatives --display ip6tables 2>/dev/null | sed -n '1,3p'
else
    echo "(update-alternatives indisponible)"
fi

section "Routage noyau"
if command -v sysctl >/dev/null 2>&1; then
    sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding 2>/dev/null
else
    echo "(sysctl indisponible)"
fi

cat <<'EOF'

=== Interprétation ===
- « Connection refused » + aucune ligne 0.0.0.0 dans « Ports en écoute » et
  aucune ligne docker-proxy : aucun processus n'écoute en IPv4.
- IPv4 refusé alors que « PREROUTING -> DOCKER » est absent : les règles NAT
  existent mais ne sont jamais appliquées. Docker doit les recréer :
      sudo systemctl restart docker && sudo make up
- « timeout » : paquet filtré (UFW ou pare-feu de l'hébergeur), pas un refus.
- Règle absente de « iptables IPv4 : NAT Docker » alors que la règle IPv6
  existe : règles Docker perdues, les recréer avec :
      sudo systemctl restart docker && sudo make up
- IPv6 seul fonctionnel sans règle ip6tables : normal sur un réseau IPv4 seul,
  docker-proxy fait le relais ; cela ne prouve pas que le NAT IPv4 fonctionne.
- Chaîne MAILCOW avant DOCKER-FORWARD : bug connu de mailcow (#6795) qui peut
  gêner la publication des ports ; voir la section du dépannage.
- Règle `f2b-…` contenant votre IP : IP bannie par fail2ban (tous les ports
  IPv4) → `sudo make fail2ban-unban IP=<votre ip>`.
- EnableIPv4=false : réseau Docker IPv6 uniquement, à recréer.
- DEFAULT_FORWARD_POLICY différent de "ACCEPT" : Docker ne peut plus router.
EOF
