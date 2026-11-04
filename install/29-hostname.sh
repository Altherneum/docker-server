# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 29-hostname.sh - nom d'hôte de la machine et prompt du shell
#
# Le nom d'hôte et l'invite utilisent DOMAIN, calculé depuis DOMAIN_NAME et
# TLD dans .env. Exemples : admin@altherneum.fr, root@localhost.
# =============================================================================

# Vrai si la valeur est un nom d'hôte valide (localhost, altherneum.fr...).
is_valid_domain() {
    domain=$1

    case "$domain" in
        ''|.*|*.|*..*|*[!a-z0-9.-]*) return 1 ;;
    esac

    # Le nom d'hôte Linux (UTS) est limité à 64 octets.
    if [ "${#domain}" -gt 64 ]; then
        return 1
    fi

    old_ifs=$IFS
    IFS=.
    # shellcheck disable=SC2086 # découpage volontaire sur les points
    for label in $domain; do
        if [ -z "$label" ] || [ "${#label}" -gt 63 ]; then
            IFS=$old_ifs
            return 1
        fi

        case "$label" in
            -*|*-)
                IFS=$old_ifs
                return 1
                ;;
        esac
    done
    IFS=$old_ifs

    return 0
}

# Valide DOMAIN et arrête l'installation s'il est inutilisable.
validate_domain() {
    if [ -n "$TLD" ] && [ "$TLD" = "${TLD#.}" ]; then
        err "TLD invalide : '$TLD' (point initial attendu, ex: .fr, ou vide)."
        exit 1
    fi

    # Les noms d'hôte Linux sont insensibles à la casse.
    DOMAIN=$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')

    if ! is_valid_domain "$DOMAIN"; then
        err "Nom de domaine invalide : '$DOMAIN' (DOMAIN_NAME + TLD dans .env)."
        exit 1
    fi
}

# Écrit /etc/hostname et applique le nom d'hôte immédiatement.
apply_hostname() {
    current_hostname=$(hostname 2>/dev/null || true)
    current_file=$(cat /etc/hostname 2>/dev/null || true)

    if [ "$current_hostname" = "$DOMAIN" ] && [ "$current_file" = "$DOMAIN" ]; then
        log "Nom d'hôte déjà défini : $DOMAIN."
        return 0
    fi

    backup_file /etc/hostname

    # systemd met à jour /etc/hostname et le nom courant.
    if have_systemd && command_exists hostnamectl; then
        hostnamectl set-hostname "$DOMAIN" \
            || warn "hostnamectl n'a pas pu changer le nom d'hôte."
    fi

    # Fallback pour les systèmes sans systemd.
    if [ "$(cat /etc/hostname 2>/dev/null || true)" != "$DOMAIN" ]; then
        printf '%s\n' "$DOMAIN" > /etc/hostname
    fi

    if [ "$(hostname 2>/dev/null || true)" != "$DOMAIN" ]; then
        hostname "$DOMAIN" 2>/dev/null \
            || warn "Impossible d'appliquer le nom d'hôte immédiatement."
    fi

    log "Nom d'hôte défini : $DOMAIN."
}

# Vrai si le domaine est déjà présent comme nom dans /etc/hosts.
domain_in_hosts() {
    hosts=$1

    awk -v host="$DOMAIN" '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == host) {
                    found = 1
                }
            }
        }
        END { exit !found }
    ' "$hosts"
}

# Associe DOMAIN à 127.0.1.1 dans /etc/hosts (résolution de sudo).
update_etc_hosts() {
    hosts=/etc/hosts

    if [ ! -f "$hosts" ]; then
        printf '127.0.1.1\t%s\n' "$DOMAIN" > "$hosts"
        return 0
    fi

    if domain_in_hosts "$hosts"; then
        return 0
    fi

    backup_file /etc/hosts

    if grep -q '^[[:space:]]*127\.0\.1\.1[[:space:]]' "$hosts"; then
        tmp=$(mktemp)
        awk -v host="$DOMAIN" '
            /^[[:space:]]*127\.0\.1\.1[[:space:]]/ && !done {
                sub(/^[[:space:]]*127\.0\.1\.1[[:space:]]+[^[:space:]]+/, "127.0.1.1\t" host)
                done = 1
            }
            { print }
        ' "$hosts" > "$tmp"
        cat "$tmp" > "$hosts"
        rm -f "$tmp"
        log "/etc/hosts : 127.0.1.1 -> $DOMAIN."
        return 0
    fi

    printf '127.0.1.1\t%s\n' "$DOMAIN" >> "$hosts"
    log "/etc/hosts : ajout de 127.0.1.1 -> $DOMAIN."
}

# Écrit le prompt utilisateur@DOMAIN dans /etc/profile.d.
write_prompt() {
    prompt_file=/etc/profile.d/00-docker-server-prompt.sh

    write_file "$prompt_file" 644 <<'EOF'
# shellcheck shell=sh
# Généré par install.sh - prompt utilisateur@domaine.

case $- in
    *i*) ;;
    *) return 0 ;;
esac

DOCKER_SERVER_PROMPT_DOMAIN='@@DOMAIN@@'

docker_server_set_prompt() {
    if [ "$(id -u)" -eq 0 ]; then
        PS1='\[\033[01;31m\]\u@'"$DOCKER_SERVER_PROMPT_DOMAIN"'\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# '
    else
        PS1='\[\033[01;32m\]\u@'"$DOCKER_SERVER_PROMPT_DOMAIN"'\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
    fi
}

if [ -n "${BASH_VERSION:-}" ]; then
    docker_server_set_prompt
    # Réapplique le prompt avant chaque commande : ~/.bashrc peut le redéfinir.
    PROMPT_COMMAND="docker_server_set_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
else
    # ash/dash n'utilisent pas PROMPT_COMMAND.
    PS1='\u@'"$DOCKER_SERVER_PROMPT_DOMAIN"':\w\$ '
fi
EOF

    # Domaine validé : les caractères spéciaux de sed sont impossibles.
    sed -i "s|@@DOMAIN@@|$DOMAIN|g" "$prompt_file"
}

# Applique le nom d'hôte depuis .env.
configure_hostname() {
    section "Nom d'hôte"

    apply_hostname
    update_etc_hosts
}

# Installe le prompt qui affiche utilisateur@DOMAIN.
configure_prompt() {
    section "Prompt du shell"

    backup_file /etc/profile.d/00-docker-server-prompt.sh
    write_prompt

    log "Prompt installé : /etc/profile.d/00-docker-server-prompt.sh ($ADMIN_USER@$DOMAIN)."
}
