# Site PHP

**Rôle :** site web PHP (dépôt `website`) avec une base MariaDB dédiée.

**Conteneurs :** `php-site`, `db-php`  
**Adresse :** `https://php.<DOMAIN_NAME><TLD>`  
**Alias :** `https://phpdoc.<DOMAIN_NAME><TLD>`  
**Exemple :** `https://php.supername.fr`

## Mot de passe

| Variable `.env` | Utilisation |
|---|---|
| `WEBSITE_ADMIN_USERNAME` | Identifiant admin du site (par défaut `DOMAIN_NAME`) |
| `WEBSITE_ADMIN_PASSWORD` | Mot de passe admin du site, généré par `make init` |
| `PHP_DB_USER` / `PHP_DB_PASSWORD` | Compte de la base utilisé par le site |
| `PHP_DB_ROOT_PASSWORD` | Compte root MariaDB |

Le site n'utilise pas d'authentification HTTP Basic : il a son propre écran de
connexion. Le compte admin est créé au premier démarrage.

## Variables `.env` utiles

| Variable | Rôle |
|---|---|
| `PHP_DB_NAME` | Nom de la base (par défaut `php_site`) |
| `PHP_DB_USER` | Utilisateur de la base |
| `PHP_DB_PASSWORD` | Mot de passe de l'utilisateur |
| `PHP_DB_ROOT_PASSWORD` | Mot de passe root MariaDB |
| `PHP_SITE_REPO_URL` | Dépôt Git du site |
| `PHP_SITE_REPO_REF` | Branche ou tag à cloner |
| `WEBSITE_ADMIN_USERNAME` | Identifiant admin |
| `WEBSITE_ADMIN_PASSWORD` | Mot de passe admin |
| `WEBSITE_ADMIN_DISCORD_USER_ID` | Identifiant Discord du compte admin (optionnel) |
| `WEBSITE_DISCORD_CLIENT_ID` | OAuth Discord (optionnel) |
| `WEBSITE_DISCORD_CLIENT_SECRET` | OAuth Discord (optionnel) |
| `WEBSITE_DISCORD_REDIRECT_URI` | URL de retour OAuth (optionnel, vide = `https://php.<DOMAIN>/discord/callback`) |
| `WEBSITE_AUTO_INIT` | Initialise la base au premier démarrage |
| `WEBSITE_GIT_DEPLOY` | Autorise `/api/deploy` à faire `git pull` |

`make php-site-env` traduit ces variables vers les noms lus par le site dans
`src/.env` : `WEBSITE_DISCORD_CLIENT_ID` → `DISCORD_CLIENT_ID`,
`WEBSITE_DISCORD_CLIENT_SECRET` → `DISCORD_CLIENT_SECRET`,
`WEBSITE_DISCORD_REDIRECT_URI` → `DISCORD_REDIRECT_URI`,
`WEBSITE_ADMIN_DISCORD_USER_ID` → `ADMIN_DISCORD_USER_ID`.
Le site ne lit pas les variables préfixées `WEBSITE_`.

## Démarrer / arrêter

```sh
sudo make up-service SERVICE=php-site
sudo make ps-service SERVICE=php-site
sudo make logs-service SERVICE=php-site
sudo make stop SERVICE=php-site
```

La commande démarre aussi `db-php` automatiquement. Pour arrêter la base :

```sh
sudo make stop SERVICE=db-php
```

## Code source

Le site est cloné dans `stacks/web/php-site/src` :

```sh
sudo make php-site-src      # clone si absent
sudo make php-site-env      # régénère src/.env depuis .env
```

Le dossier `src` est un dépôt Git monté dans le conteneur. `make backup` ne
l'archive pas : sauvegardez-le séparément ou poussez vos modifications dans Git.

Pour mettre à jour le site, utilisez `/api/deploy` ou :

```sh
cd stacks/web/php-site/src
git pull
```

## Nettoyer

```sh
sudo CONFIRM=yes make clean-service SERVICE=php-site
sudo CONFIRM=yes make clean-service SERVICE=db-php
```

`clean-service php-site` supprime le conteneur, mais **pas** le dossier
`stacks/web/php-site/src` (c'est un dossier monté, pas un volume Docker). Pour
supprimer aussi le code et les uploads, effacez ce dossier manuellement.

La suppression de `db-php` efface la base. Le site la recrée au démarrage
suivant si `WEBSITE_AUTO_INIT=true`.

## Sauvegarde

- Base : incluse dans `make backup` (dump `db-php`).
- Fichiers du site : dossier `stacks/web/php-site/src`, à sauvegarder
  séparément.
- Uploads et logs : dans `src`, donc également à sauvegarder séparément.

## Dépannage

- **Erreur de base** : vérifiez `PHP_DB_*` et que `db-php` est `healthy`.
- **Page blanche** : consultez `sudo make logs-service SERVICE=php-site`.
- **Le clone échoue** : vérifiez `PHP_SITE_REPO_URL`, l'accès réseau et Git.
- **Le site ne s'initialise pas** : vérifiez `WEBSITE_AUTO_INIT` et les logs.
