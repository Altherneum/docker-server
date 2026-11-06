#!/bin/sh
# Vérifie que .env contient les secrets nécessaires avant make up

set -eu

ENV_FILE=${ENV_FILE:-.env}
[ -f "$ENV_FILE" ] || {
    echo "ERROR : $ENV_FILE introuvable. Lancer make init." >&2
    exit 1
}

get_env() {
    sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

echo "=== Verification de la configuration ==="

# DOMAIN_NAME et TLD doivent être présents.
if ! grep -q "^DOMAIN_NAME=" "$ENV_FILE"; then
    echo "ERROR : DOMAIN_NAME missing in $ENV_FILE" >&2
    exit 1
fi
if ! grep -q "^TLD=" "$ENV_FILE"; then
    echo "ERROR : TLD missing in $ENV_FILE" >&2
    exit 1
fi

DOMAIN_NAME=$(get_env DOMAIN_NAME)
TLD=$(get_env TLD)

if [ -z "$DOMAIN_NAME" ]; then
    echo "ERROR : DOMAIN_NAME vide dans $ENV_FILE" >&2
    exit 1
fi

# TLD contient le point initial (.fr) ou est vide pour un domaine local.
if [ -n "$TLD" ] && [ "$TLD" = "${TLD#.}" ]; then
    echo "ERROR : TLD doit inclure le point initial (ex: .fr), ou être vide." >&2
    exit 1
fi

# GID du socket Docker requis par le runner Forgejo Actions.
if [ -z "$(get_env DOCKER_GID)" ]; then
    echo "ERROR : DOCKER_GID manquant dans $ENV_FILE." >&2
    echo "        Lancer make init pour détecter le GID du socket Docker." >&2
    exit 1
fi

DOMAIN="${DOMAIN_NAME}${TLD}"

echo ""
echo "=== Checking email configurations ==="
echo "DOMAIN_NAME: $DOMAIN_NAME"
echo "TLD: ${TLD:-<vide>}"
echo "DOMAIN: $DOMAIN"

# Verify that mail variables exist but don't need to be validated here
if grep -q "^AZURIOM_MAIL_HOST=" "$ENV_FILE"; then
    echo "✓ AZURIOM_MAIL_HOST found"
fi
if grep -q "^FORGEJO_MAIL_HOST=" "$ENV_FILE"; then
    echo "✓ FORGEJO_MAIL_HOST found"
fi

echo ""
echo "=== All required variables present ==="
