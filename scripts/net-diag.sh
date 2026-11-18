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

section "Interfaces réseau"
if command -v ip >/dev/null 2>&1; then
    ip -br addr
else
    echo "(commande ip indisponible)"
fi

section "Ports en écoute sur l'hôte (80, 443, 25565)"
if command -v ss >/dev/null 2>&1; then
    # 0.0.0.0:443 = IPv4, [::]:443 = IPv6 ; les deux sont attendus.
    ss -lntp 2>/dev/null | awk 'NR == 1 || /:80\b|:443\b|:25565\b/'
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

section "iptables IPv4 : chaîne FORWARD"
iptables -S FORWARD 2>/dev/null | head -10 || echo "(iptables indisponible)"

section "ip6tables IPv6 : NAT Docker"
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -t nat -S DOCKER 2>/dev/null | grep -E -e "$IPT_PORTS" \
        || echo "aucune règle IPv6 pour ces ports"
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
- « Connection refused » + aucune ligne 0.0.0.0 dans « Ports en écoute » :
  aucun processus n'écoute en IPv4, Docker n'a pas publié le port en IPv4.
- « timeout » : paquet filtré (UFW ou pare-feu de l'hébergeur), pas un refus.
- Règle absente de « iptables IPv4 : NAT Docker » alors que la règle IPv6
  existe : règles Docker perdues, les recréer avec :
      sudo systemctl restart docker && sudo make up
- EnableIPv4=false : réseau Docker IPv6 uniquement, à recréer.
- DEFAULT_FORWARD_POLICY différent de "ACCEPT" : Docker ne peut plus router.
EOF
