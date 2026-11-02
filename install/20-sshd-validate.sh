# shellcheck shell=sh
# =============================================================================
# 20-sshd-validate.sh - validation de la configuration sshd
# =============================================================================

# Vérifie la syntaxe de la configuration sshd.
validate_sshd_config() {
    mkdir -p /run/sshd
    sshd -t
}

# Retourne la valeur effective d’un réglage sshd.
sshd_effective() {
    key=$1
    sshd -T 2>/dev/null | awk -v key="$key" 'tolower($1)==tolower(key) {print $2; exit}'
}

# Vérifie qu’un réglage sshd a la valeur attendue.
verify_sshd_setting() {
    key=$1
    expected=$2
    actual=$(sshd_effective "$key")

    if [ "$actual" = "$expected" ]; then
        log "SSH $key = $actual."
        return 0
    fi

    err "SSH $key vaut '$actual' au lieu de '$expected' (conflit dans un fichier inclus)."
    return 1
}
