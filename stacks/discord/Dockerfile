# =============================================================================
# Bot Discord.
# =============================================================================
FROM eclipse-temurin:21-jre-alpine

# Origine du jar : obligatoirement fournie par le .env via l'argument de build.
ARG BOT_URL

RUN apk add --no-cache curl tzdata \
    && mkdir -p /DiscordBot/data /DiscordBot/Data \
    && : "${BOT_URL:?BOT_URL manquant : definir BOT_URL dans .env}" \
    && curl -fsSL --retry 5 -o /DiscordBot/bot.jar "$BOT_URL"

COPY entrypoint.sh /usr/local/bin/discord-entrypoint
RUN chmod +x /usr/local/bin/discord-entrypoint

WORKDIR /DiscordBot

ENTRYPOINT ["/usr/local/bin/discord-entrypoint"]
