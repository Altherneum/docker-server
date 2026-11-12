# Images de base

**Rôle :** images Docker communes construites localement et utilisées par
plusieurs services. Elles n'ont ni URL ni mot de passe.

| Image | Dossier | Utilisée par |
|---|---|---|
| `php-apache:latest` | `images/php-apache` | Site PHP, Azuriom |
| `mariadb:11.8` | `images/mariadb` | `db-php`, `db-azuriom`, `db-nextcloud` |
| `postgres:18` | `images/postgres` | `db-forgejo` |
| `paper:1.21.11` | `stacks/minecraft/paper` | Serveurs Paper |

L'image Paper embarque aussi les cartes de départ
(`stacks/minecraft/paper/maps`) et l'entrypoint qui les installe dans le volume
du serveur.

## Construire les images

```sh
sudo make base          # construit toutes les images de base
sudo make ensure-base   # construit seulement celles qui manquent
```

Ou individuellement :

```sh
sudo make php-base
sudo make mariadb-base
sudo make postgres-base
sudo make paper-base
```

## Construire aussi les services

```sh
sudo make build
```

`make build` construit d'abord les images de base, puis toutes les images des
stacks (`php-site`, `azuriom`, `forgejo`, `code-server`, `keeweb`, `meme`,
`phpmyadmin`, `velocity`, `bot`, `fail2ban`).

## Quand reconstruire ?

| Modification | Commande |
|---|---|
| Un `Dockerfile` de `images/` | `sudo make base` |
| Un `Dockerfile` d'une stack | `sudo make build` |
| Une carte Minecraft dans `stacks/minecraft/paper/maps` | `sudo make paper-base` |
| `compose.yaml` seulement | `sudo make up-service SERVICE=nom` |

Après une reconstruction, redémarrez les services concernés :

```sh
sudo make up
```

## Bon à savoir

- Les services utilisent `ensure-base` : si une image de base manque, elle est
  construite automatiquement au démarrage.
- Une mise à jour de l'image de base ne met pas à jour les conteneurs déjà
  créés : il faut reconstruire et recréer les services.
- Les autres stacks sont construites à partir d'images officielles (Traefik,
  Forgejo, code-server, phpMyAdmin, KeeWeb, Nextcloud, Redis, fail2ban)
  téléchargées depuis leurs registres respectifs.
