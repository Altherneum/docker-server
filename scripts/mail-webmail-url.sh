#!/bin/sh
# =============================================================================
# mail-webmail-url.sh - corrige le lien "Webmail" de l'interface mailcow.
#
# Mailcow pointe le bouton Webmail vers /SOGo/so, qui passe par son SSO et peut
# répondre 401 (puis déclencher fail2ban). On le remplace par /SOGo/, la page
# de connexion SOGo qui fonctionne.
#
# Idempotent : relancer après une mise à jour de mailcow.
#
# Usage : sudo ./scripts/mail-webmail-url.sh
# =============================================================================
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MAIL_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/mail-lib.sh"
mail_load_env "$MAIL_ROOT"

[ -d "$MAILCOW_DIR" ] || {
    mail_info "mailcow n'est pas installé dans $MAILCOW_DIR ; rien à faire."
    exit 0
}

web_dir="$MAILCOW_DIR/data/web"
[ -d "$web_dir" ] || {
    mail_info "dossier $web_dir introuvable ; rien à faire."
    exit 0
}

changed=0

replace() {
    file=$1
    old=$2
    new=$3
    [ -f "$file" ] || return 0
    grep -Fq "$old" "$file" || return 0
    if ! sed -i "s|$old|$new|g" "$file" 2>/dev/null; then
        mail_warn "impossible de modifier $file (droits root ? relancez avec sudo)."
        return 0
    fi
    changed=1
    mail_info "corrigé : $file"
}

# Bouton Webmail (les deux orthographes possibles selon la version de mailcow).
replace "$web_dir/inc/vars.inc.php" "'/SOGo/so/'" "'/SOGo/'"
replace "$web_dir/inc/vars.inc.php" "'/SOGo/so'" "'/SOGo/'"

# Redirections après connexion / changement de mot de passe.
replace "$web_dir/index.php" "Location: /SOGo/so/" "Location: /SOGo/"
replace "$web_dir/inc/triggers.user.inc.php" "Location: /SOGo/so/" "Location: /SOGo/"

if [ "$changed" -eq 0 ]; then
    mail_info "URL Webmail déjà corrigée"
    exit 0
fi

if mailcow_service_running php-fpm-mailcow; then
    if mailcow_compose restart php-fpm-mailcow >/dev/null 2>&1; then
        mail_info "php-fpm-mailcow redémarré"
    else
        mail_warn "redémarrage de php-fpm-mailcow impossible ; relancez make mail-up."
    fi
else
    mail_info "mailcow arrêté : la correction sera active au démarrage."
fi
