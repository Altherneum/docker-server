#!/bin/sh
# =============================================================================
# install.sh - installation automatique d'un VPS vierge
#
# Usage :
#   sudo ./install.sh --pubkey-file /tmp/id_ed25519.pub
#
# Le script installe Docker et le dépôt, génère .env, puis sécurise l'hôte :
# compte admin, SSH par clé, UFW et mises à jour automatiques.
# fail2ban est fourni par le conteneur stacks/fail2ban/.
#
# Le code est découpé dans install/. Les modules sont chargés dans l'ordre
# des numéros, puis main() est appelée. Aucun module ne s'exécute tout seul.
# =============================================================================
set -eu

INSTALL_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR="$INSTALL_ROOT/install"

if [ ! -d "$INSTALL_DIR" ]; then
    echo "Erreur : dossier install/ introuvable." >&2
    echo "Lancez : cd docker-server && sudo ./install.sh" >&2
    exit 1
fi

# Charge les modules numérotés dans l'ordre : 00, 01, ..., 31.
# Chaque module ne fait que définir des fonctions et des variables.
for module in "$INSTALL_DIR"/[0-9][0-9]-*.sh; do
    . "$module"
done

# Lance l'installation complète.
main "$@"
