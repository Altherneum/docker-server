#!/bin/sh
# Prépare les volumes nommés avant de lancer code-server.
# Un volume Docker neuf est créé root ; code-server tourne avec l'utilisateur
# coder et doit pouvoir écrire ses réglages et ses extensions.
set -eu

# Les extensions par défaut sont listées dans stacks/code-server/extensions.txt
# (copié dans l'image sous /usr/local/share/code-server/extensions.txt).
EXTENSIONS_FILE=/usr/local/share/code-server/extensions.txt
EXTENSIONS_DIR=/home/coder/.local/share/code-server/extensions
SETTINGS_DIR=/home/coder/.local/share/code-server/User
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
# Thème par défaut, surchargeable par CODE_SERVER_THEME dans .env.
DEFAULT_THEME="${CODE_SERVER_THEME:-Default High Contrast}"

sudo mkdir -p "$EXTENSIONS_DIR"
sudo chown -R coder:coder \
    /home/coder/.local/share/code-server \
    /home/coder/workspace

# Applique le thème sombre par défaut sans écraser un choix déjà fait dans
# l'interface. Le thème vient de l'extension intégrée vscode.theme-defaults.
ensure_default_theme() {
    mkdir -p "$SETTINGS_DIR"
    if [ ! -f "$SETTINGS_FILE" ]; then
        cat > "$SETTINGS_FILE" <<EOF
{
    "workbench.colorTheme": "$DEFAULT_THEME"
}
EOF
        echo "→ Thème par défaut appliqué : $DEFAULT_THEME"
        return
    fi
    if grep -q '"workbench.colorTheme"' "$SETTINGS_FILE"; then
        return
    fi
    if ! command -v perl >/dev/null 2>&1; then
        echo "Attention : perl introuvable, thème par défaut non appliqué." >&2
        return
    fi
    DEFAULT_THEME="$DEFAULT_THEME" perl -0777 -i -pe '
        my $theme = $ENV{DEFAULT_THEME};
        if (s/\{\s*\}/{\n    "workbench.colorTheme": "$theme"\n}/) {}
        elsif (s/\{/{\n    "workbench.colorTheme": "$theme",/) {}
    ' "$SETTINGS_FILE"
    echo "→ Thème par défaut appliqué : $DEFAULT_THEME"
}

ensure_default_theme

# Un volume code-server-data existant masque les extensions de l'image :
# on installe uniquement celles qui manquent.
install_missing_extensions() {
    [ -f "$EXTENSIONS_FILE" ] || return 0
    while read -r extension; do
        case "$extension" in
            ""|\#*) continue ;;
        esac
        if ! find "$EXTENSIONS_DIR" -mindepth 1 -maxdepth 1 -type d \
                -iname "${extension}-*" | grep -q .; then
            echo "→ Installation de l'extension $extension"
            code-server --install-extension "$extension" \
                || echo "Attention : installation de $extension impossible." >&2
        fi
    done < "$EXTENSIONS_FILE"
}

install_missing_extensions

# Profil Git global, utilisé par les commits et les outils Git de code-server.
if [ -n "${GIT_USER_NAME:-}" ] && [ -n "${GIT_USER_EMAIL:-}" ]; then
    git config --global user.name "$GIT_USER_NAME"
    git config --global user.email "$GIT_USER_EMAIL"
    echo "→ Profil Git configuré : $GIT_USER_NAME <$GIT_USER_EMAIL>"
elif [ -n "${GIT_USER_NAME:-}" ] || [ -n "${GIT_USER_EMAIL:-}" ]; then
    echo "Attention : GIT_USER_NAME et GIT_USER_EMAIL doivent être renseignés ensemble." >&2
else
    echo "→ Profil Git non configuré : renseignez GIT_USER_NAME et GIT_USER_EMAIL dans .env."
fi

# Clone initial des dépôts GitHub de l'organisation. Le script est idempotent
# et ajoute aussi un remote « forgejo » à chaque dépôt.
if [ "${CODE_SERVER_CLONE_GITHUB_ORG:-true}" = "true" ]; then
    /usr/local/bin/clone-github-org \
        || echo "Attention : clonage GitHub incomplet (voir les messages ci-dessus)." >&2
fi

# L'ENTRYPOINT de l'image officielle contient « --bind-addr 0.0.0.0:8080 ».
# En le remplaçant, on doit réinjecter cette adresse, sinon code-server
# n'écoute que sur 127.0.0.1 et Traefik renvoie 502.
if [ "$#" -eq 0 ]; then
    set -- --bind-addr 0.0.0.0:8080 .
fi

exec /usr/bin/entrypoint.sh "$@"
