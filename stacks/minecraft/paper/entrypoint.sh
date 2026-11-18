#!/bin/sh
# Prépare un serveur Paper derrière Velocity puis le lance.
set -eu

: "${SERVER_NAME:?SERVER_NAME manquant}"
: "${VELOCITY_SECRET:?VELOCITY_SECRET manquant}"
: "${MINECRAFT_RCON_PASSWORD:?MINECRAFT_RCON_PASSWORD manquant}"

MEMORY=${MEMORY:-1G}
SERVER_PORT=${SERVER_PORT:-25565}
RCON_PORT=${RCON_PORT:-25575}
LEVEL_NAME=${LEVEL_NAME:-Spawn}
MAX_PLAYERS=${MAX_PLAYERS:-20}
: "${DOMAIN:?DOMAIN manquant}"
SERVER_MOTD=${SERVER_MOTD:-"${SERVER_NAME}.${DOMAIN}"}
ONLINE_MODE=${VELOCITY_ONLINE_MODE:-true}

case "$ONLINE_MODE" in
    true|false) ;;
    *)
        echo "Erreur : VELOCITY_ONLINE_MODE doit valoir true ou false." >&2
        exit 1
        ;;
esac

mkdir -p /data/config /data/plugins /data/cache

# --- Données partagées du plugin maison -------------------------------------
# Le volume mc-plugin-data est monté sur /plugin/DataFolder (voir compose.yaml).
# Le plugin calcule son dossier de données depuis /data/plugins/plugin (trois
# parents au-dessus), soit /DataFolder. On relie ce chemin au volume partagé.

# Crée le dossier cible dans le volume partagé (sécurité si le montage manque).
mkdir -p /plugin/DataFolder

# Vérifie si /DataFolder n'est pas déjà un lien symbolique.
if [ ! -L /DataFolder ]; then
    # Supprime un éventuel vrai dossier local : ln -s refuse de le remplacer.
    rm -rf /DataFolder
    # Crée le lien /DataFolder -> /plugin/DataFolder attendu par le plugin.
    ln -s /plugin/DataFolder /DataFolder
fi

# Le build a pré-téléchargé le jar Mojang et le jar Paper patché. On les copie
# dans le volume avant le premier démarrage ; le réseau egress ne sert qu'aux
# vérifications de plugins et aux appels Mojang, jamais au trafic joueur.
mkdir -p "/data/versions/${PAPER_VERSION}"
[ -f "/data/cache/mojang_${PAPER_VERSION}.jar" ] \
    || cp "/opt/paper-cache/cache/mojang_${PAPER_VERSION}.jar" /data/cache/
[ -f "/data/versions/${PAPER_VERSION}/paper-${PAPER_VERSION}.jar" ] \
    || cp "/opt/paper-cache/versions/${PAPER_VERSION}/paper-${PAPER_VERSION}.jar" \
        "/data/versions/${PAPER_VERSION}/"

printf 'eula=true\n' > /data/eula.txt

# --- Monde initial ----------------------------------------------------------
# Les cartes de départ sont copiées dans l'image depuis stacks/minecraft/paper/maps.
# L'ancien dépôt utilisait la carte Survie pour les serveurs Anarchie et Test.
case "$SERVER_NAME" in
    hub)           MAP_NAME=Hub ;;
    survie)        MAP_NAME=Survie ;;
    anarchie|test) MAP_NAME=Survie ;;
    skyblock)      MAP_NAME=SkyBlock ;;
    opprison)      MAP_NAME=OPPrison ;;
    *)             MAP_NAME= ;;
esac

if [ -n "$MAP_NAME" ] && [ -f "/opt/maps/${MAP_NAME}/${LEVEL_NAME}.zip" ]; then
    MAP_ARCHIVE="/opt/maps/${MAP_NAME}/${LEVEL_NAME}.zip"
    MAP_CHECKSUM=$(sha256sum "$MAP_ARCHIVE" | awk '{print $1}')
    MAP_STAMP="/data/.${LEVEL_NAME}.map.sha256"

    if [ ! -f "/data/${LEVEL_NAME}/level.dat" ] \
        || [ "$(cat "$MAP_STAMP" 2>/dev/null || true)" != "$MAP_CHECKSUM" ]; then
        echo "→ Installation du monde ${MAP_NAME}/${LEVEL_NAME} dans /data"

        MAP_TMP=$(mktemp -d)
        if tar -tf "$MAP_ARCHIVE" >/dev/null 2>&1; then
            tar -xf "$MAP_ARCHIVE" -C "$MAP_TMP"
        else
            unzip -q "$MAP_ARCHIVE" -d "$MAP_TMP"
        fi

        # Deux dispositions existent dans l'ancien dépôt : les archives tar
        # contiennent « Serveurs/<Carte>/Spawn/... », les zip contiennent
        # directement « Spawn/... ».
        MAP_SOURCE="$MAP_TMP/Serveurs/${MAP_NAME}/${LEVEL_NAME}"
        [ -d "$MAP_SOURCE" ] || MAP_SOURCE="$MAP_TMP/${LEVEL_NAME}"

        if [ ! -d "$MAP_SOURCE" ]; then
            echo "Erreur : monde ${LEVEL_NAME} introuvable dans ${MAP_ARCHIVE}." >&2
            rm -rf "$MAP_TMP"
            exit 1
        fi

        rm -rf "/data/${LEVEL_NAME}"
        mv "$MAP_SOURCE" "/data/${LEVEL_NAME}"
        rm -rf "$MAP_TMP"
        printf '%s\n' "$MAP_CHECKSUM" > "$MAP_STAMP"
    else
        echo "→ Monde ${LEVEL_NAME} déjà installé (${MAP_NAME})"
    fi
fi

# Configuration Paper : le secret Velocity est réinjecté à chaque démarrage.
if [ ! -f /data/config/paper-global.yml ]; then
    cp /opt/paper/config/paper-global.yml /data/config/paper-global.yml
fi
sed -i "s|^    secret: .*|    secret: '${VELOCITY_SECRET}'|" /data/config/paper-global.yml
sed -i "/^  velocity:/,/^[^ ]/ s|^    online-mode: .*|    online-mode: ${ONLINE_MODE}|" /data/config/paper-global.yml
# Les pseudos Bedrock (préfixe Floodgate) ne respectent pas la regex Java.
sed -i "s|^  perform-username-validation: .*|  perform-username-validation: false|" /data/config/paper-global.yml

if [ ! -f /data/config/paper-world-defaults.yml ]; then
    cp /opt/paper/config/paper-world-defaults.yml /data/config/paper-world-defaults.yml
fi
if [ ! -f /data/ops.json ]; then
    cp /opt/paper/config/ops.json /data/ops.json
fi
if [ ! -f /data/server-icon.png ]; then
    cp /opt/paper/config/server-icon.png /data/server-icon.png
fi

# Plugins partagés, mis à jour par le service mc-plugins.
# Nettoyage des anciens noms/plugins Paper (Geyser/Floodgate sont proxy-only)
# et de WorldEdit, qui n'est autorisé que sur le serveur créatif.
rm -f /data/plugins/geyser*.jar \
      /data/plugins/Geyser*.jar \
      /data/plugins/Plugin*.jar \
      /data/plugins/.paper-remapped/Plugin*.jar \
      /data/plugins/.paper-remapped/plugin*.jar \
      /data/plugins/floodgate*.jar \
      /data/plugins/Floodgate*.jar \
      /data/plugins/ViaVersion-*.jar \
      /data/plugins/ViaBackwards-*.jar \
      /data/plugins/worldedit-bukkit-*.jar \
      /data/plugins/WorldEdit.jar

if [ -d /opt/plugins/paper ]; then
    find /opt/plugins/paper -maxdepth 1 -name '*.jar' -exec cp -f {} /data/plugins/ \;
fi

# WorldEdit n'est installé que sur le serveur créatif.
if [ "$SERVER_NAME" = "creatif" ] && [ -d /opt/plugins/paper-creatif ]; then
    find /opt/plugins/paper-creatif -maxdepth 1 -name '*.jar' -exec cp -f {} /data/plugins/ \;
fi

# --- Resource pack -----------------------------------------------------------
# Calculer le hash du ressource pack
RESOURCE_PACK_URL=${AZURIOM_RESOURCE_PACK_URL:-}
RESOURCE_PACK_SHA1=""
if [ -n "$RESOURCE_PACK_URL" ]; then
    RESOURCE_PACK_CACHE=/data/cache/resourcePack.zip
    if curl -fsSL --retry 3 --retry-delay 2 \
        -o "${RESOURCE_PACK_CACHE}.tmp" "$RESOURCE_PACK_URL"; then
        mv "${RESOURCE_PACK_CACHE}.tmp" "$RESOURCE_PACK_CACHE"
    else
        rm -f "${RESOURCE_PACK_CACHE}.tmp"
        echo "Attention : resource pack non téléchargé, hash SHA-1 indisponible." >&2
    fi
    if [ -s "$RESOURCE_PACK_CACHE" ]; then
        RESOURCE_PACK_SHA1=$(sha1sum "$RESOURCE_PACK_CACHE" | awk '{print $1}')
    fi
fi

cat > /data/server.properties <<EOF
enable-jmx-monitoring=false
rcon.port=${RCON_PORT}
gamemode=survival
enable-command-block=false
enable-query=false
generator-settings={}
enforce-secure-profile=false
level-name=${LEVEL_NAME}
motd=${SERVER_MOTD}
pvp=true
generate-structures=true
max-chained-neighbor-updates=1000000
difficulty=easy
network-compression-threshold=256
max-tick-time=60000
require-resource-pack=false
use-native-transport=true
max-players=${MAX_PLAYERS}
online-mode=false
enable-status=true
allow-flight=false
broadcast-rcon-to-ops=true
view-distance=8
server-ip=0.0.0.0
allow-nether=true
server-port=${SERVER_PORT}
enable-rcon=true
sync-chunk-writes=false
op-permission-level=4
prevent-proxy-connections=false
hide-online-players=false
resource-pack=${RESOURCE_PACK_URL}
entity-broadcast-range-percentage=100
simulation-distance=6
rcon.password=${MINECRAFT_RCON_PASSWORD}
player-idle-timeout=0
debug=false
force-gamemode=false
rate-limit=0
hardcore=false
white-list=false
broadcast-console-to-ops=true
spawn-npcs=true
previews-chat=false
spawn-animals=true
function-permission-level=2
level-type=minecraft\:normal
text-filtering-config=
spawn-monsters=true
enforce-whitelist=false
spawn-protection=0
resource-pack-sha1=${RESOURCE_PACK_SHA1}
max-world-size=29999984
EOF

exec java \
    -Xms"${MEMORY}" -Xmx"${MEMORY}" \
    -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
    -Dterminal.jline=false -Dterminal.ansi=true \
    -jar /opt/paper.jar --nogui
