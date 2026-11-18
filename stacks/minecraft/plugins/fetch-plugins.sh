#!/bin/sh
# Téléchargement des plugins officiels dans /plugins.
# Les versions sont définies via les variables d'environnement (.env).
set -eu

PAPER_DIR=/plugins/paper
PAPER_CREATIF_DIR=/plugins/paper-creatif
DOWNLOAD_DIR=/plugins/downloads
VELOCITY_DIR=/plugins/velocity

mkdir -p "$PAPER_DIR" "$PAPER_CREATIF_DIR" "$VELOCITY_DIR" "$DOWNLOAD_DIR"

# Retire les anciens JAR obsolètes (avec version pour éviter conflits)
rm -f "$VELOCITY_DIR"/Floodgate*.jar \
      "$VELOCITY_DIR"/Geyser*.jar \
      "$PAPER_DIR"/ViaVersion*.jar \
      "$PAPER_DIR"/ViaBackwards*.jar \
      "$PAPER_CREATIF_DIR"/Worldedit*.jar \
      "$PAPER_DIR"/WorldEdit*.jar \
      "$PAPER_DIR"/Plugin*.jar \

# Fonction pour vérifier si un fichier existe et télécharger s'il manque
fetch_if_needed() {
    local url=$1
    local target=$2
    local filename=$(basename "$target")

    echo "checking : $filename"
    
    # Check if file exists (exact match by name)
    if [ -f "$DOWNLOAD_DIR/$filename.tmp" ]; then
        echo "✓ $target (déjà téléchargé en tmp)"
        cp "$DOWNLOAD_DIR/$filename.tmp" "$target"
        return 0
    fi

    echo "→ Téléchargement de $filename"
    curl -fsSL --retry 5 --retry-delay 2 -o "$DOWNLOAD_DIR/$filename.tmp" "$url"
    cp "$DOWNLOAD_DIR/$filename.tmp" "$target"
}

# Plugin maison (Paper).
fetch_if_needed \
    "https://github.com/Altherneum/plugin/releases/download/v.${PLUGIN_VERSION}/plugin-1.0-fat.jar" \
    "$PAPER_DIR/Plugin-${PLUGIN_VERSION}.jar"

# Structures du plugin maison (îles, spawns, mines) : ce sont des données, pas
# des plugins. Elles vivent dans le volume partagé mc-plugin-data (monté ici sur
# /plugin/DataFolder) et ne sont téléchargées que si elles sont absentes, pour
# ne jamais écraser une structure retouchée en jeu. Même source que l'ancien
# update.sh du dépôt server.
STRUCTURES_DIR=/plugin/DataFolder/structures
STRUCTURES_URL=https://raw.githubusercontent.com/Altherneum/server/main/Serveurs/DataFolder/structures
mkdir -p "$STRUCTURES_DIR"
for structure in spawn spawn_SB spawn_Survie spawn_OPPrison Island mine; do
    if [ -f "$STRUCTURES_DIR/$structure.yml" ]; then
        echo "✓ $structure.yml (déjà présent)"
        continue
    fi
    echo "→ Téléchargement de $structure.yml"
    curl -fsSL --retry 5 --retry-delay 2 \
        -o "$STRUCTURES_DIR/$structure.yml.tmp" \
        "$STRUCTURES_URL/$structure.yml"
    mv "$STRUCTURES_DIR/$structure.yml.tmp" "$STRUCTURES_DIR/$structure.yml"
done

# ViaVersion
fetch_if_needed \
    "https://github.com/ViaVersion/ViaVersion/releases/download/${VIAVERSION_VERSION}/ViaVersion-${VIAVERSION_VERSION}.jar" \
    "$PAPER_DIR/ViaVersion-${VIAVERSION_VERSION}.jar"

# ViaBackwards
fetch_if_needed \
    "https://github.com/ViaVersion/ViaBackwards/releases/download/${VIABACKWARDS_VERSION}/ViaBackwards-${VIABACKWARDS_VERSION}.jar" \
    "$PAPER_DIR/ViaBackwards-${VIABACKWARDS_VERSION}.jar"

# WorldEdit (Paper 1.21.11) - uniquement sur le serveur créatif.
# Note: modrinth uses a fixed release ID, version is in filename only
fetch_if_needed \
    "https://cdn.modrinth.com/data/1u6JkXh5/versions/${WORLDEDIT_OPAQUE}/worldedit-bukkit-${WORLDEDIT_VERSION}.jar" \
    "$PAPER_CREATIF_DIR/Worldedit-${WORLDEDIT_VERSION}.jar"

# Geyser (Bedrock cross-play)
fetch_if_needed \
    "https://download.geysermc.org/v2/projects/geyser/versions/${GEYSER_VERSION}/builds/latest/downloads/velocity" \
    "$VELOCITY_DIR/Geyser-${GEYSER_VERSION}.jar"

# Floodgate (Bedrock cross-play)
fetch_if_needed \
    "https://download.geysermc.org/v2/projects/floodgate/versions/${FLOODGATE_VERSION}/builds/latest/downloads/velocity" \
    "$VELOCITY_DIR/Floodgate-${FLOODGATE_VERSION}.jar"

echo "Plugins prêts dans $PAPER_DIR, $PAPER_CREATIF_DIR et $VELOCITY_DIR"
