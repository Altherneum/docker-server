# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 11-ports.sh - validation des ports et liste des ports UFW
#
# Ports de base :
#   - HARDEN_SSH_PORT (22 par défaut) ;
#   - 80/tcp et 443/tcp pour Traefik ;
#   - MINECRAFT_PORT/tcp pour Minecraft Java ;
#   - 19132/tcp + udp et 19133/udp pour Minecraft Bedrock.
#
# Les ports supplémentaires viennent de HARDEN_EXTRA_TCP et HARDEN_EXTRA_UDP.
# =============================================================================

# Vrai si la valeur est un port valide (1 à 65535).
valid_port() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac

    if [ "$1" -lt 1 ]; then
        return 1
    fi

    if [ "$1" -gt 65535 ]; then
        return 1
    fi

    return 0
}

# Vérifie un port nommé et arrête le script s’il est invalide.
validate_port() {
    name=$1
    value=$2

    if valid_port "$value"; then
        return 0
    fi

    err "$name invalide : $value"
    exit 1
}

# Vérifie les ports obligatoires du fichier .env.
validate_ports() {
    validate_port HARDEN_SSH_PORT "$SSH_PORT"
    validate_port MINECRAFT_PORT "$MINECRAFT_PORT"
}

# Nettoie une liste de ports : "80, 443 80" devient "80 443".
normalize_ports() {
    ports=$1
    result=""

    # shellcheck disable=SC2086 # découpage volontaire de la liste
    for port in $(printf '%s' "$ports" | tr ',' ' '); do
        if ! valid_port "$port"; then
            continue
        fi

        case " $result " in
            *" $port "*) continue ;;
        esac

        result="$result $port"
    done

    printf '%s' "$result" | sed 's/^ //'
}

# Construit les listes de ports TCP et UDP à ouvrir dans UFW.
build_ports() {
    TCP_PORTS="$SSH_PORT 80 443 19132 $MINECRAFT_PORT $EXTRA_TCP"
    UDP_PORTS="19132 19133 $EXTRA_UDP"

    TCP_PORTS=$(normalize_ports "$TCP_PORTS")
    UDP_PORTS=$(normalize_ports "$UDP_PORTS")
}
