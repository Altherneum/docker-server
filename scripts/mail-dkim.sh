#!/bin/sh
# =============================================================================
# mail-dkim.sh - crée ou importe la clé DKIM de mailcow pour le domaine.
#
# Un seul domaine (DOMAIN) et une seule clé DKIM : toutes les adresses du
# domaine (contact@, admin@, ...) utilisent la même clé.
#
# MAIL_CREATE_KEYS=yes : nouvelle paire RSA 2048, écrite dans Redis, TXT affiché.
# MAIL_CREATE_KEYS=no  : importe MAIL_DKIM_PRIVATE_KEY_FILE (ou la clé inline),
#                        ou conserve la clé déjà présente dans Redis.
# --generate force la génération d'une nouvelle clé (utilisé par mail-setup
#            quand aucune clé n'est disponible).
#
# Aucune action dans l'interface mailcow : les clés sont écrites dans les hashs
# Redis utilisés par rspamd (DKIM_PRIV_KEYS, DKIM_PUB_KEYS, DKIM_SELECTORS).
#
# Usage : ./scripts/mail-dkim.sh [--generate]
# =============================================================================
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MAIL_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/mail-lib.sh"
mail_load_env "$MAIL_ROOT"

force_generate=0
case "${1:-}" in
    '') ;;
    --generate) force_generate=1 ;;
    *) mail_die "option inconnue : $1 (utilisez --generate)" ;;
esac

[ -d "$MAILCOW_DIR" ] || mail_die "mailcow n'est pas installé dans $MAILCOW_DIR."
[ -f "$MAILCOW_CONF" ] || mail_die "$MAILCOW_CONF introuvable."
command -v openssl >/dev/null 2>&1 || mail_die "openssl est requis."
command -v docker >/dev/null 2>&1 || mail_die "docker est requis."

domain=$DOMAIN
mail_domain_valid "$domain" || mail_die "DOMAIN invalide : $domain (renseignez DOMAIN_NAME et TLD dans .env)"

REDISPASS=$(mailcow_get REDISPASS)
[ -n "$REDISPASS" ] || mail_die "REDISPASS introuvable dans mailcow.conf."

mailcow_hostname=$(mailcow_get MAILCOW_HOSTNAME)
[ -n "$mailcow_hostname" ] || mailcow_hostname="mail.$domain"

mailcow_service_running redis-mailcow || mail_die "redis-mailcow ne tourne pas. Lancez : sudo make mail-setup"
if ! mail_redis_cmd PING >/dev/null 2>&1; then
    mail_die "Redis mailcow refuse la connexion (REDISPASS incorrect ?)."
fi

selector=$(env_get MAIL_DKIM_SELECTOR)
[ -n "$selector" ] || selector=dkim
case "$selector" in
    *[!A-Za-z0-9._-]*) mail_die "MAIL_DKIM_SELECTOR invalide : $selector" ;;
esac

create_keys=$(env_get MAIL_CREATE_KEYS)
create_keys=$(printf '%s' "$create_keys" | tr '[:upper:]' '[:lower:]')
case "$create_keys" in
    '') create_keys=no ;;
    yes|no) ;;
    *) mail_die "MAIL_CREATE_KEYS doit valoir yes ou no (valeur : $create_keys)." ;;
esac
if [ "$force_generate" -eq 1 ]; then
    create_keys=yes
fi

# --- Clé privée à importer (mode no) --------------------------------------
import_key=$(env_get MAIL_DKIM_PRIVATE_KEY_FILE)
inline_key=$(env_get MAIL_DKIM_PRIVATE_KEY)

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mail-dkim.XXXXXX")
trap 'rm -rf "$TMP_DIR"' 0 1 2 15
umask 077

if [ -n "$import_key" ]; then
    case "$import_key" in
        "~/"*) import_key="$HOME/${import_key#~/}" ;;
        /*) ;;
        *) import_key="$MAIL_ROOT/$import_key" ;;
    esac
    [ -f "$import_key" ] || mail_die "MAIL_DKIM_PRIVATE_KEY_FILE introuvable : $import_key"
    [ -r "$import_key" ] || mail_die "MAIL_DKIM_PRIVATE_KEY_FILE illisible : $import_key"
    cp "$import_key" "$TMP_DIR/imported.pem"
    import_key="$TMP_DIR/imported.pem"
elif [ -n "$inline_key" ]; then
    printf '%b' "$inline_key" > "$TMP_DIR/imported.pem"
    import_key="$TMP_DIR/imported.pem"
fi

# Normalise les fins de ligne (clé copiée depuis Windows).
if [ -n "$import_key" ]; then
    sed -i 's/\r$//' "$import_key"
fi

if [ "$create_keys" = "yes" ] && [ -n "$import_key" ]; then
    mail_warn "génération d'une nouvelle clé demandée : la clé fournie dans .env est ignorée."
    import_key=""
fi
if [ "$create_keys" = "no" ] && [ -z "$import_key" ]; then
    mail_info "aucune clé fournie : la clé déjà présente dans Redis est conservée."
fi

# --- Dossier de sauvegarde ------------------------------------------------
timestamp=$(date +%Y%m%d-%H%M%S)
OUT_DIR="$BACKUP_DIR/mail-dkim-$timestamp-$$"
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
trap 'rm -rf "$TMP_DIR"; mail_chown_user "$OUT_DIR"; mail_chown_user "$ENV_FILE"' 0 1 2 15

DNS_FILE="$OUT_DIR/dns-records.txt"
PRIV_FILE="$OUT_DIR/private-keys.pem"
OLD_DNS_FILE="$OUT_DIR/old-dns-records.txt"
OLD_PRIV_FILE="$OUT_DIR/old-private-keys.pem"
: > "$DNS_FILE"
: > "$PRIV_FILE"
: > "$OLD_DNS_FILE"
: > "$OLD_PRIV_FILE"
chmod 644 "$DNS_FILE" "$OLD_DNS_FILE"
chmod 600 "$PRIV_FILE" "$OLD_PRIV_FILE"

# --- Création du domaine via l'API ----------------------------------------
if mail_api_available; then
    mail_api_add_domain "$domain" || mail_warn "impossible de créer/vérifier $domain via l'API mailcow."
else
    mail_warn "API mailcow indisponible (clé absente ou php-fpm arrêté) : créez le domaine $domain dans l'interface."
fi

cat >> "$DNS_FILE" <<EOF
# Clé DKIM mailcow - $domain - $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Sélecteur configuré : $selector (un sélecteur existant peut être conservé)
#
# Une seule clé DKIM couvre toutes les adresses du domaine :
# contact@$domain, admin@$domain, etc. Les boîtes se créent dans l'interface
# mailcow ; elles n'ont pas besoin d'une clé DKIM chacune.
#
# Publiez la ligne TXT ci-dessous dans la zone DNS du domaine.
# La valeur brute et la version découpée en chaînes de 255 caractères sont
# fournies : utilisez celle que votre panneau DNS accepte.
# =============================================================================
EOF

cat >> "$OLD_DNS_FILE" <<EOF
# Ancienne clé DKIM - sauvegarde avant modification
# =============================================================================
EOF

# --- Sauvegarde de l'ancienne clé -----------------------------------------
old_selector=$(mail_redis_cmd HGET DKIM_SELECTORS "$domain" 2>/dev/null | tr -d '\r' || true)
[ -n "$old_selector" ] || old_selector=$selector
old_priv=$(mail_redis_cmd HGET DKIM_PRIV_KEYS "$old_selector.$domain" 2>/dev/null || true)
old_pub=$(mail_redis_cmd HGET DKIM_PUB_KEYS "$domain" 2>/dev/null || true)

if [ -n "$old_priv" ]; then
    {
        printf '### %s (selector %s)\n' "$domain" "$old_selector"
        printf '%s\n' "$old_priv"
    } >> "$OLD_PRIV_FILE"
fi
if [ -n "$old_pub" ]; then
    {
        printf '### %s (selector %s)\n' "$domain" "$old_selector"
        printf '%s._domainkey.%s. IN TXT "v=DKIM1;k=rsa;t=s;s=email;p=%s"\n\n' "$old_selector" "$domain" "$old_pub"
    } >> "$OLD_DNS_FILE"
fi

# Découpe une valeur TXT en chaînes de 255 caractères.
split_txt() {
    printf '%s' "$1" | awk '{
        s = $0
        out = ""
        while (length(s) > 0) {
            out = out (out == "" ? "" : " ") "\"" substr(s, 1, 255) "\""
            s = substr(s, 256)
        }
        print out
    }'
}

# --- Choix de la clé -------------------------------------------------------
key_file=""
domain_selector=$selector

if [ "$create_keys" = "yes" ]; then
    key_file="$TMP_DIR/$domain.key"
    openssl genrsa -out "$key_file" 2048 2>/dev/null || mail_die "génération de clé impossible pour $domain"
    action="nouvelle clé générée"
elif [ -n "$import_key" ]; then
    key_file="$import_key"
    action="clé importée"
else
    existing=""
    # En mode conservation, garde le sélecteur déjà utilisé par le domaine :
    # c'est lui qui correspond au TXT DNS existant.
    current_selector=$(mail_redis_cmd HGET DKIM_SELECTORS "$domain" 2>/dev/null | tr -d '\r' || true)
    if [ -n "$current_selector" ]; then
        existing=$(mail_redis_cmd HGET DKIM_PRIV_KEYS "$current_selector.$domain" 2>/dev/null || true)
        if [ -n "$existing" ]; then
            domain_selector=$current_selector
            if [ "$current_selector" != "$selector" ]; then
                mail_info "sélecteur existant $current_selector conservé pour $domain"
            fi
        fi
    fi
    if [ -z "$existing" ]; then
        existing=$(mail_redis_cmd HGET DKIM_PRIV_KEYS "$selector.$domain" 2>/dev/null || true)
    fi
    [ -n "$existing" ] || mail_die "aucune clé DKIM existante pour $domain et aucune clé fournie. Lancez sudo make mail-setup (génération automatique), passez MAIL_CREATE_KEYS=yes, ou fournissez MAIL_DKIM_PRIVATE_KEY_FILE."
    key_file="$TMP_DIR/$domain.existing.pem"
    printf '%s\n' "$existing" > "$key_file"
    sed -i 's/\r$//' "$key_file"
    chmod 600 "$key_file"
    action="clé existante conservée"
fi

pub_file="$TMP_DIR/$domain.pub"
if ! openssl pkey -in "$key_file" -pubout -out "$pub_file" 2>/dev/null; then
    mail_die "clé privée invalide pour $domain : $key_file"
fi

priv_pem=$(cat "$key_file")
pub_b64=$(sed -e '1d' -e '$d' "$pub_file" | tr -d '\r\n')
[ -n "$pub_b64" ] || mail_die "clé publique vide pour $domain"

if ! printf '%s' "$priv_pem" | mail_redis_set DKIM_PRIV_KEYS "$domain_selector.$domain"; then
    mail_die "écriture Redis DKIM_PRIV_KEYS impossible pour $domain"
fi
if ! printf '%s' "$pub_b64" | mail_redis_set DKIM_PUB_KEYS "$domain"; then
    mail_die "écriture Redis DKIM_PUB_KEYS impossible pour $domain"
fi
if ! printf '%s' "$domain_selector" | mail_redis_set DKIM_SELECTORS "$domain"; then
    mail_die "écriture Redis DKIM_SELECTORS impossible pour $domain"
fi

# Une nouvelle clé est active : l'ancienne clé importée ne doit pas être
# réimportée par erreur au prochain make mail-dkim.
if [ "$create_keys" = "yes" ]; then
    env_set MAIL_CREATE_KEYS no
    env_set MAIL_DKIM_PRIVATE_KEY_FILE ""
    env_set MAIL_DKIM_PRIVATE_KEY ""
fi

txt_value="v=DKIM1;k=rsa;t=s;s=email;p=$pub_b64"
chunked=$(split_txt "$txt_value")

{
    printf '### %s (selector %s) - %s\n' "$domain" "$domain_selector" "$action"
    printf '# Nom    : %s._domainkey.%s\n' "$domain_selector" "$domain"
    printf '# Valeur : %s\n' "$txt_value"
    printf '# Découpé: %s\n' "$chunked"
    printf '%s._domainkey.%s. IN TXT %s\n\n' "$domain_selector" "$domain" "$chunked"
} >> "$DNS_FILE"

{
    printf '### %s (selector %s)\n' "$domain" "$domain_selector"
    printf '%s\n' "$priv_pem"
} >> "$PRIV_FILE"

{
    printf '### %s - enregistrements à conserver/adapter\n' "$domain"
    printf '# SPF   : @ IN TXT "v=spf1 mx ~all"\n'
    printf '# DMARC : _dmarc IN TXT "v=DMARC1; p=quarantine; rua=mailto:postmaster@%s"\n' "$domain"
    printf '# MX    : @ IN MX 10 %s.\n' "$mailcow_hostname"
    printf '# A     : %s IN A <IP_DU_SERVEUR>\n' "$mailcow_hostname"
    printf '# PTR   : <IP_DU_SERVEUR> -> %s\n\n' "$mailcow_hostname"
} >> "$DNS_FILE"

printf '\n[%s] %s\n' "$domain" "$action"
printf '  Nom    : %s._domainkey.%s\n' "$domain_selector" "$domain"
printf '  Valeur : %s\n' "$txt_value"
printf '  Découpé: %s\n' "$chunked"

# Recharge rspamd seulement si une clé a réellement changé : inutile de
# couper le filtrage à chaque make mail-setup quand la clé est conservée.
keys_changed=0
[ "$old_priv" = "$priv_pem" ] || keys_changed=1
[ "$old_pub" = "$pub_b64" ] || keys_changed=1
[ "$old_selector" = "$domain_selector" ] || keys_changed=1

if [ "$keys_changed" -eq 0 ]; then
    mail_info "clé DKIM inchangée : rspamd-mailcow non redémarré"
elif mailcow_service_running rspamd-mailcow; then
    if mailcow_compose restart rspamd-mailcow >/dev/null 2>&1; then
        mail_info "rspamd-mailcow redémarré"
    else
        mail_warn "redémarrage de rspamd-mailcow impossible ; relancez-le manuellement."
    fi
fi

printf '\n'
mail_info "fichiers écrits dans $OUT_DIR"
printf '  - %s (public, à copier dans le DNS)\n' "$DNS_FILE"
printf '  - %s (privé, permissions 600)\n' "$PRIV_FILE"
printf '  - modèles SPF/DMARC/MX/A/PTR à la fin de %s\n' "$DNS_FILE"
if [ -s "$OLD_PRIV_FILE" ]; then
    printf '  - %s (ancienne clé, pour revenir en arrière)\n' "$OLD_PRIV_FILE"
fi
if [ -s "$OLD_DNS_FILE" ] && [ "$(wc -l < "$OLD_DNS_FILE")" -gt 2 ]; then
    printf '  - %s (ancien TXT)\n' "$OLD_DNS_FILE"
fi
printf '\n'

if [ "$create_keys" = "yes" ]; then
    printf "Important : le nouveau TXT DKIM doit remplacer l'ancien dans le DNS.\n"
    printf "Tant que la propagation n'est pas terminée, les messages sortants\n"
    printf 'peuvent échouer la vérification DKIM.\n'
else
    printf 'Le DNS DKIM ne change pas : la clé privée correspond au TXT existant.\n'
fi

mail_chown_user "$OUT_DIR"
