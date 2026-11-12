#!/bin/sh
# Configuration appliquée une seule fois, après l'installation de Nextcloud.
set -eu

OCC="php /var/www/html/occ"

# Adresse e-mail du compte administrateur (l'image ne la lit pas elle-même).
if [ -n "${NEXTCLOUD_ADMIN_EMAIL:-}" ] && [ -n "${NEXTCLOUD_ADMIN_USER:-}" ]; then
    $OCC user:setting "$NEXTCLOUD_ADMIN_USER" settings email "$NEXTCLOUD_ADMIN_EMAIL" || true
fi

# Utilise le conteneur nextcloud-cron au lieu des requêtes AJAX.
$OCC background:cron || true
