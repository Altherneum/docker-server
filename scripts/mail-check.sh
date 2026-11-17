#!/bin/sh
# =============================================================================
# mail-check.sh - vérifie que mailcow peut démarrer derrière Traefik.
#
# Contrôle : Docker, réseau proxy, sous-réseau mailcow, ports mail, override,
# merge docker compose, DNS de mail.<domaine>, flag DKIM.
#
# Usage : ./scripts/mail-check.sh
# =============================================================================
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MAIL_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/mail-lib.sh"
mail_load_env "$MAIL_ROOT"

fails=0
warns=0

ok() {
    printf '  [OK]   %s\n' "$*"
}

warn() {
    warns=$((warns + 1))
    printf '  [WARN] %s\n' "$*"
}

fail() {
    fails=$((fails + 1))
    printf '  [FAIL] %s\n' "$*"
}

printf '\n=== Vérification mailcow ===\n\n'

if mail_domain_valid "$DOMAIN"; then
    ok "domaine : $DOMAIN"
else
    fail "DOMAIN invalide : $DOMAIN (renseignez DOMAIN_NAME et TLD dans .env)"
fi

# --- Docker et mailcow -----------------------------------------------------
if docker info >/dev/null 2>&1; then
    ok "Docker répond"
else
    fail "Docker ne répond pas"
fi

if docker compose version >/dev/null 2>&1; then
    ok "docker compose disponible"
    compose_version=$(docker compose version --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    [ -n "$compose_version" ] || compose_version=inconnue
    compose_major=${compose_version%%.*}
    compose_rest=${compose_version#*.}
    compose_minor=${compose_rest%%.*}
    case "$compose_major" in ''|*[!0-9]*) compose_major=0 ;; esac
    case "$compose_minor" in ''|*[!0-9]*) compose_minor=0 ;; esac
    if [ "$compose_major" -gt 2 ] || { [ "$compose_major" -eq 2 ] && [ "$compose_minor" -ge 24 ]; }; then
        ok "docker compose $compose_version supporte !reset"
    else
        fail "docker compose $compose_version est trop ancien pour !reset (minimum 2.24)"
    fi
else
    fail "docker compose introuvable"
fi

if [ -d "$MAILCOW_DIR" ]; then
    ok "MAILCOW_DIR existe : $MAILCOW_DIR"
else
    fail "MAILCOW_DIR introuvable : $MAILCOW_DIR (mailcow n'est pas installé)"
fi

if [ -f "$MAILCOW_CONF" ]; then
    ok "mailcow.conf présent"
else
    fail "mailcow.conf manquant dans $MAILCOW_DIR"
fi

if [ -f "$MAILCOW_DIR/docker-compose.override.yml" ]; then
    ok "docker-compose.override.yml présent"
else
    fail "override absent : lancez sudo make mail-integrate"
fi

if [ -f "$MAILCOW_DIR/.env" ]; then
    if [ -L "$MAILCOW_DIR/.env" ]; then
        ok ".env est un lien vers mailcow.conf"
    else
        warn ".env n'est pas un lien symbolique vers mailcow.conf (ancienne installation ?)"
    fi
else
    warn "$MAILCOW_DIR/.env absent (mailcow récent attend un lien vers mailcow.conf)"
fi

# --- Réseau proxy et sous-réseau mailcow -----------------------------------
if docker network inspect "$PROXY_NETWORK" >/dev/null 2>&1; then
    ok "réseau proxy présent : $PROXY_NETWORK"
else
    fail "réseau proxy absent : $PROXY_NETWORK (sudo make ensure-networks)"
fi

if docker info >/dev/null 2>&1; then
    current_subnet=$(mailcow_current_subnet)
    if [ -n "$current_subnet" ]; then
        ok "réseau mailcow existant : $current_subnet"
    else
        configured=$(env_get MAILCOW_IPV4_NETWORK)
        [ -n "$configured" ] || configured=$(mailcow_get IPV4_NETWORK)
        [ -n "$configured" ] || configured=172.22.1
        if base=$(mail_normalize_ipv4 "$configured" 2>/dev/null); then
            if mail_subnet_free "${base}.0/24"; then
                ok "sous-réseau mailcow libre : ${base}.0/24"
            else
                fail "${base}.0/24 est déjà utilisé par Docker. Lancez sudo make mail-integrate ou changez MAILCOW_IPV4_NETWORK."
            fi
        else
            fail "MAILCOW_IPV4_NETWORK invalide : $configured"
        fi
    fi
else
    warn "sous-réseau mailcow non vérifié : Docker ne répond pas"
fi

# --- Ports mail ------------------------------------------------------------
if command -v ss >/dev/null 2>&1; then
    for port in 25 110 143 465 587 993 995 4190; do
        if ss -H -lnt 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" { found=1 } END { exit !found }'; then
            if docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":${port}->"; then
                ok "port $port utilisé par un conteneur (mailcow ?)"
            else
                fail "port $port déjà utilisé sur l'hôte"
            fi
        else
            ok "port $port libre"
        fi
    done
else
    warn "ss introuvable : ports mail non vérifiés"
fi

# --- Règles UFW (indicatif : Docker publie ses ports avant UFW) -------------
if command -v ufw >/dev/null 2>&1; then
    ufw_status=$(ufw status 2>/dev/null || true)
    case "$ufw_status" in
        *"Status: active"*)
            missing_ufw=""
            for port in 80 443 25 110 143 465 587 993 995 4190; do
                if printf '%s\n' "$ufw_status" | grep -qE "(^|[[:space:]])${port}/tcp([[:space:]]|$).*ALLOW"; then
                    :
                else
                    missing_ufw="$missing_ufw $port"
                fi
            done
            if [ -z "$missing_ufw" ]; then
                ok "règles UFW présentes pour les ports web/mail"
            else
                warn "règles UFW manquantes :$missing_ufw (Docker publie quand même ; vérifiez le pare-feu de l'hébergeur)"
            fi
            ;;
        *)
            warn "UFW inactif ou non lisible : règles pare-feu non vérifiées"
            ;;
    esac
else
    warn "ufw introuvable : règles pare-feu non vérifiées"
fi

# --- Configuration mailcow.conf -------------------------------------------
if [ -f "$MAILCOW_CONF" ]; then
    skip_acme=$(mailcow_get SKIP_LETS_ENCRYPT | tr '[:upper:]' '[:lower:]')
    if [ "$skip_acme" = "y" ]; then
        ssl_cert="$MAILCOW_DIR/data/assets/ssl/cert.pem"
        if [ -f "$ssl_cert" ] && command -v openssl >/dev/null 2>&1; then
            case "$(openssl x509 -in "$ssl_cert" -noout -issuer 2>/dev/null || true)" in
                *"Let's Encrypt"*) ok "certificat SMTP/IMAP public (Let's Encrypt, copié de Traefik)" ;;
                *) ok "certificat SMTP/IMAP interne (auto-signé)" ;;
            esac
        else
            ok "certificat SMTP/IMAP géré hors mailcow (Traefik)"
        fi
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet mail-cert-sync.timer 2>/dev/null; then
                ok "timer de synchro du certificat actif"
            else
                warn "timer de synchro du certificat absent (sudo make mail-cert-timer)"
            fi
        fi
    else
        fail "SKIP_LETS_ENCRYPT=$skip_acme : mailcow tenterait son ACME sur 80/443, déjà pris par Traefik (lancez make mail-integrate)"
    fi

    # Clé API et IP autorisées (nécessaires à mail-dkim et mail-mailboxes).
    env_api_key=$(env_get MAILCOW_API_KEY)
    conf_api_key=$(mailcow_get API_KEY)
    case "$conf_api_key" in
        ''|invalid) conf_api_key="" ;;
    esac
    if [ -n "$conf_api_key" ]; then
        ok "clé API mailcow présente dans mailcow.conf"
    else
        fail "API_KEY absent de mailcow.conf (relancez sudo make mail-integrate)"
    fi
    if [ -n "$env_api_key" ] && [ -n "$conf_api_key" ] && [ "$env_api_key" != "$conf_api_key" ]; then
        fail "MAILCOW_API_KEY (.env) diffère de API_KEY (mailcow.conf) : relancez mail-integrate"
    elif [ -z "$env_api_key" ] && [ -n "$conf_api_key" ]; then
        warn "MAILCOW_API_KEY vide dans .env : mail-integrate le recopiera"
    fi

    check_base=$(mailcow_current_subnet 2>/dev/null || true)
    if [ -n "$check_base" ]; then
        check_base=$(mail_normalize_ipv4 "$check_base" 2>/dev/null || true)
    fi
    if [ -z "$check_base" ]; then
        check_base=$(env_get MAILCOW_IPV4_NETWORK)
        [ -n "$check_base" ] || check_base=$(mailcow_get IPV4_NETWORK)
        if [ -n "$check_base" ]; then
            check_base=$(mail_normalize_ipv4 "$check_base" 2>/dev/null || true)
        fi
    fi
    api_allow=$(mailcow_get API_ALLOW_FROM | tr -d '[:space:]')
    if [ -n "$check_base" ]; then
        case ",$api_allow," in
            *",${check_base}.0/24,"*) ok "API_ALLOW_FROM inclut ${check_base}.0/24" ;;
            *) fail "API_ALLOW_FROM n'inclut pas ${check_base}.0/24 (relancez mail-integrate)" ;;
        esac
    fi

    https_port=$(mailcow_get HTTPS_PORT)
    [ -n "$https_port" ] || https_port=443
    if grep -Fq "server.port: \"$https_port\"" "$MAILCOW_DIR/docker-compose.override.yml" 2>/dev/null; then
        ok "override pointe vers le port HTTPS interne $https_port"
    else
        fail "override ne pointe pas vers HTTPS_PORT=$https_port (relancez make mail-integrate)"
    fi

    if grep -q 'traefik.enable: "true"' "$MAILCOW_DIR/docker-compose.override.yml" 2>/dev/null; then
        ok "labels Traefik présents"
    else
        fail "labels Traefik absents de l'override"
    fi

    if grep -q 'ports: !reset \[\]' "$MAILCOW_DIR/docker-compose.override.yml" 2>/dev/null; then
        ok "ports 80/443 retirés de nginx-mailcow"
    else
        fail "ports 80/443 non retirés de nginx-mailcow"
    fi

    hostname=$(mailcow_get MAILCOW_HOSTNAME)
    [ -n "$hostname" ] || hostname="mail.$DOMAIN"
    if grep -Fq "Host(\`$hostname\`)" "$MAILCOW_DIR/docker-compose.override.yml" 2>/dev/null; then
        ok "routeur web : $hostname"
    else
        fail "override ne route pas MAILCOW_HOSTNAME=$hostname (relancez make mail-integrate)"
    fi
    if command -v getent >/dev/null 2>&1; then
        if getent ahostsv4 "$hostname" >/dev/null 2>&1; then
            ok "DNS : $hostname résout"
        else
            warn "DNS : $hostname ne résout pas encore (normal avant configuration DNS)"
        fi
    fi
fi

# --- Merge Compose ---------------------------------------------------------
if [ -d "$MAILCOW_DIR" ] && [ -f "$MAILCOW_DIR/docker-compose.yml" ] && [ -f "$MAILCOW_DIR/docker-compose.override.yml" ]; then
    if ( cd "$MAILCOW_DIR" && docker compose -f docker-compose.yml -f docker-compose.override.yml config >/dev/null 2>&1 ); then
        ok "docker compose config : merge valide"
    else
        fail "docker compose config échoue (voir sudo make mail-integrate)"
    fi
fi

# --- Clés DKIM -------------------------------------------------------------
create_keys=$(env_get MAIL_CREATE_KEYS)
create_keys=$(printf '%s' "$create_keys" | tr '[:upper:]' '[:lower:]')
[ -n "$create_keys" ] || create_keys=no
case "$create_keys" in
    yes)
        ok "MAIL_CREATE_KEYS=yes : make mail-dkim générera une nouvelle clé"
        ;;
    no)
        key_file=$(env_get MAIL_DKIM_PRIVATE_KEY_FILE)
        inline_key=$(env_get MAIL_DKIM_PRIVATE_KEY)
        if [ -n "$key_file" ]; then
            case "$key_file" in
                "~/"*) key_path="$HOME/${key_file#~/}" ;;
                /*) key_path=$key_file ;;
                *) key_path="$MAIL_ROOT/$key_file" ;;
            esac
            if [ -f "$key_path" ] && [ -r "$key_path" ]; then
                ok "MAIL_CREATE_KEYS=no : clé privée lisible ($key_path)"
            else
                fail "MAIL_DKIM_PRIVATE_KEY_FILE introuvable ou illisible : $key_path"
            fi
        elif [ -n "$inline_key" ]; then
            ok "MAIL_CREATE_KEYS=no : clé privée inline fournie"
        elif mailcow_service_running redis-mailcow 2>/dev/null; then
            ok "MAIL_CREATE_KEYS=no : la clé Redis existante sera conservée"
        else
            warn "MAIL_CREATE_KEYS=no mais aucune clé fournie et Redis n'est pas démarré"
        fi
        ;;
    *)
        fail "MAIL_CREATE_KEYS doit valoir yes ou no (valeur : ${create_keys:-vide})"
        ;;
esac

printf '\n=== Résultat : %s erreur(s), %s avertissement(s) ===\n\n' "$fails" "$warns"

if [ "$fails" -gt 0 ]; then
    printf 'Corrigez les erreurs puis relancez sudo make mail-check.\n'
    exit 1
fi

printf 'Configuration prête. Démarrez avec : sudo make mail-up\n'
printf "%s\n" "Rappel : les ports mail sont publiés par Docker ; vérifiez aussi le pare-feu de l'hébergeur."
