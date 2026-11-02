# shellcheck shell=sh
# =============================================================================
# 07-repo.sh - récupération du dépôt docker-server
# =============================================================================

# Rend le dépôt au propriétaire d'origine pour éviter les problèmes Git.
chown_repo() {
    if [ -z "${SUDO_USER:-}" ]; then
        return 0
    fi

    if [ "$SUDO_USER" = "root" ]; then
        return 0
    fi

    chown -R "$SUDO_USER" "$REPO_DIR" 2>/dev/null || true
}

# Le dépôt peut appartenir à l'utilisateur qui a lancé sudo : autoriser
# explicitement ce chemin pour Git, sinon `pull` échoue en « dubious ownership ».
git_pull() {
    git -C "$REPO_DIR" -c safe.directory="$REPO_DIR" pull --ff-only
}

# Vrai si le dossier existe et contient au moins un fichier.
dir_is_nonempty() {
    [ -d "$1" ] || return 1
    [ -n "$(ls -A "$1" 2>/dev/null)" ]
}

# Dépôt déjà installé : le mettre à jour sans écraser les modifications locales.
clone_existing_repo() {
    log "Dépôt déjà présent dans $REPO_DIR"
    git_pull || warn "git pull impossible (dépôt local modifié ?)."
    cd "$SERVER_DIR"
    chown_repo
}

# Utilise le clone courant, met à jour /opt, ou clone le dépôt.
clone_repo() {
    if [ "$USE_SCRIPT_DIR" = "1" ]; then
        log "Utilisation du dépôt existant : $SERVER_DIR"
        if [ -d "$REPO_DIR/.git" ]; then
            git_pull || warn "git pull impossible (dépôt local modifié ?)."
        fi
        cd "$SERVER_DIR"
        chown_repo
        return 0
    fi

    if [ -d "$REPO_DIR/.git" ]; then
        clone_existing_repo
        return 0
    fi

    if dir_is_nonempty "$REPO_DIR"; then
        err "$REPO_DIR existe mais n'est pas un dépôt Git. Déplacez-le ou supprimez-le."
        exit 1
    fi

    log "Clonage du dépôt dans $REPO_DIR..."
    mkdir -p "$REPO_DIR"
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$SERVER_DIR"
    chown_repo
}
