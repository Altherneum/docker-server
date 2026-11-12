# Dockhand - administration Docker

**Rôle :** interface web moderne pour administrer Docker : conteneurs, stacks
Compose, images, volumes, réseaux, logs, terminal, sauvegardes Restic et
environnements distants.

**Conteneur :** `dockhand`  
**Adresse :** `https://dockhand.<DOMAIN_NAME><TLD>`  
**Alias :** `docker`  
**Exemple :** `https://dockhand.supername.fr`

## Sécurité

Dockhand donne un accès complet au socket Docker de l'hôte : un utilisateur de
l'interface peut créer, modifier ou supprimer des conteneurs, lire des volumes
et exécuter des commandes. L'interface est donc protégée par **deux niveaux** :

1. HTTP Basic Auth par Traefik (`DOCKHAND_HTTP_USER` / `DOCKHAND_HTTP_PASSWORD`) ;
2. l'authentification propre à Dockhand, à activer au premier lancement.

L'authentification Dockhand est **désactivée par défaut**. Après la première
connexion, ouvrez `Settings` > `Authentication`, créez un compte administrateur
puis activez la protection.

> Dockhand est une console d'administration. Pour un serveur exposé sur
> Internet, gardez en plus l'accès derrière un VPN (WireGuard, Tailscale) ou
> une restriction d'adresse IP. Les mots de passe seuls ne suffisent pas à
> protéger un accès au socket Docker.

## Variables `.env`

| Variable | Rôle | Exemple |
|---|---|---|
| `DOCKHAND_VERSION` | Version de l'image, avec le préfixe `v` | `v1.0.57` |
| `DOCKHAND_PUID` | UID interne du conteneur | `1001` |
| `DOCKHAND_PGID` | GID interne du conteneur | `1001` |
| `DOCKHAND_ENCRYPTION_KEY` | Clé de chiffrement des identifiants Dockhand | générée par `make init` |
| `DOCKHAND_HTTP_USER` | Compte de la protection Traefik | `dockhand` |
| `DOCKHAND_HTTP_PASSWORD` | Mot de passe de la protection Traefik | généré par `make init` |
| `DOCKHAND_AUTO_LOCAL_ENV` | Enregistre automatiquement l'environnement Docker local | `true` |
| `DOCKER_GID` | GID du socket Docker de l'hôte | `960` |

`DOCKHAND_ENCRYPTION_KEY` et `DOCKER_GID` sont générés ou détectés par
`sudo make init`. `DOCKHAND_AUTO_LOCAL_ENV` vaut `true` par défaut.

## Démarrer / arrêter

```sh
sudo make up-service SERVICE=dockhand
sudo make ps-service SERVICE=dockhand
sudo make logs-service SERVICE=dockhand
sudo make stop SERVICE=dockhand
```

Le premier démarrage télécharge l'image Dockhand ; aucune compilation locale
n'est nécessaire.

## Premier lancement

1. Ouvrir `https://dockhand.<domaine>`.
2. Saisir le compte HTTP Basic défini par `DOCKHAND_HTTP_USER` et
   `DOCKHAND_HTTP_PASSWORD`.
3. Dans Dockhand, aller dans `Settings` > `Authentication`, créer le compte
   administrateur et activer l'authentification.
4. Vérifier que l'environnement `local` (`/var/run/docker.sock`) est présent
   dans `Settings` > `Environments`. Il est créé automatiquement au démarrage
   lorsque `DOCKHAND_AUTO_LOCAL_ENV=true` ; sinon, l'ajouter manuellement.

La configuration automatique n'a lieu qu'au premier démarrage, tant que
l'authentification Dockhand est désactivée. Elle est idempotente : un
environnement socket déjà existant n'est pas modifié. Pour la relancer
manuellement :

```sh
sudo make dockhand-local-env
```

## Socket Docker

Le socket de l'hôte est monté directement :

```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

Le conteneur ajoute automatiquement le groupe du socket au démarrage.
Avec `DOCKHAND_AUTO_LOCAL_ENV=true`, `make up` et
`make up-service SERVICE=dockhand` déclarent aussi l'environnement `local`
dans Dockhand. Si Dockhand affiche `permission denied` :

```sh
stat -c '%g' /var/run/docker.sock
sudo make init
sudo make up-service SERVICE=dockhand
```

Vérifiez que `DOCKER_GID` dans `.env` correspond au GID affiché.

Une alternative plus restrictive consiste à intercaler un proxy de socket
(`tecnativa/docker-socket-proxy`) et à ne monter le socket qu'en lecture seule.
Elle limite certaines fonctions, notamment le terminal et le navigateur de
fichiers.

## Données et sauvegarde

Les données Dockhand sont dans le volume `dockhand-data` :

- base SQLite ;
- stacks et dépôts Git gérés par Dockhand ;
- caches et snapshots.

La clé `DOCKHAND_ENCRYPTION_KEY` n'est **pas** stockée dans le volume : elle
reste dans `.env`. Le volume est marqué `should.backup=true` : `sudo make backup`
l'inclut dans l'archive. Aucun dump SQL n'est nécessaire.

L'archive du volume est créée à chaud. Pour une sauvegarde SQLite parfaitement
cohérente, arrêtez Dockhand avant la sauvegarde :

```sh
sudo make stop SERVICE=dockhand
sudo make backup
sudo make up-service SERVICE=dockhand
```

Sinon, utilisez la fonction de sauvegarde Restic intégrée à Dockhand.

Lors d'une restauration, conservez la **même** `DOCKHAND_ENCRYPTION_KEY` que
celle utilisée avant la sauvegarde (donc sauvegardez `.env` séparément). Sinon,
les identifiants et secrets stockés par Dockhand deviennent illisibles.
La procédure complète est décrite dans
[Sauvegarde et restauration](../05-backup-restore.md).

## Mettre à jour Dockhand

1. Sauvegarder : `sudo make backup`.
2. Changer `DOCKHAND_VERSION` dans `.env`, par exemple `v1.0.57` → `v1.0.58`.
3. Recréer le conteneur :

```sh
sudo make up-service SERVICE=dockhand
```

Les tags de l'image officielle utilisent le préfixe `v`. La version courante est
publiée sur [Docker Hub](https://hub.docker.com/r/fnsys/dockhand/tags).

## Licence

Dockhand est distribué sous **BSL 1.1** (`Business Source License`). L'usage
personnel, le homelab, les associations, les écoles et les travailleurs
indépendants sont gratuits. La production des systèmes d'une organisation avec
salariés nécessite une licence commerciale. Voir le fichier `LICENSE.txt` du
dépôt officiel.

## Nettoyer

```sh
sudo CONFIRM=yes make clean-service SERVICE=dockhand
```

Le volume `dockhand-data` est exclusif au service : `clean-service` le supprime.
Cette opération est destructive.

## Dépannage

- **Permission refusée sur le socket Docker** : `DOCKER_GID` est vide ou ne
  correspond pas au GID du socket. Lancer `sudo make init` puis recréer le
  conteneur.
- **Identifiants ou environnements illisibles** : la clé
  `DOCKHAND_ENCRYPTION_KEY` a changé. Restaurez la valeur d'origine ou la
  sauvegarde du volume.
- **Erreur 502 via Traefik** : le conteneur n'est pas démarré ou termine son
  initialisation. Consulter les logs.
- **Erreur 500 sur le middleware `dockhand-auth`** : le fichier
  `stacks/proxy/auth/dockhand.htpasswd` est absent. Lancer `sudo make init`.
  Si le middleware vient d'être ajouté au template, reconstruire Traefik avec
  `sudo make up-service SERVICE=traefik`.
- **Terminal ou navigateur de fichiers indisponible** : ces fonctions utilisent
  l'API `exec` de Docker. Elles ne fonctionnent pas avec un proxy de socket qui
  n'autorise pas `EXEC`.

Logs :

```sh
sudo make logs-service SERVICE=dockhand
```
