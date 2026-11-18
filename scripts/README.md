# Dossier `scripts`

Scripts appelés par le `Makefile`. Vous n'avez normalement pas besoin de les
lancer directement : utilisez les commandes `make` documentées dans
[`docs/03-commandes.md`](../docs/03-commandes.md).

| Script | Commande `make` | Rôle |
|---|---|---|
| `init.sh` | `make init` | Crée `.env`, les secrets, les htpasswd et les réseaux |
| `check-env.sh` | `make check-env` | Vérifie que `.env` contient les variables de base |
| `ensure-networks.sh` | `make ensure-networks` | Crée les réseaux Docker externes manquants |
| `ensure-auth.sh` | `make ensure-auth` | Génère les htpasswd manquants (appelé automatiquement par `up` / `up-service`) |
| `php-site-src.sh` | `make php-site-src` / `php-site-env` | Clone ou met à jour le site PHP et génère son `.env` |
| `forgejo-admin.sh` | `make forgejo-admin` | Crée le compte admin Forgejo (appelé automatiquement par `up` / `up-service`) |
| `forgejo-runner.sh` | `make forgejo-runner` | Vérifie que le runner Forgejo Actions est enregistré et en ligne (appelé automatiquement par `up` / `up-service`) |
| `forgejo-github-mirror.sh` | `make forgejo-mirror` | Importe les dépôts GitHub dans Forgejo, configure le miroir push et démarre la CI des dépôts importés (appelé automatiquement par `up` / `up-service`) ; sans `GITHUB_TOKEN`, code Git seul pour éviter le quota GitHub |
| `uptime-kuma-admin.sh` | `make uptime-kuma-admin` | Crée le compte admin Uptime Kuma via Socket.IO (appelé automatiquement par `up` / `up-service`) |
| `uptime-kuma-docker-sync.sh` | `make uptime-kuma-docker-sync` | Ajoute l'hôte Docker, les moniteurs de conteneurs manquants et la notification Discord via Socket.IO (appelé automatiquement par `up` / `up-service` si Uptime Kuma tourne) |
| `dockhand-local-env.sh` | `make dockhand-local-env` | Enregistre l'environnement Docker local `/var/run/docker.sock` dans Dockhand (appelé automatiquement par `up` / `up-service` si `DOCKHAND_AUTO_LOCAL_ENV=true`) |
| `dockhand-notifications.sh` | `make dockhand-notifications` | Crée ou met à jour le canal de notifications, active tous les événements et l'attache à l'environnement local (appelé automatiquement par `up` / `up-service` si `DOCKHAND_AUTO_NOTIFICATIONS=true`) |
| `mail-install.sh` | `make mail-install` | Clone et configure Mailcow si absent |
| `mail-setup.sh` | `make mail-setup` | Installe, démarre et configure Mailcow en une commande |
| `mail-integrate.sh` | `make mail-integrate` | Prépare l'override Traefik, le réseau et la clé API de Mailcow |
| `mail-webmail-url.sh` | `make mail-webmail-url` | Rétablit le flux webmail Mailcow (UI → `/SOGo/so`, appelé par `mail-integrate`) |
| `mail-check.sh` | `make mail-check` | Vérifie Docker, le réseau, les ports et l'override Mailcow |
| `mail-cert-sync.sh` | `make mail-cert-sync` | Copie le certificat Let's Encrypt de Traefik vers Mailcow (SMTP/IMAP) |
| `mail-cert-timer.sh` | `make mail-cert-timer` | Installe le timer systemd quotidien de synchro du certificat |
| `mail-dkim.sh` | `make mail-dkim` | Crée ou importe la clé DKIM du domaine et affiche le TXT DNS |
| `mail-dkim-key.sh` | `make mail-dkim-key` | Pré-génère la clé DKIM avant l'installation de Mailcow |
| `mail-mailboxes.sh` | `make mail-mailboxes` | Crée les boîtes mail de base via l'API Mailcow |
| `mail-lib.sh` | *(interne)* | Fonctions communes aux scripts Mailcow |
| `backup.sh` | `make backup` | Sauvegarde les bases et les volumes |
| `restore.sh` | `make restore` | Restaure une sauvegarde |
| `clean-service.sh` | `make clean-service` | Supprime un service, ses volumes exclusifs et son code monté |
| `net-diag.sh` | `make net-diag` | Diagnostique les ports, UFW, iptables et IPv4/IPv6 (lecture seule) |

Documentation détaillée :

- [Installation](../docs/01-installation.md)
- [Sauvegarde et restauration](../docs/05-backup-restore.md)
- [Dépannage](../docs/06-depannage.md)
