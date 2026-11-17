# shellcheck shell=sh
# =============================================================================
# mail-lib.sh - fonctions communes aux scripts mailcow.
#
# Ce fichier est sourcé par les scripts mail-*.sh.
# Il ne doit pas être exécuté directement.
# =============================================================================

mail_die() {
    printf 'Erreur : %s\n' "$*" >&2
    exit 1
}

mail_warn() {
    printf 'Attention : %s\n' "$*" >&2
}

mail_info() {
    printf '→ %s\n' "$*"
}

# Rend un fichier/dossier à l'utilisateur qui a lancé sudo (si applicable).
mail_chown_user() {
    [ -n "${SUDO_USER:-}" ] || return 0
    [ "$SUDO_USER" != "root" ] || return 0
    chown -R "$SUDO_USER": "$1" 2>/dev/null || true
}

# Lit une valeur brute dans le .env (sans expansion des ${...}).
env_get() {
    sed -n "s/^$1=//p" "$ENV_FILE" 2>/dev/null | tail -n1 | tr -d '\r'
}

# Écrit une valeur dans le .env, en remplaçant la ligne existante.
env_set() {
    key=$1
    value=$2
    escaped=$(printf '%s' "$value" | sed 's/[&|\\]/\\&/g')

    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${escaped}|" "$ENV_FILE"
        return 0
    fi

    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
}

# Lit une valeur dans mailcow.conf.
mailcow_get() {
    sed -n "s/^$1=//p" "$MAILCOW_CONF" 2>/dev/null | tail -n1 | tr -d '\r'
}

# Écrit une valeur dans mailcow.conf, en remplaçant la ligne existante.
mailcow_set() {
    key=$1
    value=$2
    escaped=$(printf '%s' "$value" | sed 's/[&|\\]/\\&/g')

    if grep -q "^${key}=" "$MAILCOW_CONF"; then
        sed -i "s|^${key}=.*|${key}=${escaped}|" "$MAILCOW_CONF"
        return 0
    fi

    printf '\n%s=%s\n' "$key" "$value" >> "$MAILCOW_CONF"
}

# Lance docker compose dans le dossier mailcow.
mailcow_compose() {
    ( cd "$MAILCOW_DIR" && docker compose "$@" )
}

# Vrai si le service mailcow demandé tourne.
mailcow_service_running() {
    service=$1
    id=$(mailcow_compose ps -q "$service" 2>/dev/null | head -n1)
    [ -n "$id" ] || return 1
    [ "$(docker inspect -f '{{.State.Running}}' "$id" 2>/dev/null || true)" = "true" ]
}

# Charge .env et les valeurs dérivées. $1 = racine du dépôt.
mail_load_env() {
    MAIL_ROOT=$1
    ENV_FILE=${ENV_FILE:-$MAIL_ROOT/.env}
    [ -f "$ENV_FILE" ] || mail_die "$ENV_FILE introuvable. Lancez make init."

    # docker compose résout les ${DOMAIN_NAME}${TLD} du .env. Si Docker n'est
    # pas disponible, les fallbacks ci-dessous gardent le script utilisable.
    ENV_DUMP=$( cd "$MAIL_ROOT" && docker compose --env-file "$ENV_FILE" config --environment 2>/dev/null || true )
    env_resolved() {
        printf '%s\n' "$ENV_DUMP" | sed -n "s/^$1=//p" | tail -n1
    }

    DOMAIN_NAME=$(env_resolved DOMAIN_NAME)
    [ -n "$DOMAIN_NAME" ] || DOMAIN_NAME=$(env_get DOMAIN_NAME)
    TLD=$(env_resolved TLD)
    if [ -z "$TLD" ]; then
        TLD=$(env_get TLD)
    fi
    DOMAIN=$(env_resolved DOMAIN)
    # Fallback quand docker compose n'est pas disponible : .env contient la
    # valeur littérale ${DOMAIN_NAME}${TLD}, qu'il faut reconstruire.
    case "$DOMAIN" in
        *'${'*) DOMAIN="" ;;
    esac
    if [ -z "$DOMAIN" ]; then
        DOMAIN="${DOMAIN_NAME}${TLD}"
    fi

    PROXY_NETWORK=$(env_resolved PROXY_NETWORK)
    if [ -z "$PROXY_NETWORK" ]; then
        PROXY_NETWORK=$(env_get PROXY_NETWORK)
        case "$PROXY_NETWORK" in
            *'${'*) PROXY_NETWORK="${DOMAIN_NAME}_proxy" ;;
        esac
    fi

    MAILCOW_DIR=${MAILCOW_DIR:-$(env_resolved MAILCOW_DIR)}
    [ -n "$MAILCOW_DIR" ] || MAILCOW_DIR=$(env_get MAILCOW_DIR)
    [ -n "$MAILCOW_DIR" ] || MAILCOW_DIR=/opt/mailcow-dockerized

    MAILCOW_CONF="$MAILCOW_DIR/mailcow.conf"

    # Backups hors du dépôt si demandé (utile pour les tests).
    BACKUP_DIR=${BACKUP_DIR:-$MAIL_ROOT/backups}
}

# Vérifie qu'un domaine est plausible (pas de validation DNS).
mail_domain_valid() {
    case "$1" in
        ''|*[!A-Za-z0-9.-]*|.*|*.) return 1 ;;
    esac
    case "$1" in
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}

# Vrai si le fichier contient au moins une ligne KEY=VALUE (hors commentaires).
mail_acme_secrets_present() {
    file=$1
    [ -s "$file" ] || return 1
    grep -Eq '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' "$file"
}

# Résout un chemin de clé DKIM (absolu, ~/ ou relatif au dépôt).
mail_resolve_key_path() {
    case "$1" in
        "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$MAIL_ROOT" "$1" ;;
    esac
}

# Vrai si une clé DKIM utilisable existe déjà (fichier, inline ou Redis).
mail_dkim_key_available() {
    dkim_key_file=$(env_get MAIL_DKIM_PRIVATE_KEY_FILE)
    if [ -n "$dkim_key_file" ]; then
        dkim_key_path=$(mail_resolve_key_path "$dkim_key_file")
        [ -r "$dkim_key_path" ] && return 0
    fi
    [ -n "$(env_get MAIL_DKIM_PRIVATE_KEY)" ] && return 0

    mailcow_service_running redis-mailcow 2>/dev/null || return 1
    dkim_redispass=$(mailcow_get REDISPASS)
    [ -n "$dkim_redispass" ] || return 1
    REDISPASS=$dkim_redispass
    dkim_selector=$(mail_redis_cmd HGET DKIM_SELECTORS "$DOMAIN" 2>/dev/null | tr -d '\r' || true)
    [ -n "$dkim_selector" ] || return 1
    dkim_priv=$(mail_redis_cmd HGET DKIM_PRIV_KEYS "$dkim_selector.$DOMAIN" 2>/dev/null | tr -d '\r' || true)
    [ -n "$dkim_priv" ]
}

# Nom du réseau Docker de mailcow.
mailcow_network_name() {
    project=$(mailcow_get COMPOSE_PROJECT_NAME)
    [ -n "$project" ] || project=mailcowdockerized
    printf '%s_mailcow-network\n' "$project"
}

# Sous-réseau IPv4 /24 actuel du réseau mailcow, ou vide.
mailcow_current_subnet() {
    network=$(mailcow_network_name)
    docker network inspect "$network" --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null \
        | tr ' ' '\n' | grep '/24$' | head -n1
}

# Teste si un /24 est libre en créant un réseau jetable.
mail_subnet_free() {
    cidr=$1
    mail_probe_seq=$((${mail_probe_seq:-0} + 1))
    probe="mailcow-probe-$$-$mail_probe_seq"
    if docker network create --driver bridge --subnet "$cidr" "$probe" >/dev/null 2>&1; then
        docker network rm "$probe" >/dev/null 2>&1 || true
        return 0
    fi
    return 1
}

# Normalise 172.30.1 ou 172.30.1.0/24 en 172.30.1. Refuse autre chose que /24.
mail_normalize_ipv4() {
    case "$1" in
        */*) cidr=$1 ;;
        *) cidr="$1.0/24" ;;
    esac

    case "$cidr" in
        */24) base=${cidr%/24} ;;
        *) return 1 ;;
    esac
    base=${base%.0}

    case "$base" in
        *[!0-9.]*|.*|*.) return 1 ;;
    esac

    old_ifs=$IFS
    IFS=.
    # shellcheck disable=SC2086
    set -- $base
    IFS=$old_ifs
    [ $# -eq 3 ] || return 1
    for octet in "$@"; do
        [ -n "$octet" ] || return 1
        [ "$octet" -le 255 ] || return 1
    done

    printf '%s\n' "$base"
}

# Cherche un /24 libre dans 172.30.0.0/16 puis 172.31.0.0/16.
mail_pick_ipv4() {
    third=30
    while [ "$third" -le 31 ]; do
        last=1
        while [ "$last" -le 254 ]; do
            base="172.${third}.${last}"
            if mail_subnet_free "${base}.0/24"; then
                printf '%s\n' "$base"
                return 0
            fi
            last=$((last + 1))
        done
        third=$((third + 1))
    done
    return 1
}

# Exécute redis-cli dans le conteneur mailcow.
mail_redis_cmd() {
    mailcow_compose exec -T -e REDISCLI_AUTH="$REDISPASS" redis-mailcow \
        redis-cli --no-auth-warning "$@"
}

# Écrit une valeur (lue sur stdin) dans un hash Redis mailcow.
mail_redis_set() {
    hash=$1
    field=$2
    mailcow_compose exec -T -e REDISCLI_AUTH="$REDISPASS" redis-mailcow \
        redis-cli --no-auth-warning -x HSET "$hash" "$field" >/dev/null
}

# Vrai si l'API mailcow peut être appelée depuis php-fpm.
mail_api_available() {
    api_key=$(env_get MAILCOW_API_KEY)
    [ -n "$api_key" ] || api_key=$(mailcow_get API_KEY)
    [ -n "$api_key" ] || return 1
    mailcow_service_running php-fpm-mailcow || return 1
    return 0
}

# POST /api/v1/<path> depuis php-fpm, donc avec une IP source du réseau mailcow.
mail_api_post() {
    api_path=$1
    api_json=$2
    api_key=$(env_get MAILCOW_API_KEY)
    [ -n "$api_key" ] || api_key=$(mailcow_get API_KEY)
    api_host=$(mailcow_get MAILCOW_HOSTNAME)
    [ -n "$api_host" ] || api_host="mail.$DOMAIN"
    api_port=$(mailcow_get HTTPS_PORT)
    [ -n "$api_port" ] || api_port=443

    printf '%s' "$api_json" | mailcow_compose exec -T php-fpm-mailcow php -r '
        $body = stream_get_contents(STDIN);
        $host = $argv[1];
        $key = $argv[2];
        $path = $argv[3];
        $port = $argv[4];
        $context = stream_context_create([
            "http" => [
                "method" => "POST",
                "header" => "Host: " . $host . "\r\n" .
                            "X-API-Key: " . $key . "\r\n" .
                            "Content-Type: application/json\r\n",
                "content" => $body,
                "ignore_errors" => true,
                "timeout" => 20,
            ],
            "ssl" => [
                "verify_peer" => false,
                "verify_peer_name" => false,
            ],
        ]);
        $result = @file_get_contents("https://nginx:" . $port . "/api/v1/" . $path, false, $context);
        if ($result === false) {
            fwrite(STDERR, "api_request_failed\n");
            exit(1);
        }
        echo $result;
    ' -- "$api_host" "$api_key" "$api_path" "$api_port"
}

# GET /api/v1/<path> depuis php-fpm.
mail_api_get() {
    api_path=$1
    api_key=$(env_get MAILCOW_API_KEY)
    [ -n "$api_key" ] || api_key=$(mailcow_get API_KEY)
    api_host=$(mailcow_get MAILCOW_HOSTNAME)
    [ -n "$api_host" ] || api_host="mail.$DOMAIN"
    api_port=$(mailcow_get HTTPS_PORT)
    [ -n "$api_port" ] || api_port=443

    mailcow_compose exec -T php-fpm-mailcow php -r '
        $host = $argv[1];
        $key = $argv[2];
        $path = $argv[3];
        $port = $argv[4];
        $context = stream_context_create([
            "http" => [
                "method" => "GET",
                "header" => "Host: " . $host . "\r\n" .
                            "X-API-Key: " . $key . "\r\n",
                "ignore_errors" => true,
                "timeout" => 20,
            ],
            "ssl" => [
                "verify_peer" => false,
                "verify_peer_name" => false,
            ],
        ]);
        $result = @file_get_contents("https://nginx:" . $port . "/api/v1/" . $path, false, $context);
        if ($result === false) {
            fwrite(STDERR, "api_request_failed\n");
            exit(1);
        }
        echo $result;
    ' -- "$api_host" "$api_key" "$api_path" "$api_port"
}

# Ajoute un domaine via l'API, sans générer de clé DKIM (key_size=0).
mail_api_add_domain() {
    domain=$1

    if ! mail_api_available; then
        return 2
    fi

    json=$(printf '{"domain":"%s","description":"%s","aliases":400,"mailboxes":10,"defquota":3072,"maxquota":10240,"quota":10240,"active":1,"gal":1,"backupmx":0,"relay_all_recipients":0,"relay_unknown_only":0,"restart_sogo":0,"key_size":0,"dkim_selector":""}' "$domain" "$domain")

    if ! out=$(mail_api_post add/domain "$json" 2>&1); then
        return 1
    fi

    case "$out" in
        *'"type":"success"'*|*'"type": "success"'*)
            mail_info "domaine $domain créé via l'API mailcow"
            ;;
        *domain_exists*)
            mail_info "domaine $domain déjà présent dans mailcow"
            ;;
        *)
            mail_warn "API mailcow pour $domain : $out"
            return 1
            ;;
    esac
}
