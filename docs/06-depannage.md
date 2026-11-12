# Dépannage

## Les premiers réflexes

```sh
sudo make ps
sudo make logs-service SERVICE=nom
sudo make config
docker inspect nom-du-conteneur
```

Remplacez `nom` par le service voulu : `traefik`, `php-site`, `azuriom`,
`forgejo`, `code-server`, `keeweb`, `nextcloud`, `dockhand`, `uptime-kuma`,
`uptime-kuma-docker-proxy`, `phpmyadmin`, `velocity`, `bot`, etc.

## Le site affiche une erreur 404

- Vérifiez `DOMAIN_NAME` et `TLD` dans `.env`.
- Vérifiez que le DNS pointe vers le serveur.
- Vérifiez que Traefik tourne :

```sh
sudo make ps-service SERVICE=traefik
```

- Vérifiez que le service tourne et que son nom de domaine correspond.

## Le site affiche une erreur 502 ou 503

Le service derrière Traefik ne répond pas.

```sh
sudo make ps-service SERVICE=nom
sudo make logs-service SERVICE=nom
sudo make restart-service SERVICE=nom
```

Vérifiez aussi que le conteneur écoute sur le port attendu par Traefik.

## Le certificat HTTPS ne se crée pas

- Le port `80` doit être ouvert et accessible depuis Internet.
- Le DNS doit pointer vers le serveur.
- Cloudflare doit être en mode « DNS only » (proxy désactivé) pour la
  validation HTTP.
- Consultez les logs Traefik :

```sh
sudo make logs-service SERVICE=traefik
```

Let's Encrypt limite le nombre de certificats. En cas de tests répétés, utilisez
le serveur de test Let's Encrypt via `TRAEFIK_ACME_CA_SERVER` dans `.env`.

## `port is already allocated`

Un autre programme utilise déjà le port `80`, `443` ou `25565`.

```sh
sudo ss -tlnp | grep -E ':80|:443|:25565'
```

Arrêtez l'autre programme (souvent Apache, Nginx ou un autre Docker).

## `permission denied` sur Docker

Ajoutez votre utilisateur au groupe `docker`, puis reconnectez-vous :

```sh
sudo usermod -aG docker "$USER"
```

Ou utilisez `sudo` devant les commandes `make`.

## `.env` introuvable ou `CHANGE_ME`

```sh
sudo make init
```

`make init` crée `.env` s'il manque et remplit les secrets encore vides ou
égaux à `CHANGE_ME`.

## Le bot Discord s'arrête tout de suite

`DISCORD_BOT_TOKEN` est vide ou vaut `CHANGE_ME`. Renseignez un vrai token dans
`.env`, puis :

```sh
sudo make up-service SERVICE=bot
sudo make logs-service SERVICE=bot
```

## Azuriom refuse de démarrer

En mode `mc-online`, `AZURIOM_ADMIN_GAME_ID` est obligatoire au premier
démarrage. Il doit contenir 32 caractères hexadécimaux, sans tirets. Vérifiez
aussi `AZURIOM_ADMIN_PASSWORD` et les variables `AZURIOM_DB_*`.

## Forgejo : impossible de se connecter

Le compte admin n'est pas créé automatiquement par le conteneur. Lancez :

```sh
sudo make forgejo-admin
```

Le nom `admin` est réservé par Forgejo. Utilisez un autre nom.

## Nextcloud : « Access through untrusted domain »

Le nom d'hôte utilisé n'est pas dans les domaines de confiance. Au premier
démarrage, `NEXTCLOUD_TRUSTED_DOMAINS` les enregistre ; après une modification
de domaine, ajoutez-les avec `occ` :

```sh
docker exec -u www-data nextcloud php occ config:system:get trusted_domains
docker exec -u www-data nextcloud php occ config:system:set trusted_domains 1 --value=cloud.mondomaine.fr
```

Vérifiez aussi que l'alias est bien déclaré dans la règle Traefik de
`stacks/web/nextcloud/compose.yaml`.

## Nextcloud : mauvais protocole ou redirections en boucle

Traefik termine le HTTPS. Vérifiez dans `.env` puis `docker compose config`
que `OVERWRITEPROTOCOL` vaut `https` et que `NEXTCLOUD_TRUSTED_PROXIES` couvre
le réseau Docker de Traefik.

## Nextcloud : upload de gros fichiers bloqué

Augmentez `NEXTCLOUD_PHP_UPLOAD_LIMIT` (et éventuellement
`NEXTCLOUD_PHP_MEMORY_LIMIT`), gardez `NEXTCLOUD_APACHE_BODY_LIMIT=0`, puis
recréez le conteneur :

```sh
sudo make up-service SERVICE=nextcloud
```

## Dockhand : permission refusée sur le socket Docker

Le conteneur n'a pas accès à `/var/run/docker.sock`. Vérifiez le GID du socket
et relancez l'initialisation :

```sh
stat -c '%g' /var/run/docker.sock
sudo make init
sudo make up-service SERVICE=dockhand
```

La valeur affichée doit correspondre à `DOCKER_GID` dans `.env`.

## Dockhand : identifiants ou environnements illisibles

La clé `DOCKHAND_ENCRYPTION_KEY` a changé. Dockhand ne peut plus déchiffrer les
identifiants enregistrés. Restaurez l'ancienne clé depuis la sauvegarde de
`.env` ou restaurez le volume `dockhand-data`.

## Uptime Kuma : compte admin non créé

Le script d'initialisation n'a pas pu joindre l'application. Vérifiez que le
conteneur est démarré et relancez la création :

```sh
sudo make ps-service SERVICE=uptime-kuma
sudo make logs-service SERVICE=uptime-kuma
sudo make uptime-kuma-admin
```

Si un compte existe déjà avec un autre mot de passe, utilisez l'outil intégré :

```sh
docker exec -it uptime-kuma node extra/reset-password.js
```

## Uptime Kuma : moniteurs Docker non créés

La synchronisation automatique se lance avec `make up` et `make up-service`
lorsque Uptime Kuma tourne. Vérifiez qu'elle n'est pas désactivée, puis
relancez-la à la main :

```sh
grep '^UPTIME_KUMA_DOCKER_SYNC=' .env
sudo make uptime-kuma-docker-sync
```

Les messages indiquent l'hôte Docker, le nombre de conteneurs détectés et les
moniteurs ajoutés. Causes fréquentes :

- le mot de passe admin a été changé dans l'interface mais pas dans
  `UPTIME_KUMA_ADMIN_PASSWORD` : la connexion échoue avec
  `authIncorrectCreds` ;
- le proxy `uptime-kuma-docker-proxy` n'est pas démarré ou refuse les requêtes ;
- le conteneur `uptime-kuma` n'est pas encore prêt : relancer la commande.

Pour ignorer un conteneur, l'ajouter à `UPTIME_KUMA_DOCKER_EXCLUDE`, relancer
la synchronisation, puis supprimer son moniteur dans l'interface.

## Uptime Kuma : la synchronisation s'affiche à chaque `up-service`

C'est normal : `make up-service SERVICE=<nom>` relance la synchronisation
après le démarrage du service pour détecter le nouveau conteneur. Quand rien
n'a changé, elle doit afficher une seule ligne :

```text
→ Uptime Kuma : 8 conteneur(s) détecté(s), aucun nouveau moniteur Docker, notification Discord à jour
```

Pour le détail :

```sh
sudo VERBOSE=1 make up-service SERVICE=<nom>
```

Si la sortie recrée le compte admin, la notification et les moniteurs avec des
identifiants qui repartent à `1`, la base Uptime Kuma a été réinitialisée. Ce
n'est **pas** le comportement normal de `up-service`, qui ne supprime pas les
volumes. Vérifiez le volume :

```sh
docker volume inspect uptime-kuma-data
```

Les commandes `make clean`, `make down-clean`,
`make clean-service SERVICE=uptime-kuma` et
`docker compose down -v` suppriment le volume. Le compte admin n'est créé que
par `make up` ou `make up-service SERVICE=uptime-kuma` ; si la ligne
« compte admin créé » apparaît pour un autre service, vérifiez que le
`Makefile` local est à jour.

## Uptime Kuma : notification Discord absente

Vérifiez d'abord que le webhook est renseigné dans `.env` et que la
configuration automatique est active :

```sh
grep '^UPTIME_KUMA_DISCORD_' .env
sudo make uptime-kuma-docker-sync
```

Le message `notification Discord ignorée` indique un webhook vide ou égal à
`CHANGE_ME`. Le message `n'est pas une URL HTTPS valide` indique une URL
incorrecte. Une fois
le webhook renseigné, la synchronisation crée ou met à jour la notification
dans `Settings` > `Notifications` ; utilisez le bouton **Test** pour vérifier
l'envoi.

Si la notification existe mais que certains moniteurs ne l'utilisent pas,
vérifiez `UPTIME_KUMA_DISCORD_DEFAULT` (nouveaux moniteurs) et
`UPTIME_KUMA_DISCORD_APPLY_EXISTING` (moniteurs déjà créés). Pour désactiver
complètement la configuration automatique :
`UPTIME_KUMA_DISCORD_ENABLED=false`.

Si le test échoue, le webhook a probablement été révoqué ou le salon supprimé :
recréez-le dans Discord et mettez `.env` à jour. Le webhook n'est jamais
affiché dans les logs.

## Uptime Kuma : erreur 502 ou 503

Le conteneur Uptime Kuma ne répond pas. Vérifiez son état et ses logs :

```sh
sudo make ps-service SERVICE=uptime-kuma
sudo make logs-service SERVICE=uptime-kuma
```

Le premier démarrage peut être long après le téléchargement de l'image.

## Uptime Kuma : moniteur Docker en erreur 403

Le proxy de socket refuse la requête. Vérifiez qu'il tourne et que seules les
lectures nécessaires sont autorisées (`CONTAINERS=1`, `INFO=1`, `POST=0`) :

```sh
sudo make ps-service SERVICE=uptime-kuma-docker-proxy
sudo make logs-service SERVICE=uptime-kuma-docker-proxy
```

L'hôte Docker `Local` est normalement créé automatiquement par
`make uptime-kuma-docker-sync` et doit pointer vers
`http://uptime-kuma-docker-proxy:2375`, pas vers `localhost`. S'il a été
supprimé ou modifié, relancez la synchronisation ou corrigez-le dans
`Settings` > `Docker Hosts`.

## Uptime Kuma : login ou WebSocket bloqué

Traefik conserve le `Host`, donc le contrôle d'origine par défaut fonctionne.
Vérifiez la console du navigateur et les logs Traefik. Ne passez à
`UPTIME_KUMA_WS_ORIGIN_CHECK=bypass` qu'en dernier recours, si un autre reverse
proxy réécrit le `Host`.

## Erreur d'authentification sur une base de données

Le mot de passe dans `.env` ne correspond plus à celui enregistré dans la base.
Cela arrive si vous modifiez `.env` après le premier démarrage.

- Remettez l'ancien mot de passe ;
- ou changez le mot de passe dans la base ;
- ou supprimez le volume de la base pour repartir de zéro (**destructif**) :

```sh
sudo CONFIRM=yes make clean-service SERVICE=db-php
sudo make up-service SERVICE=php-site
```

## Le disque est plein

```sh
docker system df
du -sh backups/*
```

Si `install.sh` a configuré Docker, les logs sont limités à 3 fichiers de
10 Mo. Supprimez les anciennes sauvegardes et les images inutilisées :

```sh
docker image prune
```

## Points connus dans la version actuelle

Certains scripts du dépôt sont incomplets. Vérifiez-les avant de compter sur les
services concernés :

| Service | Symptôme | Cause probable |
|---|---|---|
| Mailcow | `make mail-integrate` ne copie pas l'override | Le script génère un fichier local au lieu de l'installer dans `MAILCOW_DIR` |

En attendant une correction, consultez les fichiers concernés et adaptez-les, ou
utilisez la configuration manuelle décrite dans la fiche du service.

## Repartir de zéro

> **Dernier recours.** Toutes les données seront perdues.

```sh
sudo make down-clean CONFIRM=yes
sudo make up
```
