#!/bin/sh
# =============================================================================
# mail-webmail-url.sh - rétablit le flux webmail prévu par mailcow.
#
# Mailcow se connecte via l'interface (/ ou /user), puis ouvre /SOGo/so/ en
# SSO. La page /SOGo/ redirige vers /user via data/conf/sogo/custom-sogo.js.
# Ce script répare ces fichiers si un ancien patch les a modifiés.
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

# Liens de l'UI mailcow vers /SOGo/so (SSO prévu par mailcow).
replace "$web_dir/inc/vars.inc.php" "'/SOGo/'" "'/SOGo/so'"

# Redirections après connexion / changement de mot de passe.
replace "$web_dir/index.php" 'Location: /SOGo/")' 'Location: /SOGo/so/")'
replace "$web_dir/inc/triggers.user.inc.php" 'Location: /SOGo/")' 'Location: /SOGo/so/")'

# La page de login SOGo redirige vers l'UI mailcow (/user), comme prévu.
sogo_js="$MAILCOW_DIR/data/conf/sogo/custom-sogo.js"
replace "$sogo_js" "        // window.location.href = '/user'; // login SOGo direct" "        window.location.href = '/user';"

# Évite l'erreur console « CKEDITOR is not defined » sur la page de login.
if [ -f "$sogo_js" ] && grep -Eq '^CKEDITOR\.addCss' "$sogo_js"; then
    if sed -i 's|^CKEDITOR\.addCss.*|if (typeof CKEDITOR !== "undefined") { CKEDITOR.addCss("body {font-size: 16px !important}"); }|' "$sogo_js" 2>/dev/null; then
        changed=1
        mail_info "corrigé : $sogo_js"
    else
        mail_warn "impossible de modifier $sogo_js (droits root ? relancez avec sudo)."
    fi
fi

if [ "$changed" -eq 0 ]; then
    mail_info "flux webmail mailcow déjà conforme"
    exit 0
fi

if mailcow_service_running php-fpm-mailcow; then
    if mailcow_compose restart php-fpm-mailcow >/dev/null 2>&1; then
        mail_info "php-fpm-mailcow redémarré"
    else
        mail_warn "redémarrage de php-fpm-mailcow impossible ; relancez make mail-up."
    fi
fi
if mailcow_service_running sogo-mailcow; then
    if mailcow_compose restart sogo-mailcow >/dev/null 2>&1; then
        mail_info "sogo-mailcow redémarré"
    else
        mail_warn "redémarrage de sogo-mailcow impossible ; relancez make mail-up."
    fi
fi
