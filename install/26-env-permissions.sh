# shellcheck shell=sh
# =============================================================================
# 26-env-permissions.sh - protection du fichier .env
# =============================================================================

# Passe .env en 600.
secure_env() {
    section "Fichier .env"

    if [ ! -f "$SERVER_DIR/.env" ]; then
        log "Aucun fichier .env à protéger."
        return 0
    fi

    chmod 600 "$SERVER_DIR/.env"
    log "Permissions de $SERVER_DIR/.env : 600."
}
