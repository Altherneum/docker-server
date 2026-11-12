# Configuration `.env`

Le fichier `.env` contient la configuration et les mots de passe. Il est créé à
partir de `.env.example` par `sudo make init`.

## Règles importantes

- `.env` ne doit **jamais** être commité ni partagé.
- `make init` ne remplace pas une valeur déjà remplie. Il ne remplit que les
  valeurs vides ou égales à `CHANGE_ME`.
- `make init` régénère aussi les fichiers `.htpasswd` à partir de `.env`.
- Après une modification, redémarrez le service concerné.

## Variables principales

| Variable | Rôle | Exemple |
|---|---|---|
| `DOMAIN_NAME` | Nom sans extension | `monprojet` |
| `TLD` | Extension avec le point | `.com` |
| `DOMAIN` | Calculé automatiquement ; nom d'hôte et prompt | `monprojet.com` |
| `TZ` | Fuseau horaire | `Europe/Paris` |
| `BOT_URL` | URL du jar du bot Discord (obligatoire) | `<URL_DU_JAR>` |
| `ACME_EMAIL` | E-mail Let's Encrypt | `admin@monprojet.com` |
| `MAILCOW_DIR` | Dossier de mailcow | `/opt/mailcow-dockerized` |
| `PROXY_NETWORK` | Réseau Docker de Traefik | `monprojet_proxy` |
| `DB_ADMIN_NETWORK` | Réseau d'administration des bases | `monprojet_db_admin` |
| `MINECRAFT_NETWORK` | Réseau interne Minecraft | `monprojet_minecraft_internal` |

## Valeurs à renseigner à la main

Ces valeurs ne peuvent pas être générées automatiquement :

| Variable | Obligatoire ? | Où la trouver |
|---|---|---|
| `DISCORD_BOT_TOKEN` | Oui pour le bot | Portail développeur Discord |
| `MINECRAFT_DISCORD_TOKEN_*` | Non | Portail développeur Discord (un bot par serveur Minecraft) |
| `AZURIOM_ADMIN_GAME_ID` | Oui en mode `mc-online` | UUID Minecraft du compte admin, sans tirets |
| `WEBSITE_DISCORD_CLIENT_ID` | Non | Application Discord OAuth |
| `WEBSITE_DISCORD_CLIENT_SECRET` | Non | Application Discord OAuth |
| `MICROSOFT_CLIENT_ID` | Non | Microsoft Entra ID |
| `MICROSOFT_CLIENT_SECRET` | Non | Microsoft Entra ID |
| `NEXTCLOUD_MAIL_HOST` | Non | Hôte SMTP de mailcow ; vide = e-mails Nextcloud désactivés |
| `UPTIME_KUMA_DISCORD_WEBHOOK_URL` | Non | Discord : paramètres du serveur > intégrations > webhooks |

## Nextcloud

| Variable | Rôle | Exemple |
|---|---|---|
| `NEXTCLOUD_VERSION` | Version majeure de l'image officielle | `35` |
| `NEXTCLOUD_REDIS_VERSION` | Image Redis | `8-alpine` |
| `NEXTCLOUD_ADMIN_USER` | Compte administrateur | `admin` |
| `NEXTCLOUD_ADMIN_EMAIL` | E-mail de l'administrateur | `admin@monprojet.com` |
| `NEXTCLOUD_TRUSTED_PROXIES` | Proxies de confiance Docker | `172.16.0.0/12 10.0.0.0/8 192.168.0.0/16` |
| `NEXTCLOUD_PHP_UPLOAD_LIMIT` | Taille maximale d'un fichier | `10G` |
| `NEXTCLOUD_MAIL_HOST` | Hôte SMTP ; vide = e-mails désactivés | `mail.monprojet.com` |
| `NEXTCLOUD_MAIL_USERNAME` | Boîte d'envoi | `cloud@monprojet.com` |

Nextcloud ne peut être mis à jour que d'**une version majeure à la fois**.
Changez `NEXTCLOUD_VERSION`, puis `sudo make up-service SERVICE=nextcloud`.
Voir la [fiche Nextcloud](services/nextcloud.md#mettre-à-jour-nextcloud).

## Dockhand

| Variable | Rôle | Exemple |
|---|---|---|
| `DOCKHAND_VERSION` | Version de l'image, avec le préfixe `v` | `v1.0.57` |
| `DOCKHAND_PUID` / `DOCKHAND_PGID` | UID/GID internes du conteneur | `1001` |
| `DOCKHAND_ENCRYPTION_KEY` | Clé de chiffrement des identifiants Dockhand | générée par `make init` |
| `DOCKHAND_HTTP_USER` | Compte de la protection Traefik | `dockhand` |
| `DOCKHAND_HTTP_PASSWORD` | Mot de passe de la protection Traefik | généré par `make init` |
| `DOCKHAND_AUTO_LOCAL_ENV` | Enregistre automatiquement l'environnement Docker local | `true` |

La clé `DOCKHAND_ENCRYPTION_KEY` ne doit pas être modifiée après le premier
démarrage : elle déchiffre les identifiants et secrets stockés par Dockhand.
Avec `DOCKHAND_AUTO_LOCAL_ENV=true`, `make up` et
`make up-service SERVICE=dockhand` créent l'environnement `local` sur
`/var/run/docker.sock` s'il n'existe pas encore. Voir la
[fiche Dockhand](services/dockhand.md).

## Uptime Kuma

| Variable | Rôle | Exemple |
|---|---|---|
| `UPTIME_KUMA_VERSION` | Version exacte de l'image Uptime Kuma | `2.5.10` |
| `UPTIME_KUMA_DOCKER_PROXY_VERSION` | Version du proxy Docker en lecture seule | `v0.5.0` |
| `UPTIME_KUMA_DB_TYPE` | Type de base ; SQLite incluse dans le volume | `sqlite` |
| `UPTIME_KUMA_ADMIN_USER` | Compte administrateur créé au premier démarrage | `admin` |
| `UPTIME_KUMA_ADMIN_PASSWORD` | Mot de passe du compte administrateur | généré par `make init` |
| `UPTIME_KUMA_DOCKER_SYNC` | Crée automatiquement les moniteurs Docker | `true` |
| `UPTIME_KUMA_DOCKER_HOST_NAME` | Nom de l'hôte Docker dans Uptime Kuma | `Local` |
| `UPTIME_KUMA_DOCKER_HOST_URL` | URL interne du proxy Docker | `http://uptime-kuma-docker-proxy:2375` |
| `UPTIME_KUMA_DOCKER_EXCLUDE` | Conteneurs exclus, séparés par des virgules | vide |
| `UPTIME_KUMA_DISCORD_ENABLED` | Active la configuration automatique de la notification Discord | `true` |
| `UPTIME_KUMA_DISCORD_WEBHOOK_URL` | URL du webhook Discord, à renseigner | vide |
| `UPTIME_KUMA_DISCORD_BOT_NAME` | Nom affiché du bot Discord | `Uptime Kuma` |
| `UPTIME_KUMA_DISCORD_PREFIX` | Préfixe des messages Discord | `[Uptime Kuma]` |
| `UPTIME_KUMA_DISCORD_NOTIFICATION_NAME` | Nom de la notification dans Uptime Kuma | `Discord` |
| `UPTIME_KUMA_DISCORD_DEFAULT` | Notification par défaut des nouveaux moniteurs | `true` |
| `UPTIME_KUMA_DISCORD_APPLY_EXISTING` | Applique la notification aux moniteurs existants | `true` |

Le compte admin est créé automatiquement par
`scripts/uptime-kuma-admin.sh`, appelé par `make up` et
`make up-service SERVICE=uptime-kuma`. Il n'y a pas de HTTP Basic Auth
Traefik : seul le login Uptime Kuma protège le dashboard.

`scripts/uptime-kuma-docker-sync.sh` utilise ce compte pour ajouter l'hôte
Docker, les moniteurs de conteneurs manquants et la notification Discord. Il
est appelé par `make up`, par `make up-service SERVICE=uptime-kuma`, et par les
autres `make up-service` lorsque Uptime Kuma tourne. Le webhook Discord est la
seule valeur à renseigner dans `.env` : le nom du bot, le préfixe et le nom de
la notification sont préconfigurés. Tant que le webhook est vide, aucune
notification Discord n'est créée. Si le mot de passe admin est changé dans
l'interface, reportez-le dans `UPTIME_KUMA_ADMIN_PASSWORD` pour ne pas casser
la synchronisation. Voir la [fiche Uptime Kuma](services/uptime-kuma.md).

## Import GitHub (Forgejo et code-server)

| Variable | Rôle | Exemple |
|---|---|---|
| `CODE_SERVER_GITHUB_ORG_URL`/`FORGEJO_GITHUB_ORG_URL` | Organisation GitHub à importer/cloner. Vide = désactivé. | `https://github.com/altherneum` |
| `GITHUB_TOKEN` | Jeton GitHub (scope `repo`). Requis pour les dépôts privés, les métadonnées et le miroir push. | `ghp_...` |
| `GITHUB_USER` | Identifiant associé au jeton. | `x-access-token` |
| `FORGEJO_OWNER` | Propriétaire Forgejo des dépôts importés. | `${FORGEJO_ADMIN_NAME}` |
| `FORGEJO_API_TOKEN` | Jeton API Forgejo optionnel pour les scripts. | vide |
| `FORGEJO_GITHUB_MIGRATE_METADATA` | Import complet (`auto`, `true`) ou code Git seul (`false`). | `auto` |
| `FORGEJO_GITHUB_MIGRATE_TIMEOUT` | Attente max de la migration en secondes (`0` = illimité). | `1800` |
| `FORGEJO_GITHUB_PUSH_MIRROR` | Crée un miroir push Forgejo → GitHub. | `true` |
| `FORGEJO_GITHUB_MIRROR_INTERVAL` | Fréquence de synchronisation du miroir. | `8h` |
| `FORGEJO_GITHUB_MIRROR_SYNC_ON_COMMIT` | Synchronise à chaque push reçu. | `true` |
| `CODE_SERVER_CLONE_GITHUB_ORG` | Clone les dépôts GitHub dans code-server. | `true` |
| `FORGEJO_INTERNAL_URL` | URL interne de Forgejo pour Git depuis code-server. | `http://forgejo:3000` |

Forgejo importe les dépôts, code-server les
clone dans son workspace. Sans `GITHUB_TOKEN`, seuls les dépôts publics sont
traités, l'import se limite au code Git (pas d'issues/PR/releases) et le miroir
push vers GitHub est désactivé. Avec `auto`, ajouter un jeton suffit à activer
l'import complet lors de la prochaine exécution.

## Forgejo Actions (CI/CD)

| Variable | Rôle | Exemple |
|---|---|---|
| `FORGEJO_RUNNER_VERSION` | Version de l'image du runner. | `13.2.1` |
| `FORGEJO_RUNNER_NAME` | Nom du runner dans Forgejo. | `forgejo-runner` |
| `FORGEJO_RUNNER_LABELS` | Labels `runs-on` (séparés par des virgules). | `ubuntu-latest:docker://...` |
| `FORGEJO_RUNNER_CAPACITY` | Jobs simultanés. | `2` |
| `FORGEJO_RUNNER_TIMEOUT` | Durée max d'un job. | `3h` |
| `FORGEJO_RUNNER_DOCKER_HOST` | `automount` pour Docker dans les jobs, `-` pour désactiver. | `automount` |
| `FORGEJO_ACTIONS_DEFAULT_URL` | Source des actions `uses:`. | `https://data.forgejo.org` |
| `DOCKER_GID` | GID du socket Docker, rempli par `make init`. | `960` |

Le runner est créé automatiquement au démarrage. Voir la fiche
[Forgejo](services/forgejo.md#forgejo-actions-cicd) pour les labels et les
workflows.

Pour obtenir l'UUID Minecraft d'un joueur :

```sh
curl -s https://api.mojang.com/users/profiles/minecraft/<pseudo>
```

Gardez les 32 caractères hexadécimaux, sans tirets.

## Comptes et mots de passe

| Service | Variables | Utilisation |
|---|---|---|
| Traefik | `TRAEFIK_DASHBOARD_USER`, `TRAEFIK_DASHBOARD_PASSWORD` | Connexion au tableau de bord |
| phpMyAdmin | `PMA_ADMIN_USER`, `PMA_ADMIN_PASSWORD` | Protection HTTP Basic, puis compte MariaDB sur la page de connexion |
| Site PHP | `WEBSITE_ADMIN_USERNAME`, `WEBSITE_ADMIN_PASSWORD` | Compte admin du site |
| Site PHP / base | `PHP_DB_ROOT_PASSWORD`, `PHP_DB_USER`, `PHP_DB_PASSWORD` | Base MariaDB |
| Azuriom | `AZURIOM_ADMIN_NAME`, `AZURIOM_ADMIN_PASSWORD` | Compte admin Azuriom |
| Azuriom / base | `AZURIOM_DB_ROOT_PASSWORD`, `AZURIOM_DB_USER`, `AZURIOM_DB_PASSWORD` | Base MariaDB |
| Azuriom / mail | `AZURIOM_MAIL_PASSWORD` | Boîte `noreply@` |
| Forgejo | `FORGEJO_ADMIN_NAME`, `FORGEJO_ADMIN_PASSWORD` | Compte admin Forgejo |
| Forgejo | `FORGEJO_HTTP_USER`, `FORGEJO_HTTP_PASSWORD` | Protection HTTP Basic par Traefik |
| Forgejo / base | `FORGEJO_DB_USER`, `FORGEJO_DB_PASSWORD` | Base PostgreSQL |
| Forgejo / base | `FORGEJO_DB_ROOT_PASSWORD` | Généré mais non utilisé par la stack actuelle |
| Forgejo / mail | `FORGEJO_MAIL_PASSWORD` | Boîte `git@` |
| code-server | `CODE_SERVER_PASSWORD` | Mot de passe de l'éditeur web |
| code-server | `CODE_SERVER_HTTP_USER`, `CODE_SERVER_HTTP_PASSWORD` | Première protection HTTP Basic par Traefik |
| code-server | `GIT_USER_NAME`, `GIT_USER_EMAIL` | Profil Git global du conteneur (commits) |
| KeeWeb | `KEEWEB_UI_USER`, `KEEWEB_UI_PASSWORD` | Accès à l'interface KeeWeb |
| KeeWeb | `KEEWEB_WEBDAV_USER`, `KEEWEB_WEBDAV_PASSWORD` | Accès WebDAV |
| Nextcloud | `NEXTCLOUD_ADMIN_USER`, `NEXTCLOUD_ADMIN_PASSWORD` | Compte admin Nextcloud |
| Nextcloud | `NEXTCLOUD_ADMIN_EMAIL` | E-mail du compte admin |
| Nextcloud / base | `NEXTCLOUD_DB_USER`, `NEXTCLOUD_DB_PASSWORD` | Base MariaDB |
| Nextcloud / base | `NEXTCLOUD_DB_ROOT_PASSWORD` | Compte root MariaDB (dump de sauvegarde) |
| Nextcloud / Redis | `NEXTCLOUD_REDIS_PASSWORD` | Cache, verrous et sessions Redis |
| Nextcloud / mail | `NEXTCLOUD_MAIL_PASSWORD` | Boîte `cloud@` (optionnel) |
| Dockhand | `DOCKHAND_HTTP_USER`, `DOCKHAND_HTTP_PASSWORD` | Protection HTTP Basic par Traefik, puis compte Dockhand |
| Dockhand | `DOCKHAND_ENCRYPTION_KEY` | Chiffrement des identifiants Dockhand |
| Uptime Kuma | `UPTIME_KUMA_ADMIN_USER`, `UPTIME_KUMA_ADMIN_PASSWORD` | Compte admin Uptime Kuma (pas de Basic Auth) |
| Minecraft | `MINECRAFT_RCON_PASSWORD` | Administration RCON interne |
| Minecraft | `VELOCITY_SECRET` | Liaison Velocity / serveurs Paper |

## Modifier un mot de passe

### Tableau de bord Traefik, phpMyAdmin, KeeWeb, code-server, Forgejo, Dockhand (HTTP Basic)

1. Modifier la valeur dans `.env`.
2. Lancer `sudo make init` pour régénérer les fichiers `.htpasswd`.
3. Redémarrer le service concerné (ou Traefik).

```sh
sudo make restart-service SERVICE=traefik
```

### Forgejo

Forgejo a deux protections :

- `FORGEJO_HTTP_USER` / `FORGEJO_HTTP_PASSWORD` : protection HTTP Basic
  par Traefik, générée dans `stacks/proxy/auth/forgejo.htpasswd` ;
- `FORGEJO_ADMIN_NAME` / `FORGEJO_ADMIN_PASSWORD` : compte admin Forgejo.

Pour changer la protection HTTP : modifier `.env`, lancer `sudo make init`,
puis redémarrer Forgejo.

### code-server

code-server a deux mots de passe :

- `CODE_SERVER_HTTP_USER` / `CODE_SERVER_HTTP_PASSWORD` : protection HTTP Basic
  par Traefik, générée dans `stacks/proxy/auth/code-server.htpasswd` ;
- `CODE_SERVER_PASSWORD` : mot de passe de l'éditeur web.

Pour changer la protection HTTP : modifier `.env`, lancer `sudo make init`,
puis redémarrer code-server. Pour changer le mot de passe de l'éditeur :
modifier `CODE_SERVER_PASSWORD` dans `.env`, puis redémarrer :

```sh
sudo make restart-service SERVICE=code-server
```

### Comptes admin Azuriom et site PHP

Le compte est créé **au premier démarrage**. Modifier la variable dans `.env`
ne change pas le mot de passe d'un compte déjà existant. Connectez-vous à
l'interface du service pour le changer, ou supprimez les données du service
pour repartir de zéro (destructif).

### Compte admin Nextcloud

Le compte est créé **au premier démarrage**. Modifier
`NEXTCLOUD_ADMIN_PASSWORD` dans `.env` ne change pas le mot de passe d'un
compte déjà existant : utilisez l'interface Nextcloud ou `occ`.

```sh
docker exec -u www-data nextcloud php occ user:resetpassword admin
```

### Compte Dockhand

Le compte Dockhand n'est **pas** défini dans `.env`. L'authentification de
Dockhand est désactivée au premier démarrage : créez le compte administrateur
dans `Settings` > `Authentication`, puis activez la protection.

`DOCKHAND_HTTP_USER` / `DOCKHAND_HTTP_PASSWORD` protègent uniquement l'accès
Traefik. Modifier ces valeurs puis lancer `sudo make init` et redémarrer
Dockhand ne change pas le compte créé dans l'interface.

### Compte admin Uptime Kuma

Le compte est créé **automatiquement** au premier démarrage par
`make up` ou `make up-service SERVICE=uptime-kuma`. La commande reste
disponible manuellement :

```sh
sudo make uptime-kuma-admin
```

Modifier `UPTIME_KUMA_ADMIN_USER` ou `UPTIME_KUMA_ADMIN_PASSWORD` dans `.env`
ne change pas un compte existant. Utilisez l'interface Uptime Kuma, ou l'outil
intégré :

```sh
docker exec -it uptime-kuma node extra/reset-password.js
```

Si vous changez le mot de passe dans l'interface, reportez la même valeur dans
`UPTIME_KUMA_ADMIN_PASSWORD` : `make up` et
`make uptime-kuma-docker-sync` utilisent ce compte pour synchroniser les
moniteurs Docker.

### Compte admin Forgejo

Le compte admin est créé **automatiquement** par `make up` et par
`make up-service SERVICE=forgejo`. La commande reste disponible manuellement :

```sh
sudo make forgejo-admin
```

Modifier `.env` ensuite ne change pas le compte existant : utilisez l'interface
Forgejo.

### Bases de données

Modifier `PHP_DB_PASSWORD` dans `.env` ne change pas le mot de passe déjà
enregistré dans MariaDB. Avant le premier démarrage, tout est cohérent. Après,
il faut changer le mot de passe dans la base (via phpMyAdmin ou SQL) **et**
dans `.env`.

## Fichiers générés

| Fichier | Contenu |
|---|---|
| `.env` | Configuration et secrets |
| `stacks/proxy/auth/dashboard.htpasswd` | Accès au dashboard Traefik |
| `stacks/proxy/auth/phpmyadmin.htpasswd` | Accès HTTP à phpMyAdmin |
| `stacks/proxy/auth/code-server.htpasswd` | Accès HTTP à code-server |
| `stacks/proxy/auth/forgejo.htpasswd` | Accès HTTP à Forgejo |
| `stacks/web/keeweb/auth/*.htpasswd` | Accès KeeWeb et WebDAV |
| `stacks/web/php-site/src/.env` | Configuration du site PHP cloné |

Ces fichiers sont ignorés par Git (sauf les `.gitkeep`).
