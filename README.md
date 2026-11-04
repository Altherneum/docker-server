# Docker Server

Infrastructure Docker : proxy HTTPS, sites web, forge Git, éditeur de code, gestionnaire de mots de passe, serveurs Minecraft, bot Discord, messagerie et sauvegardes.

## Documentation

La documentation complète pour débutants est dans [`docs/`](docs/README.md).

| Guide | Contenu |
|---|---|
| [Démarrage rapide](docs/README.md) | Installer, configurer et lancer |
| [Installation](docs/01-installation.md) | Installation simple ou manuelle, conteneurs, commandes, DNS, ports |
| [Sécurisation de l'hôte](docs/07-securisation.md) | Compte admin, SSH, UFW, fail2ban, mises à jour |
| [Configuration `.env`](docs/02-configuration-env.md) | Variables et mots de passe |
| [Commandes](docs/03-commandes.md) | Démarrer, arrêter, nettoyer |
| [Accès et URL](docs/04-acces-et-urls.md) | Toutes les adresses |
| [DNS](docs/08-dns.md) | Domaine, sous-domaines et certificats HTTPS |
| [Sauvegarde](docs/05-backup-restore.md) | `make backup` / `make restore` |
| [Dépannage](docs/06-depannage.md) | Erreurs fréquentes |
| [Fiches services](docs/services/README.md) | Une fiche par service |

## Démarrage rapide

```sh
ssh-keygen -t ed25519 -C "admin@mon-poste" # Crée votre clé SSH
scp ~/.ssh/id_ed25519.pub root@<ip>:/tmp/id_ed25519.pub
```

```sh
ssh root@<ip>

sudo apt update && sudo apt install -y git   # Debian/Ubuntu, if git is missing

sudo git clone https://github.com/lx78WyY0J5/docker-server.git /opt/docker-server

cd /opt/docker-server

cp .env.example .env # Vous pouvez aussi directement coller le fichier avec les tokens déjà configurés
chmod 600 .env

nano .env

sudo ./install.sh --pubkey-file /tmp/id_ed25519.pub
```

- Dans un nouveau terminal :
  - Testez directement la connexion (nouveau port SSH, clé SSH, etc)
  - Avant de fermer le terminal actuel
```sh
# Si vous avez l'ajout de clé automatique via Keepass ou un agent SSH
ssh -p <port> admin@<ip-du-serveur>
# Sinon, ajoutez le fichier de clé SSH privé
ssh -p <port> -i ~/.ssh/<id_rsa|ed25519> admin@<ip-du-serveur>
```

```sh
su - # Passer en root
sudo su - # Alternative
```

- `install.sh` installe Docker, génère les secrets, crée les réseaux, puis sécurise l'hôte (compte admin, SSH, UFW, mises à jour)
- fail2ban est lancé avec les conteneurs

Ensuite :

```sh
sudo make check-env
sudo make up
sudo make ps
```

Les adresses suivent le modèle `https://<service>.<DOMAIN_NAME><TLD>`.
Exemple : avec `DOMAIN_NAME=supername` et `TLD=.fr`, Forgejo est sur `https://git.supername.fr`. Le domaine et l'extension peuvent être changés :
toutes les adresses changeront en même temps.

## Commandes
`sudo make help`
- **__help__** : Affiche cette aide
- **__init__** : Génère .env, les mots de passe, les htpasswd et les réseaux Docker
- **__check-env__** : Vérifie que .env contient les secrets nécessaires avant make up
- **__ensure-networks__** : Crée les réseaux Docker externes manquants
- **__build__** : Construit les images de base puis celles des stacks
- **__php-site-src__** : Clone le dépôt website dans stacks/web/php-site/src
- **__php-site-env__** : Régénère stacks/web/php-site/src/.env depuis .env
- **__php-base__** : Construit uniquement l'image de base PHP/Apache
- **__mariadb-base__** : Construit uniquement l'image de base MariaDB
- **__postgres-base__** : Construit uniquement l'image de base PostgreSQL
- **__paper-base__** : Construit l'image commune des serveurs Paper
- **__base__** : Construit toutes les images de base
- **__ensure-base__** : Construit les images de base manquantes
- **__up__** : Démarre toute l'infrastructure
- **__down__** : Arrête toute l'infrastructure sans supprimer les conteneurs (les volumes sont conservés)
- **__restart__** : Redémarre toute l'infrastructure
- **__ps__** : Liste l'état des conteneurs
- **__logs__** : Suit les logs de tous les conteneurs
- **__config__** : Valide et affiche la configuration Compose fusionnée
- **__backup__** : Sauvegarde les bases et les volumes applicatifs
- **__restore__** : Restaure une sauvegarde : make restore BACKUP=backups/AAAA...
- **__azuriom-seed__** : Réapplique les données de démonstration Azuriom (paramètres, rôles, boutique)
- **__forgejo-admin__** : Crée le compte admin Forgejo depuis .env (automatique avec `up` / `up-service`)
- **__mail-integrate__** : Installe l'override Traefik dans MAILCOW_DIR
- **__mail-up__** : Démarre mailcow avec l'intégration Traefik
- **__mail-down__** : Arrête mailcow
- **__mail-logs__** : Suit les logs de mailcow
- **__clean__** : Supprime tous les conteneurs ET les volumes (**__DESTRUCTIF__**, `CONFIRM=yes`)
- **__clean-service__** : Supprime un service ciblé, ses conteneurs et ses volumes exclusifs (**__DESTRUCTIF__**, `CONFIRM=yes`)
- **__down-clean__** : Arrête puis supprime tous les conteneurs ET les volumes (**__DESTRUCTIF__**, `CONFIRM=yes`)
- **__down-clean-service__** : Arrête puis supprime un service ciblé et ses volumes exclusifs (**__DESTRUCTIF__**, `CONFIRM=yes`)
- **__stop__** : Arrête un service (ex: make stop `SERVICE=azuriom`)
- **__restart-service__** : Redémarre un service (ex: make restart-service `SERVICE=azuriom`)
- **__logs-service__** : Suit les logs d'un service (ex: make logs-service `SERVICE=azuriom`)
- **__up-service__** : Démarre un service (ex: make up-service `SERVICE=azuriom`)
- **__down-service__** : Arrête un service sans supprimer son conteneur (ex: `make down-service SERVICE=azuriom`)
- **__ps-service__** : État d'un service (ex: make ps-service `SERVICE=azuriom`)
- **__services__** : Liste tous les noms de services

## Services
### Bases
- `base` : Images de base PHP/Apache, MariaDB, PostgreSQL, Paper

### Bases de données
- `db-azuriom` : Base de données Azuriom
- `db-forgejo` : Base de données Forgejo
- `db-php` : Base de données pour le site PHP

### Services de développement
- `code-server` : Interface web pour vs-code
- `phpmyadmin` : Gestionnaire de bases MariaDB via interface web
- `forgejo` : Forge Git auto-hébergée
- `keeweb` : Gestion des mots de passe (`.kdbx` / KeePass)

### Services Web
- `php-site` : Site web PHP
- `meme` : Site de redirection de meme
- `azuriom` : Site et panneau d'administration pour serveur Minecraft

### Services système
- `traefik` : Proxy
- `fail2ban` : Protection anti-brute force (Traefik + SSH)
- `bot` : Bot Discord

### Messagerie
- `mail-integrate` : Override Traefik dans MAILCOW_DIR
- `mail-up` / `mail-down` : Gestion de MailCow
- `mail-logs` : Logs de MailCow

### Applications Minecraft
- `mc-anarchie`, `mc-creatif`, `mc-opprison`, `mc-hub`, `mc-skyblock`, `mc-survie`, `mc-rpg`, `mc-test` : Serveurs de jeu Minecraft
- `mc-plugins` : Plugins pour les serveurs
- mondes Minecraft : les cartes de départ sont incluses dans l'image Paper (`stacks/minecraft/paper/maps`)

## Réseaux
Les services communiquent via :
- `PROXY_NETWORK`
  - `forgejo_internal`
  - `minecraft`
  - `azuriom_internal`
  - `db_admin`
  - `php_internal`

## Utilisation
- `sudo make init` - Initialisation (création des secrets, htpasswd et réseaux)
- `sudo make up` - Démarrage complet
- `sudo make down` - Arrêt complet sans supprimer les conteneurs
- `sudo make down-service SERVICE=azuriom` - Arrêt d'un service sans supprimer son conteneur
- `sudo make services` - Liste complète des services disponibles
- `sudo CONFIRM=yes make clean` - Suppression complète des conteneurs et volumes
- `sudo CONFIRM=yes make clean-service SERVICE=azuriom` - Suppression d'un service et de ses volumes
- `sudo CONFIRM=yes make down-clean-service SERVICE=azuriom` - Arrêt puis suppression d'un service et de ses volumes
