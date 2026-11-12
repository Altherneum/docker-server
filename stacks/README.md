# Dossier `stacks`

Chaque dossier de service contient une stack Docker Compose indépendante. Le
fichier `compose.yaml` à la racine les inclut toutes. Le dossier `mail` contient
seulement le modèle d'intégration de Mailcow, qui est une stack externe.

| Dossier | Services | Fiche |
|---|---|---|
| `proxy` | `traefik` | [Traefik](../docs/services/traefik.md) |
| `web/php-site` | `php-site`, `db-php` | [Site PHP](../docs/services/php-site.md) |
| `web/azuriom` | `azuriom`, `db-azuriom` | [Azuriom](../docs/services/azuriom.md) |
| `web/keeweb` | `keeweb` | [KeeWeb](../docs/services/keeweb.md) |
| `web/nextcloud` | `nextcloud`, `nextcloud-cron`, `nextcloud-redis`, `db-nextcloud` | [Nextcloud](../docs/services/nextcloud.md) |
| `web/phpmyadmin` | `phpmyadmin` | [phpMyAdmin](../docs/services/phpmyadmin.md) |
| `web/meme` | `meme` | [Meme](../docs/services/meme.md) |
| `forgejo` | `forgejo`, `db-forgejo` | [Forgejo](../docs/services/forgejo.md) |
| `code-server` | `code-server` | [code-server](../docs/services/code-server.md) |
| `dockhand` | `dockhand` | [Dockhand](../docs/services/dockhand.md) |
| `uptime-kuma` | `uptime-kuma`, `uptime-kuma-docker-proxy` | [Uptime Kuma](../docs/services/uptime-kuma.md) |
| `minecraft` | `velocity`, `mc-*` | [Minecraft](../docs/services/minecraft.md) |
| `discord` | `bot` | [Bot Discord](../docs/services/discord-bot.md) |
| `fail2ban` | `fail2ban` | [fail2ban](../docs/services/fail2ban.md) |
| `mail` | stack Mailcow externe | [Mailcow](../docs/services/mailcow.md) |

Lancer une stack seule :

```sh
docker compose --env-file .env -f stacks/<dossier>/compose.yaml up -d --build
```

Mais les commandes `make` sont préférables, car elles créent les réseaux et les
images de base si nécessaire. Voir
[Commandes](../docs/03-commandes.md).
