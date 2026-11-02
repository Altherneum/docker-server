# shellcheck shell=sh
# =============================================================================
# 09-files.sh - écriture et sauvegarde de fichiers
# =============================================================================

# Écrit un fichier depuis stdin : write_file CHEMIN MODE <<EOF
write_file() {
    path=$1
    mode=$2
    mkdir -p "$(dirname "$path")"
    cat > "$path"
    chmod "$mode" "$path"
}

# Calcule le chemin aplati d'une sauvegarde.
backup_path() {
    src=$1
    printf '%s/%s\n' "$BACKUP_DIR" "$(printf '%s' "$src" | sed 's|^/||; s|/|__|g')"
}

# Copie un fichier dans le dossier de sauvegarde.
backup_file() {
    src=$1
    if [ ! -e "$src" ]; then
        return 0
    fi
    dest=$(backup_path "$src")
    mkdir -p "$BACKUP_DIR"
    cp -a "$src" "$dest"
}
