#!/bin/sh
# =============================================================================
# mail-cert-timer.sh - installe le timer systemd qui synchronise le certificat
# Traefik vers mailcow (SMTP/IMAP) une fois par jour.
#
# Le service lance mail-cert-sync.sh --quiet. Traefik renouvelle le certificat
# environ 30 jours avant expiration : la copie quotidienne suit le renouvellement
# sans aucune action manuelle.
#
# Usage : sudo ./scripts/mail-cert-timer.sh
# =============================================================================
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MAIL_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/mail-lib.sh"

[ "$(id -u)" -eq 0 ] || mail_die "lancez avec sudo (installation d'un service systemd)."
command -v systemctl >/dev/null 2>&1 || mail_die "systemctl introuvable."
[ -d /run/systemd/system ] || mail_die "systemd n'est pas actif sur cette machine."
command -v docker >/dev/null 2>&1 || mail_die "docker est requis."
command -v python3 >/dev/null 2>&1 || mail_die "python3 est requis (lecture d'acme.json)."
command -v openssl >/dev/null 2>&1 || mail_die "openssl est requis."

sync_script="$MAIL_ROOT/scripts/mail-cert-sync.sh"
[ -x "$sync_script" ] || mail_die "$sync_script introuvable ou non exécutable."

unit_dir=/etc/systemd/system
service_file="$unit_dir/mail-cert-sync.service"
timer_file="$unit_dir/mail-cert-sync.timer"

cat > "$service_file" <<EOF
[Unit]
Description=Synchronise le certificat Traefik vers mailcow (SMTP/IMAP)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=$sync_script --quiet
EOF

cat > "$timer_file" <<'EOF'
[Unit]
Description=Synchronisation quotidienne du certificat Traefik vers mailcow

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

chmod 644 "$service_file" "$timer_file"
systemctl daemon-reload
systemctl enable --now mail-cert-sync.timer >/dev/null

mail_info "timer systemd installé : mail-cert-sync.timer (quotidien)"
printf '  Service : %s\n' "$service_file"
printf '  Forcer   : sudo systemctl start mail-cert-sync.service\n'
printf '  Vérifier : systemctl list-timers mail-cert-sync.timer\n'
