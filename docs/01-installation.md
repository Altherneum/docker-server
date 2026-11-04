# Installation

## Ce qu'il faut

- Un serveur Linux vierge (Alpine, Arch, Debian ou Ubuntu).
- Un accès root ou sudo.
- Un nom de domaine si vous voulez du HTTPS accessible depuis Internet.
- Une clé SSH publique créée sur votre poste.

`install.sh` installe les paquets nécessaires : Docker, Docker Compose, `git`,
`make`, `openssl`, puis OpenSSH, UFW, `rsyslog` (Debian/Arch) et les mises à
jour automatiques. fail2ban est fourni par le conteneur `stacks/fail2ban/`.

## Méthode simple (recommandée)

### 1. Cloner le dépôt

```sh
git clone https://github.com/lx78WyY0J5/docker-server.git
cd docker-server
```

### 2. Créer et remplir `.env`

```sh
cp .env.example .env
chmod 600 .env
nano .env
```

Renseignez au minimum :

- `DOMAIN_NAME` et `TLD` ;
- les webhooks Discord si vous les utilisez
  (`DISCORD_WEBHOOK_SSH`, `DISCORD_WEBHOOK_SESSION`) ;
- les autres valeurs utiles.

Les secrets encore à `CHANGE_ME` seront générés automatiquement par
`install.sh` via `make init`.

### 3. Créer sa clé SSH et la copier

Sur **votre poste** :

```sh
ssh-keygen -t ed25519 -C "admin@mon-poste"
scp ~/.ssh/id_ed25519.pub root@<ip-du-serveur>:/tmp/id_ed25519.pub
```

La clé privée `~/.ssh/id_ed25519` reste sur votre poste. Seule la clé publique
est copiée sur le serveur.

### 4. Lancer l'installation

```sh
sudo ./install.sh --pubkey-file /tmp/id_ed25519.pub
```

La clé publique est **obligatoire**. `install.sh` :

- vérifie la clé avant toute modification ;
- installe les paquets et Docker ;
- clone ou met à jour le dépôt ;
- génère `.env`, les secrets et les réseaux Docker ;
- crée le compte admin ;
- configure SSH, UFW et les mises à jour automatiques ; fail2ban est lancé
  avec les conteneurs ;
- définit le nom d'hôte de la machine avec `DOMAIN` (`DOMAIN_NAME` + `TLD`)
  et installe un prompt `utilisateur@DOMAIN`, par exemple `admin@localhost`
  ou `root@altherneum.fr`.

### 5. Tester la connexion SSH

Ouvrez un **second terminal** et testez la connexion avant de fermer la
session d'installation :

```sh
ssh -p <port> admin@<ip-du-serveur>
su -
```

Le port est `HARDEN_SSH_PORT` dans `.env` (`22` par défaut). Aucun rollback
global n'est prévu : les fichiers modifiés sont sauvegardés dans
`/var/backups/harden/` pour une restauration manuelle. Seule la configuration
sshd est restaurée automatiquement si `sshd -t` échoue.

Guide détaillé : [Sécurisation de l'hôte](07-securisation.md).

### 6. Démarrer tous les conteneurs

Depuis la racine du dépôt :

```sh
sudo make check-env
sudo make up
sudo make ps
```

`make up` construit les images manquantes, démarre tous les services et crée
le compte admin Forgejo.

Le conteneur `fail2ban` lit les logs SSH de l'hôte. Sur Debian/Ubuntu, vérifiez
que `/var/log/auth.log` existe ; sinon, consultez la
[fiche fail2ban](services/fail2ban.md).

## Conteneurs disponibles

Chaque service peut être lancé seul avec :

```sh
sudo make up-service SERVICE=<nom>
```

| Service | Rôle | Commande |
|---|---|---|
| `traefik` | Proxy HTTPS et certificats | `sudo make up-service SERVICE=traefik` |
| `php-site` | Site PHP | `sudo make up-service SERVICE=php-site` |
| `db-php` | Base MariaDB du site PHP | `sudo make up-service SERVICE=db-php` |
| `phpmyadmin` | Administration des bases | `sudo make up-service SERVICE=phpmyadmin` |
| `keeweb` | Gestionnaire de mots de passe | `sudo make up-service SERVICE=keeweb` |
| `meme` | Site de memes | `sudo make up-service SERVICE=meme` |
| `forgejo` | Serveur Git Forgejo | `sudo make up-service SERVICE=forgejo` |
| `db-forgejo` | Base PostgreSQL de Forgejo | `sudo make up-service SERVICE=db-forgejo` |
| `code-server` | VS Code dans le navigateur | `sudo make up-service SERVICE=code-server` |
| `azuriom` | Site et boutique Minecraft | `sudo make up-service SERVICE=azuriom` |
| `db-azuriom` | Base MariaDB d'Azuriom | `sudo make up-service SERVICE=db-azuriom` |
| `velocity` | Proxy des joueurs Minecraft | `sudo make up-service SERVICE=velocity` |
| `mc-hub` | Serveur Minecraft Hub | `sudo make up-service SERVICE=mc-hub` |
| `mc-survie` | Serveur Minecraft Survie | `sudo make up-service SERVICE=mc-survie` |
| `mc-creatif` | Serveur Minecraft Créatif | `sudo make up-service SERVICE=mc-creatif` |
| `mc-anarchie` | Serveur Minecraft Anarchie | `sudo make up-service SERVICE=mc-anarchie` |
| `mc-rpg` | Serveur Minecraft RPG | `sudo make up-service SERVICE=mc-rpg` |
| `mc-skyblock` | Serveur Minecraft Skyblock | `sudo make up-service SERVICE=mc-skyblock` |
| `mc-opprison` | Serveur Minecraft OP Prison | `sudo make up-service SERVICE=mc-opprison` |
| `mc-test` | Serveur Minecraft de test | `sudo make up-service SERVICE=mc-test` |
| `mc-plugins` | Prépare les plugins Minecraft (one-shot) | `sudo make up-service SERVICE=mc-plugins` |
| `bot` | Bot Discord | `sudo make up-service SERVICE=bot` |
| `fail2ban` | Bannit les IP sur les journaux Traefik et SSH | `sudo make up-service SERVICE=fail2ban` |

Pour connaître la liste exacte des services :

```sh
sudo make services
```

## Commandes utiles

Toutes les commandes se lancent depuis la racine du dépôt.

### Global

| Commande | Effet |
|---|---|
| `sudo make up` | Démarre tous les conteneurs |
| `sudo make down` | Arrête tout sans supprimer les conteneurs |
| `sudo make restart` | Redémarre tout |
| `sudo make ps` | Affiche l'état des conteneurs |
| `sudo make logs` | Suit les logs de tous les services |
| `sudo make build` | Construit toutes les images |
| `sudo make check-env` | Vérifie les secrets de `.env` |
| `sudo make backup` | Sauvegarde les bases et les volumes |
| `sudo make restore BACKUP=backups/AAAA-MM-JJ_HHMMSS` | Restaure une sauvegarde |
| `sudo CONFIRM=yes make clean` | Supprime tous les conteneurs et volumes (destructif) |
| `sudo CONFIRM=yes make down-clean` | Arrête puis supprime tout (destructif) |

### Un seul service

| Commande | Effet |
|---|---|
| `sudo make up-service SERVICE=azuriom` | Installe et démarre un service |
| `sudo make stop SERVICE=azuriom` | Arrête un service |
| `sudo make restart-service SERVICE=azuriom` | Redémarre un service |
| `sudo make ps-service SERVICE=azuriom` | Affiche l'état d'un service |
| `sudo make logs-service SERVICE=azuriom` | Suit les logs d'un service |
| `sudo make down-service SERVICE=azuriom` | Arrête sans supprimer le conteneur |
| `sudo CONFIRM=yes make clean-service SERVICE=azuriom` | Supprime le conteneur et ses volumes exclusifs (destructif) |
| `sudo CONFIRM=yes make down-clean-service SERVICE=azuriom` | Arrête puis supprime le service (destructif) |

### Maintenance

| Commande | Effet |
|---|---|
| `sudo make forgejo-admin` | Crée le compte admin Forgejo depuis `.env` |
| `sudo CONFIRM=yes make azuriom-seed` | Réapplique les données de démonstration Azuriom |
| `sudo make mail-up` | Démarre mailcow |
| `sudo make mail-down` | Arrête mailcow |
| `sudo make mail-logs` | Suit les logs de mailcow |
| `sudo make php-site-src` | Met à jour le dépôt du site PHP |

La liste complète est disponible dans [Commandes](03-commandes.md).

## Mettre à jour le serveur

```sh
cd /opt/docker-server
sudo git -c safe.directory=/opt/docker-server pull --ff-only
sudo ./install.sh --pubkey-file /tmp/id_ed25519.pub
sudo make build
sudo make up
```

`install.sh` est idempotent : il remet à jour les paquets, `.env`, le compte
admin et la sécurisation sans supprimer les données.

## Installation manuelle

Cette section explique ce que fait `install.sh`, si vous préférez installer
les paquets et sécuriser l'hôte à la main.

### 1. Mettre à jour le système

| Distribution | Commande |
|---|---|
| Debian / Ubuntu | `sudo apt update && sudo apt upgrade -y` |
| Alpine | `sudo apk update && sudo apk upgrade` |
| Arch | `sudo pacman -Syu` |

### 2. Installer les paquets

Paquets principaux utilisés par le projet :

| Distribution | Paquets |
|---|---|
| Debian / Ubuntu | `git curl make openssl ca-certificates gnupg lsb-release sudo ufw openssh-server unattended-upgrades rsyslog` |
| Alpine | `git curl make openssl ca-certificates sudo ufw openssh docker docker-cli-compose docker-cli-buildx docker-openrc` |
| Arch | `git curl make openssl ca-certificates sudo ufw openssh rsyslog docker docker-compose` |

Sous Debian/Ubuntu, Docker et le plugin Compose s'installent depuis le dépôt
officiel Docker :

- <https://docs.docker.com/engine/install/>

Paquets Docker attendus : `docker-ce`, `docker-ce-cli`, `containerd.io`,
`docker-buildx-plugin`, `docker-compose-plugin`.

Vérifiez ensuite que Docker répond :

```sh
docker --version
docker compose version
```

### 3. Récupérer le dépôt et générer `.env`

```sh
git clone https://github.com/lx78WyY0J5/docker-server.git
cd docker-server
cp .env.example .env
chmod 600 .env
nano .env
sudo make init
```

`make init` génère les secrets encore à `CHANGE_ME` et crée les réseaux Docker.

### 4. Sécuriser l'hôte manuellement

Voici ce que `install.sh` fait automatiquement :

- crée le compte `admin` et l'ajoute à `sudo` et `docker` ;
- installe la clé publique dans `/home/admin/.ssh/authorized_keys`
  (droits `700` et `600`) ;
- écrit une configuration sshd qui bloque le mot de passe et root :
  `PasswordAuthentication no`, `PermitRootLogin no`,
  `PubkeyAuthentication yes` ;
- applique le port `HARDEN_SSH_PORT` dans sshd et UFW, et le transmet à fail2ban ;
- configure UFW : refus des connexions entrantes, SSH limité, ports
  `80`, `443` et Minecraft ;
- le conteneur fail2ban lit les logs SSH de l'hôte et bannit les tentatives ;
- active les mises à jour automatiques Linux ;
- définit le nom d'hôte avec `DOMAIN` et installe le prompt
  `utilisateur@DOMAIN` ;
- installe le MOTD et les webhooks Discord si configurés ;
- passe `.env` en `600` ;
- sauvegarde les fichiers modifiés dans `/var/backups/harden/`.

Si vous faites cette étape à la main, testez toujours SSH dans un second
terminal avant de fermer votre session.

### 5. Démarrer les services

```sh
sudo make check-env
sudo make up
sudo make ps
```

## Configurer le domaine

Dans `.env` :

```dotenv
DOMAIN_NAME=monprojet
TLD=.com
ACME_EMAIL=admin@monprojet.com
```

- `DOMAIN_NAME` : sans extension.
- `TLD` : avec le point, ou vide pour un domaine local.
- `ACME_EMAIL` : adresse utilisée par Let's Encrypt pour les certificats.

Créez ensuite les enregistrements DNS :

| Type | Nom | Valeur |
|---|---|---|
| `A` (ou `AAAA`) | `monprojet.com` | IP publique du serveur |
| `A` (ou `AAAA`) | `*.monprojet.com` | IP publique du serveur |

Le wildcard `*.monprojet.com` couvre tous les sous-domaines (`git`, `php`,
`minecraft`, `code`, etc.). Il ne couvre pas le domaine nu : gardez
l'enregistrement `A`/`AAAA` sur l'apex. Si vous ne pouvez pas utiliser de
wildcard, créez un enregistrement pour chaque sous-domaine utilisé.

> Le tableau minimal, les exceptions à deux niveaux comme `git.arch` et les
> enregistrements mail sont détaillés dans [DNS](08-dns.md).

## Ports à ouvrir

| Port | Protocole | Utilité |
|---|---|---|
| `HARDEN_SSH_PORT` (`22`) | TCP | SSH |
| `80` | TCP | Redirection HTTP et validation des certificats |
| `443` | TCP | Sites HTTPS |
| `MINECRAFT_PORT` (`25565`) | TCP | Minecraft Java |
| `19132` | TCP + UDP | Minecraft Bedrock (Geyser) |
| `19133` | UDP | Minecraft Bedrock récent (NetherNet) |

Sans les ports `80` et `443`, les certificats HTTPS ne peuvent pas être créés.

> `MINECRAFT_RCON_PORT` n'est pas ouvert dans UFW et Docker ne le publie pas
> sur l'hôte : il reste utilisé sur le réseau interne. Le port `8080`
> (code-server) reste également interne.

## Premier démarrage

Au premier `make up` :

- les images de base sont construites si nécessaire ;
- le dépôt du site PHP est cloné dans `stacks/web/php-site/src` ;
- les mondes Minecraft sont extraits des cartes livrées avec l'image Paper ;
- les bases de données sont initialisées ;
- les certificats HTTPS sont demandés à Let's Encrypt lors du premier accès.

Vérifiez ensuite :

```sh
sudo make ps
sudo make logs
```

Le compte administrateur Forgejo est créé automatiquement par `make up`. Pour
le créer manuellement (ou après suppression des volumes) :

```sh
sudo make forgejo-admin
```

## Sans domaine public (test local)

Avec `DOMAIN_NAME=localhost` et `TLD=` (vide), les adresses ressemblent à
`https://git.localhost`. Let's Encrypt ne peut pas délivrer de certificat pour
`localhost`. Pour un test local, utilisez un vrai domaine, ou adaptez la
configuration TLS de Traefik. Les services restent accessibles en interne, mais
le navigateur affichera un avertissement de certificat.
