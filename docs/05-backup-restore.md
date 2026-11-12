# Sauvegarde et restauration

## Ce que `make backup` sauvegarde

```sh
sudo make backup
```

La sauvegarde est créée dans `backups/AAAA-MM-JJ_HHMMSS/`. Elle contient :

- un dump SQL de `db-php` (MariaDB) ;
- un dump SQL de `db-azuriom` (MariaDB) ;
- un dump SQL de `db-nextcloud` (MariaDB) ;
- un dump SQL de `db-forgejo` (PostgreSQL) ;
- les volumes applicatifs marqués `should.backup=true` :
  - Azuriom : stockage, plugins, thèmes, configuration ;
  - Forgejo : dépôts, comptes, configuration ;
  - KeeWeb : fichiers WebDAV ;
  - Nextcloud : fichiers, configuration et applications (`nextcloud-html`) ;
  - Dockhand : base SQLite, stacks et dépôts Git (`dockhand-data`) ;
  - Uptime Kuma : base SQLite, moniteurs, notifications et status pages (`uptime-kuma-data`) ;
  - code-server : réglages et espace de travail ;
  - Minecraft : mondes des serveurs Paper, données partagées du plugin
    (`mc-plugin-data`) et configuration de Velocity ;
  - bot Discord : données.

Les volumes des bases de données ne sont **pas** archivés : les dumps SQL
suffisent et sont plus fiables.

## Ce qui n'est pas sauvegardé

- `.env` et les fichiers `.htpasswd` (à copier manuellement dans un endroit
  sûr) ;
- mailcow (il a sa propre procédure de sauvegarde) ;
- les logs, les certificats et les données temporaires ;
- le cache et les sessions Redis de Nextcloud ;
- les plugins Minecraft téléchargés (ils peuvent être retéléchargés).

> Copiez `.env` séparément : sans lui, les mots de passe des bases et des
> services sont perdus.

## Vérifier une sauvegarde

```sh
ls -lh backups/AAAA-MM-JJ_HHMMSS/
cat backups/AAAA-MM-JJ_HHMMSS/manifest.txt
```

## Restaurer

> **Attention :** la restauration remplace les données actuelles.

```sh
sudo CONFIRM=yes make restore BACKUP=backups/AAAA-MM-JJ_HHMMSS
```

La commande :

1. arrête les applications ;
2. démarre les bases de données ;
3. attend qu'elles soient prêtes ;
4. réimporte les dumps SQL ;
5. restaure les volumes ;
6. redémarre toute l'infrastructure.

## Bonnes pratiques

- Faites une sauvegarde avant chaque mise à jour ou nettoyage.
- Testez la restauration sur un serveur de test si possible.
- Copiez les sauvegardes sur un autre disque ou un autre serveur.
- Pour une sauvegarde plus cohérente, arrêtez les applications tout en
  laissant les bases démarrées :

```sh
sudo make stop SERVICE=php-site
sudo make stop SERVICE=azuriom
sudo make stop SERVICE=forgejo
sudo make stop SERVICE=keeweb
sudo make stop SERVICE=nextcloud
sudo make stop SERVICE=nextcloud-cron
sudo make stop SERVICE=code-server
sudo make stop SERVICE=uptime-kuma
sudo make backup
sudo make up
```

Ne lancez pas `make down` avant `make backup` : les bases seraient arrêtées et
les dumps seraient ignorés.

## Nettoyer les anciennes sauvegardes

```sh
du -sh backups/*
```

Supprimez uniquement les dossiers dont vous n'avez plus besoin. `backups/` est
ignoré par Git.
