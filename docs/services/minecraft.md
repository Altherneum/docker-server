# Minecraft

**Rôle :** serveur Minecraft Java et Bedrock avec un proxy Velocity et huit
serveurs Paper.

**Conteneurs :**

- `velocity` : point d'entrée des joueurs ;
- `mc-plugins` : télécharge les plugins puis s'arrête ;
- `mc-hub`, `mc-survie`, `mc-creatif`, `mc-anarchie`, `mc-rpg`, `mc-skyblock`,
  `mc-opprison`, `mc-test` : serveurs de jeu.

## Stockage

| Chemin | Contenu | Volume |
|---|---|---|
| `/data` | Monde, `server.properties`, `plugins/`, `config/`, caches et logs du serveur | `mc-<serveur>-data` (un par serveur) |
| `/data/plugins/plugin` | Configuration propre au plugin (par serveur) | `mc-<serveur>-data` |
| `/plugin/DataFolder` | Données partagées du plugin : `players/`, `islands/`, `structures/`, argent, grades, tags… | `mc-plugin-data` (partagé) |
| `/opt/plugins` | JAR des plugins téléchargés (lecture seule) | `mc-plugins` (partagé) |
| `/data` (Velocity) | Configuration et plugins de Velocity | `mc-velocity-data` |

Les mondes ne sont jamais dans le volume partagé : chaque serveur garde son
propre volume. Seules les données du plugin qui doivent être communes (argent,
grades, tags, îles) sont dans `mc-plugin-data`.

## Adresses

| Usage | Adresse |
|---|---|
| Java | `mc.<DOMAIN_NAME><TLD>:25565` |
| Bedrock | `mc.<DOMAIN_NAME><TLD>` port `19132` |
| Accès direct à un serveur | `<serveur>.<domaine>:25565` |

Exemple avec `supername.fr` :

```text
mc.supername.fr:25565          (Java)
mc.supername.fr:19132          (Bedrock)
survie.supername.fr:25565      (accès direct)
```

## Mots de passe

Les joueurs n'ont pas de mot de passe à saisir dans le jeu.

| Variable `.env` | Utilisation |
|---|---|
| `VELOCITY_SECRET` | Secret interne entre Velocity et Paper |
| `MINECRAFT_RCON_PASSWORD` | Administration RCON interne |

Ces secrets sont générés par `make init`. Ils ne doivent pas être partagés avec
les joueurs.

## Variables `.env` utiles

| Variable | Rôle |
|---|---|
| `MINECRAFT_PORT` | Port Java exposé par Traefik (`25565`) |
| `MINECRAFT_LEVEL_NAME` | Nom du monde par défaut |
| `MINECRAFT_MAX_PLAYERS` | Nombre maximum de joueurs |
| `MINECRAFT_MEMORY_*` | RAM allouée à chaque serveur Paper |
| `VELOCITY_MEMORY` | RAM allouée au proxy |
| `VELOCITY_SECRET` | Secret Velocity / Paper |
| `VELOCITY_ONLINE_MODE` | `true` premium, `false` hors-ligne |
| `VELOCITY_MOTD` | Message affiché dans la liste des serveurs (`\n` pour un saut de ligne) |
| `MINECRAFT_RCON_PASSWORD` | Mot de passe RCON |
| `MINECRAFT_RCON_PORT` | Port RCON utilisé par Paper et Azuriom (`25575`) |
| `MINECRAFT_DISCORD_TOKEN_*` | Jeton du bot Discord de chaque serveur (un bot par serveur) |

Les variables `MINECRAFT_DISCORD_TOKEN_HUB`, `MINECRAFT_DISCORD_TOKEN_SURVIE`,
`MINECRAFT_DISCORD_TOKEN_CREATIF`, `MINECRAFT_DISCORD_TOKEN_ANARCHIE`,
`MINECRAFT_DISCORD_TOKEN_RPG`, `MINECRAFT_DISCORD_TOKEN_SKYBLOCK`,
`MINECRAFT_DISCORD_TOKEN_OPPRISON` et `MINECRAFT_DISCORD_TOKEN_TEST` sont
transmises au plugin via `DISCORD_BOT_TOKEN`. Laisser une valeur vide désactive
le bot de ce serveur.

Les variables `MINECRAFT_MEMORY_HUB`, `MINECRAFT_MEMORY_SURVIE`,
`MINECRAFT_MEMORY_CREATIF`, `MINECRAFT_MEMORY_ANARCHIE`,
`MINECRAFT_MEMORY_RPG`, `MINECRAFT_MEMORY_SKYBLOCK`,
`MINECRAFT_MEMORY_OPPRISON` et `MINECRAFT_MEMORY_TEST` règlent la mémoire de
chaque serveur.

## Démarrer

Pour tout démarrer :

```sh
sudo make up
```

Ou service par service :

```sh
sudo make up-service SERVICE=velocity
sudo make up-service SERVICE=mc-hub
sudo make up-service SERVICE=mc-survie
sudo make up-service SERVICE=mc-creatif
sudo make up-service SERVICE=mc-anarchie
sudo make up-service SERVICE=mc-rpg
sudo make up-service SERVICE=mc-skyblock
sudo make up-service SERVICE=mc-opprison
sudo make up-service SERVICE=mc-test
```

`mc-plugins` démarre automatiquement avant les autres. Il s'arrête une fois les
plugins téléchargés : c'est normal.

Si les joueurs sont refusés (`Connexion refusée`, erreur `-111`) alors que les
conteneurs tournent, vérifiez la joignabilité IPv4 et IPv6 du port 25565 :
[Connexion refusée en IPv4, services OK en IPv6](../06-depannage.md#connexion-refusée-en-ipv4-services-ok-en-ipv6).

## Arrêter

```sh
sudo make stop SERVICE=velocity
sudo make stop SERVICE=mc-hub
sudo make stop SERVICE=mc-survie
sudo make stop SERVICE=mc-creatif
sudo make stop SERVICE=mc-anarchie
sudo make stop SERVICE=mc-rpg
sudo make stop SERVICE=mc-skyblock
sudo make stop SERVICE=mc-opprison
sudo make stop SERVICE=mc-test
```

## Nettoyer

```sh
sudo CONFIRM=yes make clean-service SERVICE=mc-hub
```

Chaque serveur a son propre volume de monde. `clean-service` supprime ce volume
et donc le monde du serveur. Les volumes `mc-plugins` et `mc-plugin-data` sont
partagés : ils sont conservés.

Pour supprimer aussi Velocity :

```sh
sudo CONFIRM=yes make clean-service SERVICE=velocity
```

## Premium et hors-ligne

| Mode | `VELOCITY_ONLINE_MODE` | Azuriom |
|---|---|---|
| Premium Microsoft | `true` | `AZURIOM_GAME=mc-online` |
| Comptes locaux | `false` | `AZURIOM_GAME=mc-offline` |

Les deux valeurs doivent être cohérentes. En mode premium, le joueur doit
posséder Minecraft Java.

## Mondes initiaux (maps)

Les cartes de départ sont livrées avec l'image Paper, dans
`stacks/minecraft/paper/maps/<Carte>/Spawn.zip`. Au premier démarrage d'un
serveur, l'entrypoint extrait la carte dans son volume `/data` ; les démarrages
suivants conservent le monde et les modifications des joueurs.

| Serveur | Carte utilisée |
|---|---|
| `mc-hub` | `Hub` |
| `mc-survie` | `Survie` |
| `mc-anarchie` | `Survie` |
| `mc-test` | `Survie` |
| `mc-skyblock` | `SkyBlock` |
| `mc-opprison` | `OPPrison` |
| `mc-creatif` | génération vanilla |
| `mc-rpg` | génération vanilla |

Les cartes contiennent un monde nommé `Spawn`. `MINECRAFT_LEVEL_NAME` doit donc
rester `Spawn` pour qu'elles soient utilisées.

L'extraction n'a lieu que si le monde est absent ou si le fichier de carte a
changé depuis la dernière installation. Après une mise à jour du dépôt qui
modifie une carte, reconstruisez l'image et redémarrez le serveur concerné :

```sh
sudo make paper-base
sudo make up-service SERVICE=mc-hub
```

Le monde est alors réinstallé depuis l'archive : les modifications locales de
ce monde sont remplacées. Pour repartir d'une carte propre sans mise à jour :

```sh
sudo CONFIRM=yes make clean-service SERVICE=mc-hub
sudo make up-service SERVICE=mc-hub
```

## Resource pack

Le pack est envoyé aux joueurs Java par chaque serveur Paper. L'URL vient de
`AZURIOM_RESOURCE_PACK_URL` (dans `.env`) et doit pointer directement vers un
`resourcePack.zip` :

```dotenv
AZURIOM_RESOURCE_PACK_URL=https://github.com/Altherneum/resourcePack/releases/latest/download/resourcePack.zip
```

Au démarrage, Paper télécharge le pack dans son cache (`/data/cache`) pour
calculer son SHA-1 et l'inscrit dans `server.properties` avec l'URL. Le hash
permet aux clients de vérifier le fichier ; il n'est pas fourni par GitHub.

Le pack n'a pas besoin d'Azuriom pour fonctionner : l'URL GitHub est publique.
Si vous préférez servir le pack depuis Azuriom, pointez l'URL vers
`https://minecraft.<DOMAIN_NAME><TLD>/storage/zip/resourcePack.zip` ; Azuriom le
télécharge alors dans son volume et l'expose via `/storage`. Dans ce cas,
démarrez Azuriom avant les serveurs Paper pour que le hash puisse être calculé
au premier démarrage.

Pour appliquer une nouvelle version du pack, redémarrez les serveurs Paper :
ils retéléchargent le fichier et mettent à jour le SHA-1.

## Plugins

`mc-plugins` télécharge notamment :

- le plugin ;
- ViaVersion et ViaBackwards ;
- WorldEdit (serveur créatif uniquement) ;
- Geyser et Floodgate pour Bedrock.

Les plugins sont copiés dans un volume partagé. Pour les mettre à jour,
relancez :

```sh
sudo make up-service SERVICE=mc-plugins
```

## Données partagées du plugin

Les huit serveurs Paper partagent le volume `mc-plugin-data`, monté sur
`/plugin/DataFolder`. Le plugin maison y stocke les données communes : argent,
grades, tags, données d'îles, etc.

Le plugin calcule son dossier de données depuis `/data/plugins/plugin` (trois
niveaux au-dessus), soit `/DataFolder`. L'entrypoint crée donc le lien
`/DataFolder` → `/plugin/DataFolder`.

Chaque serveur déduit son type de la variable `SERVER_NAME` (`hub`, `survie`,
`creatif`, etc.). Il n'y a donc plus de fichier `serverTypeFile.yml` ni de ports
internes différents. Le fichier `serverTypeFile.yml` d'une ancienne installation
est ignoré et peut être supprimé du volume. Le serveur `test` est traité comme
`Survie`, l'enum du plugin n'ayant pas de type `Test`.

Chaque serveur Paper reçoit aussi son propre jeton Discord via
`DISCORD_BOT_TOKEN`, alimenté par `MINECRAFT_DISCORD_TOKEN_<SERVEUR>`. Chaque
serveur a donc son propre bot. L'ancien fichier `tokens.yml` n'est plus utilisé.

Pour repartir des données de l'ancienne installation, copier son
`Serveurs/DataFolder` dans le volume avant le premier démarrage :

```sh
docker run --rm \
    -v mc-plugin-data:/target \
    -v /chemin/vers/Serveurs/DataFolder:/source:ro \
    alpine:3.24 sh -c 'mkdir -p /target && cp -a /source/. /target/'
```

> Les anciens fichiers `serverTypeFile.yml` et `tokens.yml` peuvent être
> supprimés du volume : ils ne sont plus lus par le plugin.

Après une modification de l'entrypoint, reconstruire l'image Paper puis
redémarrer les serveurs :

```sh
sudo make paper-base
sudo make up
```

Après une nouvelle release du plugin, relancer le téléchargement puis redémarrer
les serveurs :

```sh
sudo make up-service SERVICE=mc-plugins
sudo make up
```

Le tab en jeu affiche `Plugin : <version> (<date de compilation>)` : si la date
ne correspond pas à la release, le jar n'a pas été remplacé.

Les structures du plugin (`Island.yml`, `spawn_*.yml`, `mine.yml`) sont
versionnées dans ce dépôt (`stacks/minecraft/paper/structures/`) et copiées par
`mc-plugins` dans le volume `mc-plugin-data` (uniquement si elles sont
absentes, pour ne jamais écraser une structure retouchée en jeu) :

```sh
docker exec mc-skyblock ls -la /DataFolder/structures/
```

Le téléchargement se fait depuis `raw.githubusercontent.com` sur la branche
`main` : les structures doivent donc être **poussées** avant de lancer
`mc-plugins`. En cas d'échec, les serveurs démarrent quand même et le plugin
indique les fichiers manquants dans la console
(`Structure Island introuvable : /DataFolder/structures/Island.yml`).

## Performances

La configuration Paper livrée est réglée pour un VPS de **6 vCPU** avec 3 à 4
serveurs Paper en parallèle (velocity + hub, puis skyblock et survie).

| Réglage | Valeur | Pourquoi |
|---|---|---|
| `chunk-system.worker-threads` | `2` | 2 threads de génération par serveur : avec 3 serveurs actifs, les threads de chunks ne prennent pas toute la machine et les threads principaux restent réactifs |
| `chunk-system.io-threads` | `2` | lecture/écriture des chunks, largement suffisant sur disque local |
| `chunk-loading-basic.player-max-chunk-generate-rate` | `25.0` | une création d'île ou une arrivée ne peut pas monopoliser la génération de chunks au détriment des autres joueurs |

À éviter : augmenter `worker-threads` pour « aller plus vite ». Les threads de
chunks sont gourmands en CPU ; au-delà de 2 par serveur sur ce VPS, les threads
principaux sont affamés et le serveur paraît bloqué (tick spikes, watchdog).

Côté mémoire, avec ~8 Go disponibles pour Minecraft, `MINECRAFT_MEMORY_HUB=1G`
suffit, et `MINECRAFT_MEMORY_SKYBLOCK` / `MINECRAFT_MEMORY_SURVIE` peuvent être
montés à `2G` pour limiter les pauses GC quand beaucoup d'îles sont chargées.

> `paper-global.yml` n'est copié dans `/data/config/` qu'au **premier**
> démarrage d'un serveur. Sur une installation existante, reporter les valeurs
> dans `/data/config/paper-global.yml` (ou supprimer ce fichier puis redémarrer
> pour repartir de la version de l'image).

## Tester le plugin en local

Le dépôt du plugin fournit un script qui compile le plugin et lance un serveur
Paper hors-ligne dans Docker, sans toucher à la production :

- Script : <https://github.com/Altherneum/plugin/blob/main/scripts/test-local.sh>
- Dépôt : <https://github.com/Altherneum/plugin>

```sh
git clone https://github.com/Altherneum/plugin
cd plugin
./scripts/test-local.sh
```

Le script réutilise la configuration et les cartes de ce dépôt
(`stacks/minecraft/paper/config/paper-global.yml` et
`maps/<Carte>/Spawn.zip`) s'il les trouve dans `~/repo/docker-server` ; sinon il
démarre avec la configuration Paper par défaut et un monde superflat
(`DOCKER_SERVER_DIR=/chemin/vers/docker-server` pour forcer le chemin).

Le type de serveur se choisit avec `--server` (`hub`, `skyblock`, `survie`,
`creatif`, `anarchie`, `rpg`, `opprison`, `test`) :

```sh
./scripts/test-local.sh --server hub
./scripts/test-local.sh --server survie --port 25566
```

Le script installe la carte et les structures correspondantes (spawn_SB,
spawn_Survie, spawn_OPPrison, mine, Island) depuis ce dépôt et
`~/repo/server/Serveurs/DataFolder`. Le type est transmis au plugin par
`SERVER_NAME` : le port ne sert qu'à se connecter.

Le domaine affiché par le plugin (tab, boss bar, MOTD) vient de `DOMAIN_NAME` +
`TLD` ; en local le script utilise `localhost` sans TLD (aucun `.test`), et
`DOMAIN_NAME=example TLD=.test ./scripts/test-local.sh` permet de simuler un
domaine.

Prérequis sur la machine de dev : Docker, Maven + JDK 21, Python 3, curl,
unzip. Détails, options et déroulé du test : voir le README du dépôt plugin.

## Sauvegarde

`make backup` archive les mondes des serveurs Paper, les données partagées du
plugin (`mc-plugin-data`) et la configuration de Velocity. Le volume des
plugins (`mc-plugins`) n'est pas sauvegardé : il peut être retéléchargé.
