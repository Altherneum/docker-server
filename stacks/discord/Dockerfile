# =============================================================================
# Bot Discord.
# =============================================================================
FROM eclipse-temurin:21-jre-alpine

# Origine du jar, surchargeable depuis le .env via l'argument de build BOT_URL.
ARG BOT_URL=https://github.com/lx78WyY0J5/bot-rewrite/releases/latest/download/bot-rewrite-1.0-fat.jar

RUN apk add --no-cache curl tzdata \
    && mkdir -p /DiscordBot/data /DiscordBot/Data \
    && test -n "$BOT_URL" \
    && curl -fsSL --retry 5 -o /DiscordBot/bot.jar "$BOT_URL"

COPY entrypoint.sh /usr/local/bin/discord-entrypoint
RUN chmod +x /usr/local/bin/discord-entrypoint

WORKDIR /DiscordBot

ENTRYPOINT ["/usr/local/bin/discord-entrypoint"]
