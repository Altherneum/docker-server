#!/bin/sh
set -eu

: "${DISCORD_BOT_TOKEN:?DISCORD_BOT_TOKEN manquant}"
if [ "$DISCORD_BOT_TOKEN" = "CHANGE_ME" ]; then
    echo "Erreur : renseigner DISCORD_BOT_TOKEN dans .env puis relancer." >&2
    exit 1
fi

mkdir -p /DiscordBot/data /DiscordBot/Data

cat > /DiscordBot/data/tokens.yml <<EOF
BotName: ${DISCORD_BOT_NAME:-CHANGE_ME}
Bot: ${DISCORD_BOT_TOKEN}
EOF
chmod 600 /DiscordBot/data/tokens.yml

# JDA + cache des membres + cache des 10 000 derniers messages : 32 M de heap
# est trop juste. 256 M laisse de la marge sans réserver inutilement la RAM.
exec java -Xms64M -Xmx256M -jar /DiscordBot/bot.jar
