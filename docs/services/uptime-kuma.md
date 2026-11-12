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

`UPTIME_KUMA_ADMIN_PASSWORD` est généré par `sudo make init`. Il n'est pas
passé au conteneur de façon permanente : le script l'utilise uniquement pour
créer le compte.

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
`sudo make uptime-kuma-admin` après le démarrage : le script n'est alors pas
appelé automatiquement.

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

Pour ajouter l'hôte Docker :

1. `Settings` > `Docker Hosts` > `Set Up Docker Host`.
2. `Friendly Name` : `Local`.
3. `Connection Type` : `TCP`.
4. `Docker Daemon` : `http://uptime-kuma-docker-proxy:2375`.
5. Cliquer sur `Test`, puis `Save`.

Ensuite, ajoutez un moniteur de type **Docker Container**, choisissez l'hôte
`Local` et le conteneur à surveiller. Les moniteurs HTTP/TCP classiques ne
nécessitent pas le proxy.

## Notifications

Les notifications se configurent dans `Settings` > `Notifications`. Uptime Kuma
ne les lit pas dans `.env`.

Pour un envoi par mailcow, utiliser une boîte dédiée, par exemple
`uptime@<domaine>`, puis un notification de type **Email (SMTP)** :

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
