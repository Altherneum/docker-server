# Nextcloud - cloud personnel

**Rôle :** cloud auto-hébergé pour les fichiers, calendriers, contacts et
partages. Accessible depuis le navigateur, les clients desktop et mobile, ainsi
qu'en WebDAV et CalDAV/CardDAV.

**Conteneurs :** `nextcloud`, `nextcloud-cron`, `nextcloud-redis`,
`db-nextcloud`  
**Adresse :** `https://cloud.<DOMAIN_NAME><TLD>`  
**Alias :** `nextcloud`, `drive`, `files`  
**Exemple :** `https://cloud.supername.fr`

## Authentification

Nextcloud gère lui-même ses comptes. Il n'y a **pas** de protection HTTP Basic
par Traefik : elle casserait les clients desktop/mobile, la synchronisation
WebDAV et CalDAV/CardDAV.

| Variable `.env` | Utilisation |
|---|---|
| `NEXTCLOUD_ADMIN_USER` | Identifiant du compte administrateur |
| `NEXTCLOUD_ADMIN_PASSWORD` | Mot de passe du compte administrateur |
| `NEXTCLOUD_ADMIN_EMAIL` | E-mail du compte administrateur |

Le compte admin est créé **au premier démarrage**. Modifier
`NEXTCLOUD_ADMIN_PASSWORD` dans `.env` ensuite ne change pas le mot de passe du
compte existant : utilisez l'interface ou `occ`.

## Variables `.env` utiles

| Variable | Rôle |
|---|---|
| `NEXTCLOUD_VERSION` | Version majeure de l'image (`35` par défaut) |
| `NEXTCLOUD_REDIS_VERSION` | Image Redis (`8-alpine` par défaut) |
| `NEXTCLOUD_DB_NAME` | Nom de la base (`nextcloud`) |
| `NEXTCLOUD_DB_USER` | Utilisateur de la base |
| `NEXTCLOUD_DB_PASSWORD` | Mot de passe de la base |
| `NEXTCLOUD_DB_ROOT_PASSWORD` | Compte root MariaDB, utilisé par `make backup` |
| `NEXTCLOUD_REDIS_PASSWORD` | Mot de passe Redis |
| `NEXTCLOUD_TRUSTED_PROXIES` | Proxies de confiance (Traefik) |
| `NEXTCLOUD_PHP_MEMORY_LIMIT` | Limite mémoire PHP (`512M`) |
| `NEXTCLOUD_PHP_UPLOAD_LIMIT` | Taille maximale d'un fichier (`10G`) |
| `NEXTCLOUD_APACHE_BODY_LIMIT` | Limite du corps HTTP Apache (`0` = illimité) |
| `NEXTCLOUD_MAIL_*` | Configuration SMTP optionnelle |

Les mots de passe sont générés par `make init`.

## Démarrer / arrêter

```sh
sudo make up-service SERVICE=nextcloud
sudo make ps-service SERVICE=nextcloud
sudo make logs-service SERVICE=nextcloud
sudo make stop SERVICE=nextcloud
```

`make up-service SERVICE=nextcloud` démarre aussi `db-nextcloud`,
`nextcloud-redis` et `nextcloud-cron`. Le premier démarrage peut prendre
plusieurs minutes (installation de Nextcloud et initialisation de la base).

L'interface est ensuite disponible sur `https://cloud.<domaine>`. Les alias
`nextcloud`, `drive` et `files` pointent vers la même instance.

## Reverse proxy et domaines de confiance

Traefik termine le HTTPS et transmet l'adresse cliente à Nextcloud. Les
variables suivantes sont définies par `compose.yaml` :

- `NEXTCLOUD_TRUSTED_DOMAINS` : `cloud`, `nextcloud`, `drive` et `files` ;
- `TRUSTED_PROXIES` : plages privées Docker ;
- `OVERWRITEPROTOCOL=https` et `OVERWRITECLIURL` pour générer des liens HTTPS.

`NEXTCLOUD_TRUSTED_DOMAINS` n'est appliqué qu'**au premier démarrage**. Si vous
changez de domaine ou ajoutez un alias après l'installation, mettez à jour la
liste dans `compose.yaml`, puis exécutez :

```sh
docker exec -u www-data nextcloud php occ config:system:get trusted_domains
docker exec -u www-data nextcloud php occ config:system:set trusted_domains 1 --value=cloud.mondomaine.fr
```

Répétez l'index (`2`, `3`, …) pour chaque nom.

## Redis et tâches de fond

- `nextcloud-redis` sert de cache, de gestionnaire de verrous et de stockage des
  sessions PHP. Il est protégé par `NEXTCLOUD_REDIS_PASSWORD` et reste sur le
  réseau interne `nextcloud_internal`.
- `nextcloud-cron` exécute `cron.php` toutes les 5 minutes. Le mode cron est
  activé automatiquement au premier démarrage par le hook
  `stacks/web/nextcloud/hooks/post-installation/10-admin-config.sh`.

Vérifier le mode des tâches de fond :

```sh
docker exec -u www-data nextcloud php occ background:get
```

Forcer le mode cron si nécessaire :

```sh
docker exec -u www-data nextcloud php occ background:cron
```

## E-mail (optionnel)

L'envoi d'e-mails est désactivé tant que `NEXTCLOUD_MAIL_HOST` est vide. Pour
l'activer, renseignez dans `.env` :

```dotenv
NEXTCLOUD_MAIL_HOST=mail.monprojet.com
NEXTCLOUD_MAIL_PORT=587
NEXTCLOUD_MAIL_SECURE=tls
NEXTCLOUD_MAIL_USERNAME=cloud@monprojet.com
NEXTCLOUD_MAIL_PASSWORD=...
NEXTCLOUD_MAIL_FROM_ADDRESS=cloud@monprojet.com
NEXTCLOUD_MAIL_DOMAIN=monprojet.com
```

Créez la boîte `cloud@` dans mailcow avec le mot de passe
`NEXTCLOUD_MAIL_PASSWORD`, puis redémarrez :

```sh
sudo make up-service SERVICE=nextcloud
```

> Les variables `NEXTCLOUD_MAIL_*` sont lues par l'image à chaque démarrage.
> Ne configurez pas aussi le SMTP dans l'interface Nextcloud : les variables
> Docker prennent le dessus. Pour désactiver l'envoi, videz
> `NEXTCLOUD_MAIL_HOST` et redémarrez.

## Mettre à jour Nextcloud

Nextcloud ne peut monter que d'**une version majeure à la fois** (par exemple
34 → 35, jamais 33 → 35). Sauvegardez avant toute mise à jour.

1. Sauvegardez : `sudo make backup`.
2. Changez `NEXTCLOUD_VERSION` dans `.env` (une majeure à la fois).
3. Recréez les conteneurs :

```sh
sudo make up-service SERVICE=nextcloud
```

L'image officielle met à jour le schéma et les fichiers au démarrage. Le
conteneur `nextcloud-cron` utilise la même version que le conteneur web.

> Ne revenez pas à une version majeure inférieure : Nextcloud refuse de
> démarrer si les données ont été migrées vers une version plus récente.

## Sauvegarde

`make backup` sauvegarde :

- la base via un dump `db-nextcloud` ;
- le volume `nextcloud-html`, qui contient les fichiers des utilisateurs, la
  configuration et les applications.

Le volume Redis n'est pas sauvegardé : il ne contient que du cache et des
sessions. Les utilisateurs devront éventuellement se reconnecter après une
restauration.

Restaurez avec le **même `.env`** : les identifiants de la base sont aussi
enregistrés dans `config/config.php` du volume `nextcloud-html`. Si vous changez
les mots de passe de la base, mettez-les à jour dans les deux endroits.

Pour une sauvegarde cohérente, arrêtez Nextcloud et son cron avant :

```sh
sudo make stop SERVICE=nextcloud
sudo make stop SERVICE=nextcloud-cron
sudo make backup
sudo make up
```

## Nettoyer

```sh
sudo CONFIRM=yes make clean-service SERVICE=nextcloud
sudo CONFIRM=yes make clean-service SERVICE=nextcloud-cron
sudo CONFIRM=yes make clean-service SERVICE=db-nextcloud
sudo CONFIRM=yes make clean-service SERVICE=nextcloud-redis
```

Le volume `nextcloud-html` est partagé par `nextcloud` et `nextcloud-cron` :
`clean-service` le conserve donc par sécurité. Pour supprimer **toutes** les
données, supprimez-le explicitement après avoir arrêté les deux conteneurs :

```sh
docker volume rm nextcloud-html
```

> Opération destructive : fichiers, configuration et applications Nextcloud
> seront perdus.

## Accès en ligne de commande (`occ`)

```sh
docker exec -u www-data nextcloud php occ status
docker exec -u www-data nextcloud php occ user:list
docker exec -u www-data nextcloud php occ config:system:get trusted_domains
docker exec -u www-data nextcloud php occ maintenance:mode --on
docker exec -u www-data nextcloud php occ maintenance:mode --off
```

## Dépannage

- **« Access through untrusted domain »** : le nom d'hôte n'est pas dans
  `trusted_domains`. Ajoutez-le avec `occ` (voir plus haut) et vérifiez les
  alias Traefik.
- **Boucle de redirection ou liens en `http://`** : vérifiez
  `OVERWRITEPROTOCOL`, `OVERWRITECLIURL` et `TRUSTED_PROXIES`.
- **502 via Traefik** : le conteneur `nextcloud` n'est pas démarré ou termine
  son installation. Consultez les logs.
- **Le conteneur redémarre en boucle** : vérifiez `NEXTCLOUD_DB_*`,
  `NEXTCLOUD_DB_ROOT_PASSWORD` et que `db-nextcloud` est `healthy`.
- **Erreur Redis / sessions perdues** : vérifiez `NEXTCLOUD_REDIS_PASSWORD`,
  puis `sudo make logs-service SERVICE=nextcloud-redis`.
- **Upload bloqué** : augmentez `NEXTCLOUD_PHP_UPLOAD_LIMIT` et gardez
  `NEXTCLOUD_APACHE_BODY_LIMIT=0`, puis redémarrez Nextcloud.
- **Les e-mails ne partent pas** : `NEXTCLOUD_MAIL_HOST` doit être non vide, la
  boîte doit exister dans mailcow, et le mot de passe doit correspondre.
- **Version refusée au démarrage** : vous tentez de descendre de version ou de
  sauter plusieurs majeures. Restaurez la sauvegarde et montez une majeure à la
  fois.

Logs :

```sh
sudo make logs-service SERVICE=nextcloud
sudo make logs-service SERVICE=nextcloud-cron
sudo make logs-service SERVICE=nextcloud-redis
sudo make logs-service SERVICE=db-nextcloud
```
