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
| Minecraft | `MINECRAFT_RCON_PASSWORD` | Administration RCON interne |
| Minecraft | `VELOCITY_SECRET` | Liaison Velocity / serveurs Paper |

## Modifier un mot de passe

### Tableau de bord Traefik, phpMyAdmin, KeeWeb, code-server, Forgejo (HTTP Basic)

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
