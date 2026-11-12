# Uptime Kuma - supervision

**Rôle :** surveiller la disponibilité des services et des conteneurs Docker :
HTTP(S), TCP, ping, DNS, mots-clés, WebSocket et état des conteneurs.

**Conteneurs :** `uptime-kuma`, `uptime-kuma-docker-proxy`  
**Adresses :** `https://status.<DOMAIN_NAME><TLD>`, `https://uptime.<DOMAIN_NAME><TLD>`, `https://monitor.<DOMAIN_NAME><TLD>` et `https://kuma.<DOMAIN_NAME><TLD>`  
**Exemple :** `https://status.supername.fr`

## Authentification

Uptime Kuma possède son **propre compte administrateur**. Il n'y a **pas** de
HTTP Basic Auth Traefik devant l'interface : le login Uptime Kuma suffit.

Le compte est créé automatiquement au premier démarrage via `make up` ou
`make up-service SERVICE=uptime-kuma`, par `scripts/uptime-kuma-admin.sh`, à
partir de `UPTIME_KUMA_ADMIN_USER` et `UPTIME_KUMA_ADMIN_PASSWORD`. Le script
est idempotent : si un compte existe déjà, il ne modifie rien.

Uptime Kuma 2.x ne sait pas créer l'admin avec des variables d'environnement
(cette fonction arrive avec la 3.x). Le script utilise donc l'événement
Socket.IO public `setup` après le démarrage. Aucun mot de passe n'est écrit
dans les logs.

> Le script est lancé immédiatement après le démarrage, avant les autres
> scripts de `make up`. Tant que le compte n'existe pas, la page de première
> installation reste accessible : sur un serveur exposé, vérifiez que
> `make up` s'est terminé sans avertissement.

Les identifiants se lisent dans `.env` :

```sh
grep '^UPTIME_KUMA_ADMIN_USER=' .env
grep '^UPTIME_KUMA_ADMIN_PASSWORD=' .env
```

Après la première connexion, changez le mot de passe dans `Settings` >
`Security` > `Change Password` si nécessaire. Modifier
`UPTIME_KUMA_ADMIN_USER` ou `UPTIME_KUMA_ADMIN_PASSWORD` dans `.env`
**ne change pas** un compte déjà existant.

Les **status pages** créées dans Uptime Kuma peuvent être publiques. Le
dashboard d'administration reste protégé par le login.

## Variables `.env`

| Variable | Rôle | Exemple |
|---|---|---|
| `UPTIME_KUMA_VERSION` | Version exacte de l'image Uptime Kuma | `2.5.10` |
| `UPTIME_KUMA_DOCKER_PROXY_VERSION` | Version du proxy Docker en lecture seule | `v0.5.0` |
| `UPTIME_KUMA_DB_TYPE` | Type de base ; SQLite est incluse dans le volume | `sqlite` |
| `UPTIME_KUMA_ADMIN_USER` | Compte administrateur créé au premier démarrage | `admin` |
| `UPTIME_KUMA_ADMIN_PASSWORD` | Mot de passe du compte administrateur | généré par `make init` |
| `UPTIME_KUMA_DOCKER_SYNC` | Active la création automatique des moniteurs Docker | `true` |
| `UPTIME_KUMA_DOCKER_HOST_NAME` | Nom de l'hôte Docker ajouté dans Uptime Kuma | `Local` |
| `UPTIME_KUMA_DOCKER_HOST_URL` | URL interne du proxy Docker | `http://uptime-kuma-docker-proxy:2375` |
| `UPTIME_KUMA_DOCKER_EXCLUDE` | Conteneurs à ne pas surveiller, séparés par des virgules | vide |
| `UPTIME_KUMA_DISCORD_ENABLED` | Active la configuration automatique de la notification Discord | `true` |
| `UPTIME_KUMA_DISCORD_WEBHOOK_URL` | URL du webhook Discord, à renseigner | vide |
| `UPTIME_KUMA_DISCORD_BOT_NAME` | Nom affiché du bot Discord | `Uptime Kuma` |
| `UPTIME_KUMA_DISCORD_PREFIX` | Préfixe des messages Discord | `[Uptime Kuma]` |
| `UPTIME_KUMA_DISCORD_NOTIFICATION_NAME` | Nom de la notification dans Uptime Kuma | `Discord` |
| `UPTIME_KUMA_DISCORD_DEFAULT` | Notification par défaut des nouveaux moniteurs | `true` |
| `UPTIME_KUMA_DISCORD_APPLY_EXISTING` | Applique la notification aux moniteurs existants | `true` |

`UPTIME_KUMA_ADMIN_PASSWORD` est généré par `sudo make init`. Il n'est pas
passé au conteneur de façon permanente : les scripts l'utilisent uniquement
pour créer le compte, synchroniser les moniteurs Docker et configurer la
notification Discord.

`UPTIME_KUMA_DOCKER_HOST_URL` doit correspondre au nom du service proxy dans
`stacks/uptime-kuma/compose.yaml`. Ne la modifiez pas sans modifier aussi le
compose.

## Démarrer / arrêter

```sh
sudo make up-service SERVICE=uptime-kuma
sudo make ps-service SERVICE=uptime-kuma
sudo make logs-service SERVICE=uptime-kuma
sudo make stop SERVICE=uptime-kuma
```

`make up-service SERVICE=uptime-kuma` démarre aussi
`uptime-kuma-docker-proxy` grâce à `depends_on`. Le proxy reste sans port
publié et n'est joignable que par Uptime Kuma.

Le premier démarrage télécharge l'image Uptime Kuma, qui est volumineuse.
Aucune compilation locale n'est nécessaire.

## Premier lancement et compte admin

1. Ouvrir `https://status.<domaine>`.
2. Se connecter avec `UPTIME_KUMA_ADMIN_USER` et
   `UPTIME_KUMA_ADMIN_PASSWORD`.
3. Si le script n'a pas pu créer le compte, le faire manuellement :

```sh
sudo make uptime-kuma-admin
```

Si vous démarrez directement avec `docker compose up -d`, lancez une fois
`sudo make uptime-kuma-admin` puis `sudo make uptime-kuma-docker-sync` après le
démarrage : ces scripts ne sont alors pas appelés automatiquement.

## Surveiller les conteneurs Docker

Un proxy de socket est intercalé entre Uptime Kuma et Docker :

```text
uptime-kuma -> uptime-kuma-docker-proxy:2375 -> /var/run/docker.sock
```

Le proxy est limité aux lectures nécessaires :

```yaml
CONTAINERS: "1"
INFO: "1"
POST: "0"
```

Il ne peut donc pas démarrer, arrêter ou exécuter une commande dans un
conteneur. Il n'a pas de port publié et vit uniquement sur le réseau interne
`uptime_kuma_internal`.

### Synchronisation automatique

`scripts/uptime-kuma-docker-sync.sh` configure l'hôte Docker et crée les
moniteurs **Docker Container** manquants. Il est appelé :

- par `make up`, juste après la création du compte admin ;
- par `make up-service SERVICE=uptime-kuma` ;
- par les autres `make up-service SERVICE=<nom>` lorsque le conteneur
  `uptime-kuma` tourne déjà.

Cette dernière ligne est **volontaire** : elle permet de détecter le conteneur
qui vient d'être démarré et de lui ajouter un moniteur. Elle ne recrée pas le
compte admin ; celui-ci n'est créé que par `make up` ou
`make up-service SERVICE=uptime-kuma`.

Le script est idempotent :

1. il se connecte avec le compte admin de `.env` ;
2. il configure la notification Discord si
   `UPTIME_KUMA_DISCORD_WEBHOOK_URL` est renseignée (voir
   [Notifications](#notifications)) ;
3. il utilise l'hôte Docker `Local`, ou le crée avec l'URL
   `http://uptime-kuma-docker-proxy:2375` ;
4. il teste la connexion au proxy ;
5. il liste les conteneurs **en cours d'exécution** ;
6. il crée un moniteur `Docker - <nom>` pour chaque conteneur qui n'a pas déjà
   un moniteur Docker.

Il ne modifie et ne supprime jamais un moniteur existant. Les notifications
marquées par défaut dans Uptime Kuma sont associées aux **nouveaux** moniteurs
uniquement.

Quand rien n'a changé, le script n'affiche qu'une seule ligne :

```text
→ Uptime Kuma : 8 conteneur(s) détecté(s), aucun nouveau moniteur Docker, notification Discord à jour
```

Pour voir le détail (hôte, conteneurs déjà présents, etc.) :

```sh
sudo VERBOSE=1 make up-service SERVICE=<nom>
```

Pour lancer la synchronisation manuellement :

```sh
sudo make uptime-kuma-docker-sync
```

Après l'ajout d'un nouveau service, relancez cette commande ou
`sudo make up-service SERVICE=<nom>` lorsque Uptime Kuma tourne. Les moniteurs
HTTP/TCP classiques se créent toujours dans l'interface.

### Choisir les conteneurs

Tous les conteneurs en cours d'exécution visibles par le proxy sont surveillés,
y compris ceux qui ne font pas partie de ce dépôt. Pour en exclure :

```dotenv
UPTIME_KUMA_DOCKER_EXCLUDE=uptime-kuma,mon-conteneur
```

Relancez ensuite la synchronisation, puis supprimez dans l'interface le
moniteur déjà créé pour ce conteneur : la synchronisation ne recrée pas les
moniteurs exclus.

Pour désactiver entièrement la synchronisation automatique :

```dotenv
UPTIME_KUMA_DOCKER_SYNC=false
```

Un conteneur arrêté n'est pas ajouté lors d'une nouvelle synchronisation. S'il
possède déjà un moniteur, celui-ci passe **DOWN** et déclenche les
notifications configurées. Si un conteneur est recréé avec un **autre nom**,
un nouveau moniteur est ajouté ; l'ancien reste présent et doit être supprimé
manuellement.

### Ajouter un conteneur à la main

L'ajout manuel reste possible dans `Settings` > `Docker Hosts` puis
`Add New Monitor` > `Docker Container`. La synchronisation reconnaît les
moniteurs existants par le nom ou l'ID du conteneur et n'ajoute pas de doublon.

> La synchronisation se connecte avec `UPTIME_KUMA_ADMIN_USER` et
> `UPTIME_KUMA_ADMIN_PASSWORD`. Si vous changez le mot de passe dans
> l'interface, mettez aussi `.env` à jour, sinon la prochaine synchronisation
> échouera.

## Notifications

Une notification **Discord** est préconfigurée depuis `.env`. Le webhook est
la seule valeur à renseigner : le nom du bot, le préfixe et le nom de la
notification sont déjà prévus.

### Configurer le webhook Discord

1. Dans Discord, ouvrir les paramètres du serveur, puis
   `Intégrations` > `Webhooks` > `Nouveau webhook`.
2. Choisir le salon, puis copier l'URL du webhook.
3. Renseigner cette URL dans `.env` :

```dotenv
UPTIME_KUMA_DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

4. Relancer la synchronisation :

```sh
sudo make up
# ou
sudo make uptime-kuma-docker-sync
```

Le script crée ou met à jour la notification Discord. Elle apparaît dans
`Settings` > `Notifications`. Utilisez le bouton **Test** pour vérifier
l'envoi.

Tant que `UPTIME_KUMA_DISCORD_WEBHOOK_URL` est vide ou vaut `CHANGE_ME`, aucune
notification Discord n'est créée : les moniteurs continuent de fonctionner,
mais aucune alerte Discord n'est envoyée.

| Variable | Rôle | Exemple |
|---|---|---|
| `UPTIME_KUMA_DISCORD_ENABLED` | Active la configuration automatique de la notification | `true` |
| `UPTIME_KUMA_DISCORD_WEBHOOK_URL` | URL du webhook Discord, **à renseigner** | `https://discord.com/api/webhooks/...` |
| `UPTIME_KUMA_DISCORD_BOT_NAME` | Nom affiché du bot dans Discord | `Uptime Kuma` |
| `UPTIME_KUMA_DISCORD_PREFIX` | Préfixe du message envoyé | `[Uptime Kuma]` |
| `UPTIME_KUMA_DISCORD_NOTIFICATION_NAME` | Nom de la notification dans Uptime Kuma | `Discord` |
| `UPTIME_KUMA_DISCORD_DEFAULT` | Active la notification par défaut pour les nouveaux moniteurs | `true` |
| `UPTIME_KUMA_DISCORD_APPLY_EXISTING` | Applique la notification aux moniteurs déjà créés | `true` |

Le préfixe correspond au champ **Prefix Custom Message** d'Uptime Kuma : il
est envoyé comme texte d'accompagnement des alertes Discord.

La synchronisation ne supprime pas les autres notifications. Si une
notification Discord du même nom existe déjà, elle est mise à jour. Pour
désactiver la configuration automatique, passer
`UPTIME_KUMA_DISCORD_ENABLED=false` ou vider le webhook ; la notification
existante reste alors dans Uptime Kuma et peut être supprimée à la main.

Avec `UPTIME_KUMA_DISCORD_APPLY_EXISTING=true`, la notification est appliquée
à **tous** les moniteurs existants lors de sa création ou d'une modification
de sa configuration (webhook, nom du bot, préfixe ou caractère par défaut).
Une synchronisation sans changement ne réapplique rien : une notification
retirée manuellement d'un moniteur n'est pas réajoutée automatiquement. Pour
la réappliquer, supprimez la notification Discord dans l'interface puis
relancez la synchronisation, ou modifiez un des champs ci-dessus.

### Autre destination : e-mail via mailcow

Les notifications se configurent aussi dans `Settings` > `Notifications` >
`Setup Notification`. Pour un envoi par mailcow, utiliser une boîte dédiée,
par exemple `uptime@<domaine>`, puis une notification de type
**Email (SMTP)** :

| Champ | Exemple |
|---|---|
| Hostname | `mail.<domaine>` |
| Port | `587` |
| Security | `None` (STARTTLS automatique) |
| Username | `uptime@<domaine>` |
| Password | mot de passe de la boîte mailcow |
| From Email | `uptime@<domaine>` |
| To Email | `admin@<domaine>` |

Avec le port `587`, laisser `Security` sur `None` et ne pas cocher
`Disable STARTTLS`. Pour le port `465` (TLS implicite), choisir
`Security` = `TLS`.

mailcow n'est pas encore validé dans ce dépôt : testez l'envoi avec le bouton
de test avant de compter sur les alertes.

## Données et sauvegarde

Les données sont dans le volume `uptime-kuma-data` :

- base SQLite `kuma.db` ;
- moniteurs, notifications, status pages et réglages.

Le volume est marqué `should.backup=true` : `sudo make backup` l'inclut dans
l'archive. Aucun dump SQL n'est nécessaire.

L'archive du volume est créée à chaud. Pour une sauvegarde SQLite parfaitement
cohérente, arrêtez Uptime Kuma avant la sauvegarde :

```sh
sudo make stop SERVICE=uptime-kuma
sudo make backup
sudo make up-service SERVICE=uptime-kuma
```

Le proxy Docker peut rester démarré pendant la sauvegarde.

Lors d'une restauration, conservez la même valeur de
`UPTIME_KUMA_ADMIN_PASSWORD` que celle utilisée avant la sauvegarde, ou
sauvegardez `.env` séparément. Le compte admin est stocké dans la base, pas
dans `.env`.

La procédure complète est décrite dans
[Sauvegarde et restauration](../05-backup-restore.md).

## Mettre à jour Uptime Kuma

1. Sauvegarder : `sudo make backup`.
2. Changer `UPTIME_KUMA_VERSION` dans `.env`, par exemple `2.5.10` → `2.5.11`.
3. Pour mettre à jour le proxy Docker, changer aussi
   `UPTIME_KUMA_DOCKER_PROXY_VERSION`.
4. Recréer les conteneurs :

```sh
sudo make up-service SERVICE=uptime-kuma
```

Les versions sont publiées sur
[Docker Hub : Uptime Kuma](https://hub.docker.com/r/louislam/uptime-kuma/tags)
et
[Docker Hub : docker-socket-proxy](https://hub.docker.com/r/tecnativa/docker-socket-proxy/tags).

## Réinitialiser le mot de passe admin

Si le mot de passe est perdu, utiliser l'outil intégré à l'image :

```sh
docker exec -it uptime-kuma node extra/reset-password.js
```

Le compte admin existant est conservé ; seul son mot de passe change. Aucun
redémarrage n'est nécessaire.

## Nettoyer

```sh
sudo CONFIRM=yes make clean-service SERVICE=uptime-kuma
```

Le volume `uptime-kuma-data` est exclusif au service : `clean-service` le
supprime. Cette opération est destructive. Le conteneur
`uptime-kuma-docker-proxy` n'a pas de volume ; supprimez-le séparément si
nécessaire :

```sh
docker rm -f uptime-kuma-docker-proxy
```

## Dépannage

- **Le compte admin n'existe pas** : lancer `sudo make uptime-kuma-admin` et
  consulter les logs du conteneur. Si le volume a déjà été initialisé avec un
  autre mot de passe, utilisez `extra/reset-password.js`.
- **Les moniteurs Docker ne sont pas créés** : vérifier que
  `UPTIME_KUMA_DOCKER_SYNC` vaut `true`, puis lancer
  `sudo make uptime-kuma-docker-sync` et lire les messages affichés. Vérifier
  aussi que le compte admin de `.env` correspond toujours à celui de
  l'interface et que le proxy est démarré.
- **Le mot de passe admin a été changé dans l'interface** : reporter la même
  valeur dans `UPTIME_KUMA_ADMIN_PASSWORD`, sinon la synchronisation suivante
  échoue avec `authIncorrectCreds`.
- **Un conteneur indésirable est surveillé** : l'ajouter à
  `UPTIME_KUMA_DOCKER_EXCLUDE`, relancer la synchronisation, puis supprimer son
  moniteur dans l'interface. Sans exclusion, il serait recréé au prochain
  `make up`.
- **Erreur 502 via Traefik** : le conteneur n'est pas démarré ou termine son
  initialisation. Vérifier `make ps-service SERVICE=uptime-kuma`.
- **Le moniteur Docker renvoie 403** : le proxy refuse la requête. Vérifier
  `CONTAINERS=1`, `INFO=1` et `POST=0`, puis les logs
  `make logs-service SERVICE=uptime-kuma-docker-proxy`.
- **Impossible de joindre l'hôte Docker** : utiliser
  `http://uptime-kuma-docker-proxy:2375`, pas `localhost` ni
  `/var/run/docker.sock` (le socket n'est pas monté dans Uptime Kuma).
- **WebSocket ou login bloqué** : avec Traefik, le `Host` est conservé et le
  contrôle d'origine par défaut fonctionne. Vérifier les erreurs dans la
  console du navigateur et les logs Traefik. Ne passer à
  `UPTIME_KUMA_WS_ORIGIN_CHECK=bypass` qu'en dernier recours, derrière un
  reverse proxy qui réécrit le `Host`.
- **Le proxy Docker ne démarre pas** : sur certains hôtes avec SELinux ou
  AppArmor, le proxy peut nécessiter des permissions supplémentaires. Vérifier
  les logs avant d'ajouter des privilèges.

Logs :

```sh
sudo make logs-service SERVICE=uptime-kuma
sudo make logs-service SERVICE=uptime-kuma-docker-proxy
```

## Licence

Uptime Kuma est distribué sous licence **MIT**. Le proxy
`tecnativa/docker-socket-proxy` est distribué sous licence **Apache 2.0**.
