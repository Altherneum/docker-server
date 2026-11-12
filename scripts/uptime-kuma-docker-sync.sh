#!/bin/sh
# =============================================================================
# Synchronise les conteneurs Docker visibles par Uptime Kuma en moniteurs
# « Docker Container » et préconfigure la notification Discord.
# Appelé automatiquement par `make up` et par `make up-service` lorsque Uptime
# Kuma tourne. Idempotent : ne crée que les moniteurs manquants, ne modifie ni
# ne supprime les moniteurs existants.
#
# L'hôte Docker est ajouté automatiquement s'il n'existe pas. Le proxy
# uptime-kuma-docker-proxy reste en lecture seule : POST=0.
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

DOCKER_SYNC=${UPTIME_KUMA_DOCKER_SYNC:-$(get_env UPTIME_KUMA_DOCKER_SYNC)}
case "${DOCKER_SYNC:-true}" in
    true|1|yes|YES|on|ON)
        ;;
    false|0|no|NO|off|OFF)
        echo "→ synchronisation des moniteurs Docker Uptime Kuma désactivée"
        exit 0
        ;;
    *)
        echo "Erreur : UPTIME_KUMA_DOCKER_SYNC doit valoir true ou false." >&2
        exit 1
        ;;
esac

ADMIN_USER=$(get_env UPTIME_KUMA_ADMIN_USER)
ADMIN_PASSWORD=$(get_env UPTIME_KUMA_ADMIN_PASSWORD)
DOCKER_HOST_NAME=${UPTIME_KUMA_DOCKER_HOST_NAME:-$(get_env UPTIME_KUMA_DOCKER_HOST_NAME)}
DOCKER_HOST_URL=${UPTIME_KUMA_DOCKER_HOST_URL:-$(get_env UPTIME_KUMA_DOCKER_HOST_URL)}
DOCKER_EXCLUDE=${UPTIME_KUMA_DOCKER_EXCLUDE:-$(get_env UPTIME_KUMA_DOCKER_EXCLUDE)}

DOCKER_HOST_NAME=${DOCKER_HOST_NAME:-Local}
DOCKER_HOST_URL=${DOCKER_HOST_URL:-http://uptime-kuma-docker-proxy:2375}

DISCORD_ENABLED=$(get_env UPTIME_KUMA_DISCORD_ENABLED)
[ -n "$DISCORD_ENABLED" ] || DISCORD_ENABLED=true
DISCORD_WEBHOOK_URL=$(get_env UPTIME_KUMA_DISCORD_WEBHOOK_URL)
DISCORD_BOT_NAME=$(get_env UPTIME_KUMA_DISCORD_BOT_NAME)
[ -n "$DISCORD_BOT_NAME" ] || DISCORD_BOT_NAME="Uptime Kuma"
# Le préfixe peut être vide : ne remplacer par la valeur par défaut que si la
# clé est totalement absente du fichier .env.
if grep -q '^UPTIME_KUMA_DISCORD_PREFIX=' "$ENV_FILE"; then
    DISCORD_PREFIX=$(get_env UPTIME_KUMA_DISCORD_PREFIX)
else
    DISCORD_PREFIX="[Uptime Kuma]"
fi
DISCORD_NOTIFICATION_NAME=$(get_env UPTIME_KUMA_DISCORD_NOTIFICATION_NAME)
[ -n "$DISCORD_NOTIFICATION_NAME" ] || DISCORD_NOTIFICATION_NAME=Discord
DISCORD_DEFAULT=$(get_env UPTIME_KUMA_DISCORD_DEFAULT)
[ -n "$DISCORD_DEFAULT" ] || DISCORD_DEFAULT=true
DISCORD_APPLY_EXISTING=$(get_env UPTIME_KUMA_DISCORD_APPLY_EXISTING)
[ -n "$DISCORD_APPLY_EXISTING" ] || DISCORD_APPLY_EXISTING=true

# Détail utile pour le débogage : UPTIME_KUMA_SYNC_VERBOSE=true (ou VERBOSE=1).
VERBOSE=${UPTIME_KUMA_SYNC_VERBOSE:-${VERBOSE:-}}

[ -n "$ADMIN_USER" ] || { echo "Erreur : UPTIME_KUMA_ADMIN_USER est vide." >&2; exit 1; }
[ -n "$ADMIN_PASSWORD" ] || { echo "Erreur : UPTIME_KUMA_ADMIN_PASSWORD est vide." >&2; exit 1; }
if [ "$ADMIN_PASSWORD" = "CHANGE_ME" ]; then
    echo "Erreur : UPTIME_KUMA_ADMIN_PASSWORD vaut CHANGE_ME. Lancer make init." >&2
    exit 1
fi

# Attend que le conteneur soit démarré (60 s : le script est appelé après
# l'initialisation du compte admin, le conteneur est normalement déjà lancé).
tries=0
while [ "$tries" -lt 30 ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" = "true" ]; then
        break
    fi
    tries=$((tries + 1))
    sleep 2
done
if [ "$tries" -ge 30 ]; then
    echo "Erreur : le conteneur $CONTAINER n'est pas démarré." >&2
    echo "Vérifier : make ps-service SERVICE=uptime-kuma" >&2
    exit 1
fi

# Le script Node tourne dans le conteneur : socket.io-client est déjà installé.
# Il se connecte au compte admin, configure la notification Discord, vérifie
# l'hôte Docker puis crée les moniteurs manquants. Aucun mot de passe, webhook
# ni jeton n'est affiché.
docker exec -i \
    -e UPTIME_KUMA_ADMIN_USER="$ADMIN_USER" \
    -e UPTIME_KUMA_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
    -e UPTIME_KUMA_DOCKER_HOST_NAME="$DOCKER_HOST_NAME" \
    -e UPTIME_KUMA_DOCKER_HOST_URL="$DOCKER_HOST_URL" \
    -e UPTIME_KUMA_DOCKER_EXCLUDE="$DOCKER_EXCLUDE" \
    -e UPTIME_KUMA_DISCORD_ENABLED="$DISCORD_ENABLED" \
    -e UPTIME_KUMA_DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL" \
    -e UPTIME_KUMA_DISCORD_BOT_NAME="$DISCORD_BOT_NAME" \
    -e UPTIME_KUMA_DISCORD_PREFIX="$DISCORD_PREFIX" \
    -e UPTIME_KUMA_DISCORD_NOTIFICATION_NAME="$DISCORD_NOTIFICATION_NAME" \
    -e UPTIME_KUMA_DISCORD_DEFAULT="$DISCORD_DEFAULT" \
    -e UPTIME_KUMA_DISCORD_APPLY_EXISTING="$DISCORD_APPLY_EXISTING" \
    -e UPTIME_KUMA_SYNC_VERBOSE="$VERBOSE" \
    "$CONTAINER" node - <<'NODE'
const { io } = require("socket.io-client");

const url = "http://127.0.0.1:3001";
const username = process.env.UPTIME_KUMA_ADMIN_USER;
const password = process.env.UPTIME_KUMA_ADMIN_PASSWORD;
const hostName = process.env.UPTIME_KUMA_DOCKER_HOST_NAME || "Local";
const hostURL = (process.env.UPTIME_KUMA_DOCKER_HOST_URL || "http://uptime-kuma-docker-proxy:2375").replace(/\/+$/, "");
const exclude = new Set(
    (process.env.UPTIME_KUMA_DOCKER_EXCLUDE || "")
        .split(",")
        .map((name) => name.trim().replace(/^\/+/, ""))
        .filter(Boolean)
);

if (!username || !password) {
    console.error("Erreur : identifiants Uptime Kuma absents de l'environnement.");
    process.exit(1);
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function normalizeURL(value) {
    return String(value || "").replace(/\/+$/, "");
}

function parseBoolean(value, label, fallback) {
    if (value === undefined || value === null || value === "") {
        return fallback;
    }
    if (/^(true|1|yes|on)$/i.test(String(value))) {
        return true;
    }
    if (/^(false|0|no|off)$/i.test(String(value))) {
        return false;
    }
    throw new Error(`${label} doit valoir true ou false`);
}

const verbose = /^(true|1|yes|on)$/i.test(String(process.env.UPTIME_KUMA_SYNC_VERBOSE || ""));
function logDetail(message) {
    if (verbose) {
        console.log(message);
    }
}

function notificationStatusMessage(result) {
    switch (result.status) {
        case "created":
            return "notification Discord créée";
        case "updated":
            return "notification Discord mise à jour";
        case "unchanged":
            return "notification Discord à jour";
        case "disabled":
            return "notification Discord désactivée";
        case "unconfigured":
            return "notification Discord non configurée (webhook vide)";
        case "failed":
            return "notification Discord en erreur";
        default:
            return "notification Discord inconnue";
    }
}

let finished = false;
let loggedIn = false;
let loginInFlight = false;
let loginAttempts = 0;
let loginTimer = null;
let globalTimer = null;

const socket = io(url, {
    transports: ["websocket"],
    reconnection: true,
    reconnectionAttempts: 60,
    reconnectionDelay: 2000,
    timeout: 5000,
});

let monitorList = null;
let dockerHostList = null;
let notificationList = null;

function finish(code, message) {
    if (finished) {
        return;
    }
    finished = true;
    if (loginTimer) {
        clearTimeout(loginTimer);
    }
    if (globalTimer) {
        clearTimeout(globalTimer);
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

function emitAck(event, ...args) {
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
            reject(new Error(`délai dépassé pour l'événement ${event}`));
        }, 15000);

        socket.emit(event, ...args, (result) => {
            clearTimeout(timer);
            resolve(result);
        });
    });
}

function tryLogin() {
    if (finished || loggedIn || loginInFlight) {
        return;
    }
    loginInFlight = true;
    loginAttempts += 1;

    const ackTimer = setTimeout(() => {
        loginInFlight = false;
        if (!finished && !loggedIn) {
            if (loginAttempts >= 40) {
                finish(1, "Erreur : connexion à Uptime Kuma impossible après 40 tentatives.");
            } else {
                loginTimer = setTimeout(tryLogin, 1000);
            }
        }
    }, 3000);

    socket.emit("login", { username, password }, (result) => {
        clearTimeout(ackTimer);
        loginInFlight = false;

        if (finished) {
            return;
        }
        if (!result || !result.ok) {
            const message = (result && result.msg) || "pas de réponse";
            finish(1, `Erreur : connexion au compte admin Uptime Kuma impossible (${message}).`);
            return;
        }

        loggedIn = true;
        onLoggedIn().catch((error) => {
            finish(1, `Erreur : synchronisation Uptime Kuma impossible : ${error.message}`);
        });
    });
}

async function waitForList(getter, label) {
    const start = Date.now();
    while (Date.now() - start < 10000) {
        const value = getter();
        if (value !== null) {
            return value;
        }
        await wait(100);
    }
    throw new Error(`liste ${label} non reçue de Uptime Kuma`);
}

async function syncDiscordNotification(notificationArray) {
    let enabled;
    let isDefault;
    let applyExisting;
    try {
        enabled = parseBoolean(process.env.UPTIME_KUMA_DISCORD_ENABLED, "UPTIME_KUMA_DISCORD_ENABLED", true);
        isDefault = parseBoolean(process.env.UPTIME_KUMA_DISCORD_DEFAULT, "UPTIME_KUMA_DISCORD_DEFAULT", true);
        applyExisting = parseBoolean(
            process.env.UPTIME_KUMA_DISCORD_APPLY_EXISTING,
            "UPTIME_KUMA_DISCORD_APPLY_EXISTING",
            true
        );
    } catch (error) {
        console.error(`Erreur : ${error.message}`);
        return { failed: true, status: "failed" };
    }

    if (!enabled) {
        return { failed: false, status: "disabled" };
    }

    const webhook = (process.env.UPTIME_KUMA_DISCORD_WEBHOOK_URL || "").trim();
    if (!webhook || webhook === "CHANGE_ME") {
        return { failed: false, status: "unconfigured" };
    }

    try {
        const parsed = new URL(webhook);
        if (parsed.protocol !== "https:") {
            throw new Error("HTTPS requis");
        }
    } catch {
        console.error("Erreur : UPTIME_KUMA_DISCORD_WEBHOOK_URL n'est pas une URL HTTPS valide.");
        return { failed: true, status: "failed" };
    }

    const name = (process.env.UPTIME_KUMA_DISCORD_NOTIFICATION_NAME || "Discord").trim() || "Discord";
    const botName = (process.env.UPTIME_KUMA_DISCORD_BOT_NAME || "Uptime Kuma").trim() || "Uptime Kuma";
    const prefix = process.env.UPTIME_KUMA_DISCORD_PREFIX ?? "[Uptime Kuma]";

    let existing = null;
    let existingConfig = {};
    for (const notification of notificationArray) {
        if (notification.name !== name || !notification.config) {
            continue;
        }
        try {
            const config = typeof notification.config === "string" ? JSON.parse(notification.config) : notification.config;
            if (config && config.type === "discord") {
                existing = notification;
                existingConfig = config;
                break;
            }
        } catch {
            // Configuration illisible : ignorer cette entrée.
        }
    }

    if (
        existing &&
        existingConfig.discordWebhookUrl === webhook &&
        existingConfig.discordUsername === botName &&
        existingConfig.discordPrefixMessage === prefix &&
        existing.isDefault === isDefault
    ) {
        logDetail(`→ notification Discord déjà à jour (#${existing.id})`);
        return { failed: false, status: "unchanged", id: existing.id };
    }

    const notification = {
        ...existingConfig,
        name,
        type: "discord",
        isDefault,
        applyExisting,
        discordWebhookUrl: webhook,
        discordUsername: botName,
        discordPrefixMessage: prefix,
        discordChannelType: existingConfig.discordChannelType || "channel",
        discordMessageFormat: existingConfig.discordMessageFormat || "normal",
        discordUseMessageTemplate: existingConfig.discordUseMessageTemplate || false,
        discordMessageTemplate: existingConfig.discordMessageTemplate || "",
        postName: existingConfig.postName || "",
        threadId: existingConfig.threadId || "",
        disableUrl: typeof existingConfig.disableUrl === "boolean" ? existingConfig.disableUrl : false,
        discordSuppressNotifications:
            typeof existingConfig.discordSuppressNotifications === "boolean"
                ? existingConfig.discordSuppressNotifications
                : false,
    };

    let result;
    try {
        result = await emitAck("addNotification", notification, existing ? existing.id : null);
    } catch (error) {
        console.error(`Erreur : notification Discord non enregistrée (${error.message})`);
        return { failed: true, status: "failed" };
    }
    if (!result || !result.ok) {
        console.error(
            `Erreur : notification Discord non enregistrée (${(result && result.msg) || "pas de réponse"})`
        );
        return { failed: true, status: "failed" };
    }

    const saved = {
        id: result.id,
        name,
        config: JSON.stringify({ ...notification, applyExisting: false }),
        isDefault,
        active: true,
    };
    if (existing) {
        Object.assign(existing, saved);
        console.log(`→ notification Discord mise à jour (#${result.id})`);
    } else {
        notificationArray.push(saved);
        console.log(`→ notification Discord créée (#${result.id})`);
    }
    logDetail(
        `→ notification Discord : bot « ${botName} », préfixe « ${prefix} », défaut=${
            isDefault ? "oui" : "non"
        }, appliquée aux moniteurs existants=${applyExisting ? "oui" : "non"}`
    );
    return { failed: false, status: existing ? "updated" : "created", id: result.id };
}

async function onLoggedIn() {
    const monitors = await waitForList(() => monitorList, "des moniteurs");
    const hosts = await waitForList(() => dockerHostList, "des hôtes Docker");
    const notifications = await waitForList(() => notificationList, "des notifications");
    const notificationArray = Array.isArray(notifications) ? notifications : [];
    const notificationResult = await syncDiscordNotification(notificationArray);
    const notificationSummary = notificationStatusMessage(notificationResult);

    const monitorArray = Array.isArray(monitors) ? monitors : Object.values(monitors || {});
    const hostArray = Array.isArray(hosts) ? hosts : [];

    let host = hostArray.find((item) => {
        return item.dockerType === "tcp" && normalizeURL(item.dockerDaemon) === hostURL;
    });
    if (!host) {
        host = hostArray.find((item) => item.name === hostName);
    }

    if (host) {
        logDetail(`→ hôte Docker « ${host.name} » déjà configuré`);
    } else {
        const result = await emitAck("addDockerHost", {
            name: hostName,
            dockerType: "tcp",
            dockerDaemon: hostURL,
        }, null);
        if (!result || !result.ok) {
            throw new Error(`création de l'hôte Docker impossible (${(result && result.msg) || "pas de réponse"})`);
        }
        host = {
            id: result.id,
            name: hostName,
            dockerType: "tcp",
            dockerDaemon: hostURL,
        };
        console.log(`→ hôte Docker « ${hostName} » créé`);
    }

    const test = await emitAck("testDockerHost", {
        dockerType: host.dockerType,
        dockerDaemon: host.dockerDaemon,
    });
    if (!test || !test.ok) {
        throw new Error(`test de l'hôte Docker « ${host.name} » échoué (${(test && test.msg) || "pas de réponse"})`);
    }
    logDetail(`→ hôte Docker « ${host.name} » joignable : ${test.msg}`);

    let containers;
    try {
        const response = await fetch(`${hostURL}/containers/json`, {
            signal: AbortSignal.timeout(10000),
        });
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        containers = await response.json();
    } catch (error) {
        throw new Error(`lecture des conteneurs via le proxy impossible (${error.message})`);
    }

    const containersToMonitor = [];
    const seenNames = new Set();
    for (const container of containers) {
        const rawName = Array.isArray(container.Names) && container.Names.length > 0 ? container.Names[0] : "";
        const name = String(rawName).replace(/^\/+/, "");
        if (!name || seenNames.has(name)) {
            continue;
        }
        seenNames.add(name);

        if (exclude.has(name)) {
            logDetail(`→ conteneur ignoré (UPTIME_KUMA_DOCKER_EXCLUDE) : ${name}`);
            continue;
        }

        containersToMonitor.push({
            name,
            id: container.Id,
            shortId: String(container.Id || "").slice(0, 12),
        });
    }

    if (containersToMonitor.length === 0) {
        if (notificationResult.failed) {
            finish(1, "Erreur : notification Discord non configurée.");
        } else {
            finish(0, `→ Uptime Kuma : aucun conteneur en cours d'exécution, ${notificationSummary}`);
        }
        return;
    }

    const existing = new Set();
    for (const monitor of monitorArray) {
        if (monitor.type !== "docker" || !monitor.docker_container) {
            continue;
        }
        existing.add(monitor.docker_container);
    }

    const defaultNotifications = {};
    for (const notification of notificationArray) {
        if (notification.isDefault === true) {
            defaultNotifications[notification.id] = true;
        }
    }

    let added = 0;
    let failed = 0;

    for (const container of containersToMonitor) {
        if (existing.has(container.name) || (container.id && existing.has(container.id)) || (container.shortId && existing.has(container.shortId))) {
            logDetail(`→ moniteur Docker déjà présent : ${container.name}`);
            continue;
        }

        const monitorName = `Docker - ${container.name}`.slice(0, 150);
        const monitor = {
            name: monitorName,
            description: "Conteneur Docker synchronisé automatiquement via le proxy en lecture seule.",
            type: "docker",
            docker_container: container.name,
            docker_host: host.id,
            active: true,
            parent: null,
            interval: 60,
            retryInterval: 60,
            resendInterval: 0,
            maxretries: 0,
            notificationIDList: defaultNotifications,
            accepted_statuscodes: ["200-299"],
            kafkaProducerBrokers: [],
            kafkaProducerSaslOptions: { mechanism: "None" },
            conditions: [],
            rabbitmqNodes: [],
            upsideDown: false,
            expiryNotification: false,
            domainExpiryNotification: false,
            ignoreTls: false,
            maxredirects: 10,
            saveResponse: false,
            saveErrorResponse: true,
            responseMaxLength: 1024,
            dns_resolve_type: "A",
            dns_resolve_server: "",
            proxyId: null,
            method: "GET",
            url: "",
        };

        try {
            const result = await emitAck("add", monitor);
            if (!result || !result.ok) {
                failed += 1;
                console.error(`Erreur : moniteur Docker « ${container.name} » non créé (${(result && result.msg) || "pas de réponse"})`);
                continue;
            }
            existing.add(container.name);
            added += 1;
            console.log(`→ moniteur Docker ajouté : ${container.name} (#${result.monitorID})`);
        } catch (error) {
            failed += 1;
            console.error(`Erreur : moniteur Docker « ${container.name} » non créé (${error.message})`);
        }
    }

    if (notificationResult.failed) {
        finish(
            1,
            `Erreur : notification Discord non configurée${
                failed > 0 ? `, ${failed} moniteur(s) Docker non créé(s)` : ""
            }.`
        );
    } else if (added === 0 && failed === 0) {
        finish(
            0,
            `→ Uptime Kuma : ${containersToMonitor.length} conteneur(s) détecté(s), aucun nouveau moniteur Docker, ${notificationSummary}`
        );
    } else if (failed > 0) {
        finish(1, `Erreur : ${failed} moniteur(s) Docker non créé(s), ${added} ajouté(s).`);
    } else {
        finish(
            0,
            `→ Uptime Kuma : ${added} moniteur(s) Docker ajouté(s) sur ${containersToMonitor.length} conteneur(s) détecté(s), ${notificationSummary}`
        );
    }
}

socket.on("monitorList", (list) => {
    monitorList = list;
});
socket.on("dockerHostList", (list) => {
    dockerHostList = list;
});
socket.on("notificationList", (list) => {
    notificationList = list;
});

socket.on("info", () => {
    // Le serveur est prêt : tenter la connexion sans attendre le prochain délai.
    tryLogin();
});

socket.on("setup", () => {
    finish(1, "Erreur : le compte admin Uptime Kuma n'existe pas. Lancer sudo make uptime-kuma-admin.");
});

socket.on("disconnect", (reason) => {
    if (!finished && loggedIn) {
        finish(1, `Erreur : connexion à Uptime Kuma perdue (${reason}).`);
    }
});

socket.on("connect", () => {
    tryLogin();
});

globalTimer = setTimeout(() => {
    finish(1, "Erreur : synchronisation Uptime Kuma trop longue (180 s).");
}, 180000);
NODE
