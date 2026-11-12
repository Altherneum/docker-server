# Bases de données

**Rôle :** stocker les données des applications. Les bases ne sont pas exposées
directement sur Internet.

| Conteneur | Moteur | Application | Volume | Accès phpMyAdmin |
|---|---|---|---|---|
| `db-php` | MariaDB 11.8 | Site PHP | `db-php` | Oui |
| `db-azuriom` | MariaDB 11.8 | Azuriom | `db-azuriom` | Oui |
| `db-nextcloud` | MariaDB 11.8 | Nextcloud | `db-nextcloud` | Oui |
| `db-forgejo` | PostgreSQL 18 | Forgejo | `db-forgejo` | Non |

## Identifiants

| Base | Nom de base | Utilisateur | Mot de passe utilisateur | Mot de passe root |
|---|---|---|---|---|
| `db-php` | `PHP_DB_NAME` | `PHP_DB_USER` | `PHP_DB_PASSWORD` | `PHP_DB_ROOT_PASSWORD` |
| `db-azuriom` | `AZURIOM_DB_NAME` | `AZURIOM_DB_USER` | `AZURIOM_DB_PASSWORD` | `AZURIOM_DB_ROOT_PASSWORD` |
| `db-nextcloud` | `NEXTCLOUD_DB_NAME` | `NEXTCLOUD_DB_USER` | `NEXTCLOUD_DB_PASSWORD` | `NEXTCLOUD_DB_ROOT_PASSWORD` |
| `db-forgejo` | `FORGEJO_DB_NAME` | `FORGEJO_DB_USER` | `FORGEJO_DB_PASSWORD` | *(pas de root séparé)* |

Tous ces mots de passe sont générés par `make init`.
`FORGEJO_DB_ROOT_PASSWORD` existe dans `.env` mais n'est pas utilisé : sur
PostgreSQL, `FORGEJO_DB_USER` est le superutilisateur créé par l'image.

## Démarrer / arrêter

Les bases démarrent normalement avec leur application :

```sh
sudo make up-service SERVICE=php-site      # démarre aussi db-php
sudo make up-service SERVICE=azuriom       # démarre aussi db-azuriom
sudo make up-service SERVICE=nextcloud     # démarre aussi db-nextcloud
sudo make up-service SERVICE=forgejo       # démarre aussi db-forgejo
```

Pour gérer une base seule :

```sh
sudo make up-service SERVICE=db-php
sudo make stop SERVICE=db-php
sudo make ps-service SERVICE=db-php
sudo make logs-service SERVICE=db-php
```

## Nettoyer

```sh
sudo CONFIRM=yes make clean-service SERVICE=db-php
```

Cela supprime le volume de la base et donc **toutes ses données**. Les autres
bases ne sont pas touchées.

## Accéder aux bases

### MariaDB

Utilisez phpMyAdmin :

```text
https://phpmyadmin.<DOMAIN_NAME><TLD>
```

phpMyAdmin demande deux mots de passe : d'abord la protection HTTP Basic
(`PMA_ADMIN_USER` / `PMA_ADMIN_PASSWORD`), puis, sur la page de connexion
phpMyAdmin, le compte MariaDB de la base ciblée (root ou utilisateur
applicatif). Voir [phpmyadmin.md](phpmyadmin.md#authentification-en-deux-étapes).

### PostgreSQL

`db-forgejo` n'est pas accessible via phpMyAdmin. Utilisez `psql` depuis le
conteneur :

```sh
docker exec -it db-forgejo psql -U "$(sudo sed -n 's/^FORGEJO_DB_USER=//p' .env)" \
  -d "$(sudo sed -n 's/^FORGEJO_DB_NAME=//p' .env)"
```

## Sauvegarde

`make backup` crée un dump de chaque base **si le conteneur tourne**. Les
volumes des bases ne sont pas archivés : les dumps sont la source de vérité.

```sh
sudo make backup
```

## Changer un mot de passe

Modifier `.env` ne change pas le mot de passe déjà enregistré dans la base.
Après le premier démarrage :

1. changez le mot de passe dans la base (phpMyAdmin ou SQL) ;
2. reportez la même valeur dans `.env` ;
3. redémarrez l'application.

Si vous modifiez `.env` sans changer la base, l'application ne pourra plus se
connecter.

## Dépannage

- **`Access denied for user`** : le mot de passe `.env` ne correspond pas à
  celui de la base.
- **Base non `healthy`** : consultez les logs du conteneur.
- **Données perdues après `clean-service`** : restaurez une sauvegarde.
