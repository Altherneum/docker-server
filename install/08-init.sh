# shellcheck shell=sh
# =============================================================================
# 08-init.sh - génération de .env et des fichiers locaux
# =============================================================================

# make init est idempotent : il ne remplace jamais les secrets existants.
run_init() {
    log "Initialisation (.env, secrets, htpasswd, réseaux)..."
    make init
    chown_repo
}
