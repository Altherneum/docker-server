# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 00-config.sh - réglages globaux et lecture de .env
#
# Ce fichier ne modifie rien : il prépare les variables et les fonctions
# communes. Les valeurs de .env sont lues par load_security_config(), appelée
# après make init.
# =============================================================================

# Dépôt cloné quand install.sh n'est pas lancé depuis un clone existant.
REPO_URL="https://github.com/lx78WyY0J5/docker-server.git"
REPO_DIR="/opt/docker-server"
SERVER_DIR="${REPO_DIR}"
USE_SCRIPT_DIR=0
HARDEN_PUBKEY_FILE=""

# Chemins système.
SSHD_CONFIG=/etc/ssh/sshd_config
SSHD_DROPIN=/etc/ssh/sshd_config.d/00-docker-server-hardening.conf
# Drop-in de port écrit par une ancienne version du script. Il est supprimé
# pour revenir au mode classique où ssh.service applique sshd_config.
SSH_SOCKET_DROPIN=/etc/systemd/system/ssh.socket.d/00-docker-server-port.conf

# Valeurs de sécurité, remplies par load_security_config().
ADMIN_USER=""
ADMIN_PASSWORD=""
SSH_PORT=""
MINECRAFT_PORT=""
EXTRA_TCP=""
EXTRA_UDP=""
DISCORD_WEBHOOK_SSH=""
DISCORD_WEBHOOK_SESSION=""
DOMAIN_NAME=""
TLD=""
DOMAIN=""
BACKUP_DIR=""

# Variables remplies pendant l'exécution.
OS_ID=""
OS_FAMILY=""
PKG_UPDATED=0
SSHD_BACKUP=""
TCP_PORTS=""
UDP_PORTS=""
ADMIN_INITIAL_PASSWORD=""

# Messages communs.
log() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERR]\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

# Lit une valeur dans le .env du dépôt. Retourne une chaîne vide si absente.
read_env() {
    key=$1
    sed -n "s/^${key}=//p" "$SERVER_DIR/.env" 2>/dev/null | tr -d '\r' | tail -n1
}

# Charge les réglages de sécurité depuis .env, avec des valeurs par défaut.
load_security_config() {
    # Compte administrateur.
    ADMIN_USER=$(read_env HARDEN_ADMIN_USER)
    ADMIN_PASSWORD=$(read_env HARDEN_ADMIN_PASSWORD)

    # Ports réseaux ouverts sur l’hôte.
    SSH_PORT=$(read_env HARDEN_SSH_PORT)
    MINECRAFT_PORT=$(read_env MINECRAFT_PORT)
    EXTRA_TCP=$(read_env HARDEN_EXTRA_TCP)
    EXTRA_UDP=$(read_env HARDEN_EXTRA_UDP)

    # Notifications Discord.
    DISCORD_WEBHOOK_SSH=$(read_env DISCORD_WEBHOOK_SSH)
    DISCORD_WEBHOOK_SESSION=$(read_env DISCORD_WEBHOOK_SESSION)

    # Nom d'hôte de la machine et prompt du shell.
    # DOMAIN n'est pas lu directement : .env contient ${DOMAIN_NAME}${TLD}.
    DOMAIN_NAME=$(read_env DOMAIN_NAME)
    TLD=$(read_env TLD)
    DOMAIN_NAME=${DOMAIN_NAME:-localhost}
    DOMAIN="${DOMAIN_NAME}${TLD}"

    # Valeurs par défaut si .env est incomplet.
    ADMIN_USER=${ADMIN_USER:-admin}
    SSH_PORT=${SSH_PORT:-22}
    MINECRAFT_PORT=${MINECRAFT_PORT:-25565}

    # Un dossier de sauvegarde différent à chaque exécution.
    BACKUP_DIR="/var/backups/harden/$(date '+%Y%m%d-%H%M%S')"
}
