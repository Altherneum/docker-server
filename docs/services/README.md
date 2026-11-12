# Fiches par service

Chaque fiche décrit un service : son rôle, son adresse, les variables `.env`
nécessaires, les mots de passe, et les commandes pour démarrer, arrêter et
nettoyer.

Les adresses utilisent `supername.fr` comme exemple. Remplacez-le par
`<DOMAIN_NAME><TLD>` de votre `.env`. Voir
[Accès et URL](../04-acces-et-urls.md).

## Index

| Service | Conteneur(s) | Adresse | Mot de passe principal |
|---|---|---|---|
| [Traefik](traefik.md) | `traefik` | `https://traefik.<domaine>` | `TRAEFIK_DASHBOARD_PASSWORD` |
| [Site PHP](php-site.md) | `php-site`, `db-php` | `https://php.<domaine>` | `WEBSITE_ADMIN_PASSWORD` |
| [Azuriom](azuriom.md) | `azuriom`, `db-azuriom` | `https://minecraft.<domaine>` | `AZURIOM_ADMIN_PASSWORD` |
| [Forgejo](forgejo.md) | `forgejo`, `db-forgejo` | `https://git.<domaine>` | `FORGEJO_HTTP_PASSWORD` puis `FORGEJO_ADMIN_PASSWORD` |
| [code-server](code-server.md) | `code-server` | `https://code.<domaine>` | `CODE_SERVER_HTTP_PASSWORD` puis `CODE_SERVER_PASSWORD` |
| [KeeWeb](keeweb.md) | `keeweb` | `https://keeweb.<domaine>` | `KEEWEB_UI_PASSWORD` |
| [Nextcloud](nextcloud.md) | `nextcloud`, `nextcloud-cron`, `nextcloud-redis`, `db-nextcloud` | `https://cloud.<domaine>` | `NEXTCLOUD_ADMIN_PASSWORD` |
| [Dockhand](dockhand.md) | `dockhand` | `https://dockhand.<domaine>` | `DOCKHAND_HTTP_PASSWORD` puis compte Dockhand |
| [Uptime Kuma](uptime-kuma.md) | `uptime-kuma`, `uptime-kuma-docker-proxy` | `https://status.<domaine>` | `UPTIME_KUMA_ADMIN_PASSWORD` |
| [phpMyAdmin](phpmyadmin.md) | `phpmyadmin` | `https://phpmyadmin.<domaine>` | `PMA_ADMIN_PASSWORD` puis compte MariaDB |
| [Meme](meme.md) | `meme` | `https://meme.<domaine>` | *(aucun)* |
| [Minecraft](minecraft.md) | `velocity`, `mc-*` | `mc.<domaine>:25565` | *(aucun pour jouer)* |
| [Bot Discord](discord-bot.md) | `discord-bot` | *(pas d'URL)* | `DISCORD_BOT_TOKEN` |
| [fail2ban](fail2ban.md) | `fail2ban` | *(pas d'URL)* | *(aucun)* |
| [Mailcow](mailcow.md) | stack externe | `https://mail.<domaine>` | Compte mailcow |
| [Bases de données](databases.md) | `db-php`, `db-azuriom`, `db-nextcloud`, `db-forgejo` | *(accès interne)* | `*_DB_PASSWORD` |
| [Images de base](base-images.md) | *(images Docker)* | *(pas d'URL)* | *(aucun)* |

## Rappel des commandes

```sh
sudo make up-service SERVICE=nom
sudo make stop SERVICE=nom
sudo make restart-service SERVICE=nom
sudo make logs-service SERVICE=nom
sudo make ps-service SERVICE=nom
sudo CONFIRM=yes make clean-service SERVICE=nom   # DESTRUCTIF
```
