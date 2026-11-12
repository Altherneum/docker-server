#!/bin/sh
# =============================================================================
# Crée le compte administrateur Uptime Kuma à partir de .env.
# Appelé automatiquement par `make up` et `make up-service SERVICE=uptime-kuma`.
# Uptime Kuma 2.x ne sait pas créer l'admin par variable d'environnement :
# ce script utilise l'événement Socket.IO public « setup » après le démarrage.
# Idempotent : ne fait rien si un compte existe déjà.
# =============================================================================
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=${ENV_FILE:-.env}
CONTAINER=uptime-kuma
[ -f "$ENV_FILE" ] || { echo "Erreur : $ENV_FILE introuvable. Lancer make init." >&2; exit 1; }

# Docker Compose résout les variables du .env.
ENV_DUMP=$(docker compose --env-file "$ENV_FILE" config --environment)
get_env() {
    printf '%s\n' "$ENV_DUMP" | sed -n "s/^$1=//p" | tail -n 1
}

ADMIN_USER=$(get_env UPTIME_KUMA_ADMIN_USER)
ADMIN_PASSWORD=$(get_env UPTIME_KUMA_ADMIN_PASSWORD)

[ -n "$ADMIN_USER" ] || { echo "Erreur : UPTIME_KUMA_ADMIN_USER est vide." >&2; exit 1; }
[ -n "$ADMIN_PASSWORD" ] || { echo "Erreur : UPTIME_KUMA_ADMIN_PASSWORD est vide." >&2; exit 1; }
if [ "$ADMIN_PASSWORD" = "CHANGE_ME" ]; then
    echo "Erreur : UPTIME_KUMA_ADMIN_PASSWORD vaut CHANGE_ME. Lancer make init." >&2
    exit 1
fi

# Attend que le conteneur soit démarré.
tries=0
while [ "$tries" -lt 90 ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" = "true" ]; then
        break
    fi
    tries=$((tries + 1))
    sleep 2
done
if [ "$tries" -ge 90 ]; then
    echo "Erreur : le conteneur $CONTAINER n'est pas démarré." >&2
    echo "Vérifier : make ps-service SERVICE=uptime-kuma" >&2
    exit 1
fi

# Le script Node tourne dans le conteneur : socket.io-client est déjà installé.
# Il retente la connexion tant que le serveur Uptime Kuma n'est pas prêt.
docker exec -i \
    -e UPTIME_KUMA_ADMIN_USER="$ADMIN_USER" \
    -e UPTIME_KUMA_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
    "$CONTAINER" node - <<'NODE'
const { io } = require("socket.io-client");

const url = "http://127.0.0.1:3001";
const username = process.env.UPTIME_KUMA_ADMIN_USER;
const password = process.env.UPTIME_KUMA_ADMIN_PASSWORD;

if (!username || !password) {
    console.error("Erreur : identifiants Uptime Kuma absents de l'environnement.");
    process.exit(1);
}

let finished = false;
let setupInFlight = false;
let checkInterval = null;

function finish(code, message) {
    if (finished) {
        return;
    }
    finished = true;
    if (checkInterval) {
        clearInterval(checkInterval);
    }
    if (message) {
        if (code === 0) {
            console.log(message);
        } else {
            console.error(message);
        }
    }
    socket.close();
    process.exit(code);
}

function createAdmin() {
    if (finished || setupInFlight) {
        return;
    }
    setupInFlight = true;

    // Si l'événement se perd, autoriser une nouvelle tentative.
    const retryTimer = setTimeout(() => {
        setupInFlight = false;
    }, 10000);

    socket.emit("setup", username, password, (result) => {
        clearTimeout(retryTimer);
        setupInFlight = false;

        if (result && result.ok) {
            finish(0, `→ compte admin Uptime Kuma créé : ${username}`);
            return;
        }

        const message = (result && result.msg) || "réponse inconnue";
        // Course possible avec une autre initialisation : considérer comme succès.
        if (/initialized|already/i.test(message)) {
            finish(0, "→ le compte admin Uptime Kuma existe déjà");
            return;
        }
        finish(1, `Erreur : création du compte admin Uptime Kuma impossible : ${message}`);
    });
}

function checkSetup() {
    if (finished) {
        return;
    }
    socket.emit("needSetup", (needSetup) => {
        if (finished) {
            return;
        }
        if (needSetup === false) {
            finish(0, "→ le compte admin Uptime Kuma existe déjà");
            return;
        }
        if (needSetup === true) {
            createAdmin();
        }
        // Pas de réponse exploitable : le prochain intervalle réessaie.
    });
}

const socket = io(url, {
    transports: ["websocket"],
    reconnection: true,
    reconnectionAttempts: 60,
    reconnectionDelay: 2000,
    timeout: 5000,
});

socket.on("connect", () => {
    // Le serveur enregistre ses handlers après l'événement de connexion :
    // interroger needSetup avec des relances évite de perdre le premier appel.
    checkSetup();
    if (!checkInterval) {
        checkInterval = setInterval(checkSetup, 3000);
    }
});

// Le serveur émet « setup » dès qu'il est prêt : c'est le signal le plus fiable.
socket.on("setup", () => {
    createAdmin();
});

// Les erreurs de connexion sont normales pendant le démarrage ; on laisse
// socket.io-client réessayer. Un délai global évite un blocage indéfini.
setTimeout(() => {
    finish(1, "Erreur : Uptime Kuma n'est pas prêt après 180 secondes.");
}, 180000);
NODE
