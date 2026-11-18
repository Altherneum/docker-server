# Docker Server

Infrastructure Docker : proxy HTTPS, administration Docker, sites web, cloud Nextcloud, forge Git, éditeur de code, gestionnaire de mots de passe, serveurs Minecraft, bot Discord, messagerie et sauvegardes.

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

### Créer une clé SSH

Sur votre poste :

#### ED25519
Clé Ed25519 (Standard moderne, plus rapide)
```sh
ssh-keygen -t ed25519 -C "admin@mon-poste"
scp ~/.ssh/id_ed25519.pub root@<IP_OU_DNS>:/tmp/id_ed25519.pub
```
#### RSA
Clé RSA (Recommandé pour compatibilité/sécurité)
```sh
ssh-keygen -t rsa -C "admin@mon-poste"
scp ~/.ssh/id_rsa.pub root@<IP_OU_DNS>:/tmp/id_rsa.pub
```

---

### Cloner le dépôt sur le VPS

```sh
ssh root@<IP_OU_DNS>

sudo apt update && sudo apt install -y git   # Debian/Ubuntu, si Git n'est pas installé

sudo git clone https://github.com/Altherneum/docker-server.git /opt/docker-server
```

---

### Configurer le fichier `.env`

- Les adresses suivent le modèle `https://<service>.<DOMAIN_NAME><TLD>`.
  - Exemple : avec `DOMAIN_NAME=supername` et `TLD=.fr`, Forgejo est accessible sur `https://git.supername.fr`.
  - Le domaine et l'extension peuvent être changés : toutes les adresses changeront en même temps.
- Le DNS doit déjà être configuré et pointer vers l'IP de votre VPS, afin que Traefik puisse générer les certificats TLS et fournir le HTTPS. Voir [DNS](docs/08-dns.md).

Exemple minimal d'enregistrements DNS :

| Type | Nom | Valeur | Contexte (Ancien / actuel) |
|---|---|---|---|
| `A` | `@` | `<IPv4 du VPS>` | `164.68.104.65` |
| `AAAA` | `@` | `<IPv6 du VPS>` | `2a02:c207:2371:8155:0000:0000:0000:0001` |
| `CNAME` | `*` | `<DOMAIN_NAME><TLD>.` | `altherneum.fr.` |
| `CNAME` | `www` | `<DOMAIN_NAME><TLD>.` | `altherneum.fr.` |
| `CAA` | `@` | `0 issue letsencrypt.org` | Cela permet de renforcer la sécurité en limitant le risque d'émission de certificats frauduleux ou non autorisés par d'autres fournisseurs. |

#### Utilisez votre copie d'un .env

```sh
cd /opt/docker-server

touch .env
chmod 600 .env

nano .env # Coller votre copie du .env
```

#### Copier le .env d'exemple

```sh
cd /opt/docker-server

cp .env.example .env
chmod 600 .env

nano .env   # Modifier le .env ; les valeurs CHANGE_ME seront remplacées par install.sh et make init
```

---

### Lancer l'installation

```sh
cd /opt/docker-server
sudo ./install.sh --pubkey-file /tmp/id_rsa.pub
```

`install.sh` installe Docker, génère les secrets manquants (valeurs `CHANGE_ME`), crée les réseaux, puis sécurise l'hôte (compte admin, SSH, UFW, mises à jour, etc.).

### Tester l'installation

#### Tester la clé SSH

Dans un **nouveau terminal** :

- testez la connexion (nouveau port SSH, authentification par clé, etc.) **avant de fermer le terminal actuel** ;
- connectez-vous avec l'utilisateur `admin`. Le hardening bloque les connexions SSH en tant que `root`.

##### Avec un agent SSH

```sh
ssh -p <port> admin@<IP_OU_DNS>
```

##### Sans agent SSH

```sh
ssh -p <port> -i ~/.ssh/id_rsa admin@<IP_OU_DNS>
```

#### Passer en root

```sh
su -
# ou
sudo su -
```

#### Tester les conteneurs

- `sudo make init` Gère la création des clées du .env
  - Notez que `install.sh` a déjà lancé `make init`.
- `sudo make check-env` Vérifie le .env
- `sudo make up` Lance tout les conteneurs
  - `sudo make up-service SERVICE=nom` Lance le conteneur `nom`
- `sudo make ps` Liste les conteneurs

### Configurer Mailcow et son DNS (optionnel)
#### Détails sur le stack
- Mailcow est une stack séparée : `make up` ne la démarre pas,
  - mais `make up-service SERVICE=mailcow` déclenche son installation et son démarrage dédiés (elle n'est pas dans `compose.yaml`).
- Le HTTPS de `mail.<domaine>` passera par Traefik,
  - mais **la réception des e-mails dépend d'enregistrements DNS que Traefik ne crée pas** (MX, SPF, DKIM, DMARC, PTR).

> À remplir au minimum : `DOMAIN_NAME`, `TLD` et `MAIL_ENABLED=true` dans `.env`.
Rien à configurer côté certificat : Traefik fournit le certificat web et Mailcow
le réutilise automatiquement pour SMTP/IMAP.

#### Détails sur le DNS
- Si tu as déjà :
  - un `A` sur `@`
  - et un `CNAME` `*` vers `@`
- pour le HTTPS « basique », il reste **5 entrées** à ajouter dans la zone DNS.
- Le `PTR` (reverse DNS) est créé automatiquement par l'hébergeur du VPS : rien à ajouter dans ta zone DNS.
  - À vérifier seulement si les mails sortants partent en spam ou sont rejetés : voir [Mailcow](docs/services/mailcow.md#ptr-reverse-dns).

#### 1. Préparer le DNS et les ports

Créez les autres enregistrements dans la zone DNS du domaine :

| Type | Nom | Valeur | Contexte (Ancien / actuel) |
|---|---|---|---|
| `A` | `mail` | `<IP du VPS>` | `164.68.104.65` |
| `MX` | `@` | `10 mail.altherneum.fr.` | `10 mail.altherneum.fr.` |
| `TXT` | `@` | `v=spf1 mx ~all` | `v=spf1 a mx ip4:45.159.229.139 include:contabo.com ~all` (à remplacer après check full OK (ToDo)) |
| `TXT` | `dkim._domainkey` | valeur affichée par : `sudo make mail-dkim-key` | `v=DKIM1; k=rsa; t=s; s=email; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyPL8bclvt81eXd/ss0TbHtpjgby7CKYJmw41JCA+yz8R7pnCbWo1X3wqTnZ0RghY6Nhs5Pzwsx6pcBzxBmz07E4FSlxr1uL7YOmmGwJfP7+fSX0Uw4z6+uGv/gE4D7z6ShoSotoKsMJANRt5NegWxTm9CrWvm/JAs/8wgF2TZRGZUCvFrlU7po2i0mcE1VWZPr1x3gGAfWPqcmjrZAnfEeqkjKHub7riGLZfBIFaXrdhAMMR9YXk0ptUlatkRfJDNM9vfSMG9q7qNK6hf9NFudwjxYbJ+spdQFGbwsZ+b384yyegQqMZ8WndSkUXaefa7y0G4Bm5vMphueQ92dy5hwIDAQAB` |
| `TXT` | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:postmaster@altherneum.fr; adkim=r; aspf=r` | `v=DMARC1; p=none; rua=mailto:postmaster@altherneum.fr; adkim=r; aspf=r` |

> Optionnel : `CNAME autodiscover` et `CNAME autoconfig` vers
> `mail.altherneum.fr.` aident Outlook et Thunderbird à trouver les réglages
> automatiquement. Ce ne sont pas des services d'hébergement DNS : ce sont de
> simples alias, non nécessaires au fonctionnement.

Pour le DKIM :

- **Nouvelle clé** : lance `sudo make mail-dkim-key`.
  - Il affiche la valeur à  mettre dans `dkim._domainkey` et prépare `.env` pour l'import.
- **Ancienne clé conservée** : si tu as déjà le TXT de l'ancien serveur, garde-le et renseigne `MAIL_DKIM_PRIVATE_KEY_FILE` (avec `MAIL_CREATE_KEYS=no`) dans le `.env`.

```sh
sudo make mail-dkim-key
```

Points importants :

- Le `CNAME *` déjà présent suffit pour le web, mais **pas pour le MX** :
  - ajoutez l'`A mail`. Un MX ne doit pas pointer vers un CNAME.
- S'il existe déjà un TXT SPF, fusionnez-le
  - il ne doit y avoir qu'un seul enregistrement SPF par domaine.
- Le TXT DKIM peut être long : le script fournit la valeur brute et la version découpée en chaînes de 255 caractères.
- Pour DMARC, `p=none` permet d'observer avant de passer à `quarantine`.
- Si un proxy ou un CDN est activé devant le domaine, désactive-le pour `mail` (validation HTTP). Les MX et TXT ne sont jamais proxifiés.

| À vérifier | Pourquoi |
|---|---|
| `A` sur `mail` vers l'IP du VPS | cible du MX ; **ne doit pas être un CNAME** |
| port `80` ouvert | certificat Let's Encrypt de Traefik |
| ports `25`, `110`, `143`, `465`, `587`, `993`, `995`, `4190` ouverts | SMTP/IMAP |
| `MAIL_ENABLED=true` dans `.env` | ouvre ces ports dans UFW à l'installation |

Si `install.sh` a déjà tourné avec `MAIL_ENABLED=false`, ouvrez les ports
manuellement (ou relancez `install.sh`) :

```sh
sudo ufw allow 25,110,143,465,587,993,995,4190/tcp
```

Vérifiez aussi le pare-feu de l'hébergeur : beaucoup de VPS bloquent le port
`25` par défaut et il faut demander son déblocage.

> Docker publie lui-même les ports mailcow. UFW ne filtre pas les ports publiés
> par Docker (le dépôt laisse `DEFAULT_FORWARD_POLICY=ACCEPT`).
> `MAIL_ENABLED=true` ajoute bien les règles UFW, mais le contrôle réel des
> ports mail reste le pare-feu de l'hébergeur. Voir
> [Sécurisation](docs/07-securisation.md#docker-et-ufw).

Sur le VPS, `.env` doit contenir le domaine réel, par exemple :

```dotenv
DOMAIN_NAME=altherneum
TLD=.fr
MAIL_ENABLED=true
```

`localhost` est réservé au développement local : l'installation Mailcow refuse
un domaine sans point.

#### 2. Tout installer en une commande

Une fois le DNS de l'étape 1 terminé, lance :

```sh
cd /opt/docker-server
sudo make mail-setup
```

C'est la seule commande à retenir après le DNS. Elle fait tout le reste :

- installe Mailcow si absent (clone + `mailcow.conf`) ;
- installe l'override Traefik, choisit un sous-réseau Docker libre et crée la
  clé API ;
- démarre Mailcow et attend que les services et l'API soient prêts ;
- importe la clé DKIM pré-générée, ou en génère une automatiquement si aucune
  clé n'est disponible (`MAIL_CREATE_KEYS=yes` force une nouvelle clé) ;
- crée les boîtes de base (`admin@`, `contact@`, etc.) ;
- lance `make mail-check`.

`sudo make up-service SERVICE=mailcow` fait exactement la même chose. Aucun
clone ni `generate_config.sh` manuel n'est nécessaire.

Si tu n'as pas pré-généré la clé à l'étape 1, `mail-setup` en crée une et
affiche le TXT : ajoute-le au DNS, puis relance `sudo make mail-check`.

#### 3. Vérifier l'intégration

```sh
sudo make mail-check
```

`mail-check` doit finir sur `0 erreur(s)` (un avertissement DNS est normal avant
la propagation). Ouvre ensuite `https://mail.<domaine>` : le certificat web est
demandé par Traefik. Premier compte Mailcow : `admin` / `moohoo`, à changer
immédiatement.

Pour diagnostiquer ou relancer les étapes séparément :

```sh
sudo make mail-install
sudo make mail-integrate
sudo make mail-up
```

#### 4. Clé DKIM (détail)

`make mail-setup` importe ou génère déjà la clé. Pour la gérer manuellement :

```sh
sudo make mail-dkim
```

Le script importe la clé fournie, conserve la clé existante, ou en génère une
nouvelle selon `MAIL_CREATE_KEYS`. Il l'écrit dans Mailcow (sans passer par
l'interface) et affiche le TXT à publier.

- Si tu as utilisé `make mail-dkim-key` à l'étape 1, la clé est déjà prête et le
  TXT déjà publié : `make mail-dkim` l'importe dans Mailcow, sans changer le DNS
- Si aucune clé n'existe, `make mail-setup` en génère une automatiquement :
  ajoute le TXT affiché sur `dkim._domainkey` dans la zone DNS (ligne prévue à
  l'étape 1)
- Pour forcer une nouvelle clé manuellement : mets `MAIL_CREATE_KEYS=yes` dans
  `.env`, lance `sudo make mail-dkim` ; le script remet `no` automatiquement

Il sauvegarde aussi les fichiers dans `backups/mail-dkim-<date>/`.

Une seule clé DKIM couvre **toutes les adresses** du domaine (`contact@`,
`admin@`, etc.) : les boîtes se créent avec `make mail-mailboxes` ou dans
l'interface Mailcow et n'ont pas de clé individuelle.

Après cette première génération, garde `MAIL_CREATE_KEYS=no` dans `.env` :
`sudo make mail-dkim` réaffichera la clé existante sans la régénérer.

#### 5. Boîtes de base (détail)

`make mail-setup` crée déjà les boîtes par défaut. Pour les relancer ou les
modifier :

```sh
sudo make mail-mailboxes
```

Par défaut, le script crée `admin@`, `contact@`, `root@`, `postmaster@` et
`abuse@`. Les mots de passe sont générés et stockés dans `.env`
(`MAILBOX_*_PASSWORD`). La liste est modifiable avec `MAIL_MAILBOXES`.

Pour créer aussi les boîtes utilisées par les intégrations du dépôt, ajoutez :

```dotenv
MAIL_MAILBOXES=admin,contact,root,postmaster,abuse,noreply,git,cloud
```

`noreply` utilise `AZURIOM_MAIL_PASSWORD`, `git` utilise
`FORGEJO_MAIL_PASSWORD` et `cloud` utilise `NEXTCLOUD_MAIL_PASSWORD`.

> `admin@altherneum.fr` est une boîte mail. Le compte d'administration Mailcow
> est `admin` (sans `@`), avec le mot de passe initial `moohoo`.

#### 6. Vérifier

Après propagation (quelques minutes à quelques heures) :

```sh
dig +short A mail.altherneum.fr
dig +short MX altherneum.fr
dig +short TXT altherneum.fr
dig +short TXT dkim._domainkey.altherneum.fr
dig +short TXT _dmarc.altherneum.fr
dig -x <IP> +short
curl -I https://mail.altherneum.fr
```

Vérification des ports sur le VPS :

```sh
sudo ss -lntp | grep -E ':(25|80|110|143|443|465|587|993|995|4190)\b'
sudo docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep -E 'mailcow|traefik'
sudo ufw status | grep -E '25|80|110|143|443|465|587|993|995|4190'
```

Depuis un autre poste, testez au moins SMTP et IMAPS :

```sh
nc -vz mail.altherneum.fr 25
nc -vz mail.altherneum.fr 465
nc -vz mail.altherneum.fr 993
```

Puis envoyez un message vers un test (Gmail, mail-tester.com) et vérifiez
SPF/DKIM/DMARC. Logs : `sudo make mail-logs`.

`https://mail.<domaine>` est couvert par Traefik. Le même certificat Let's
Encrypt est copié automatiquement vers Mailcow pour SMTP/IMAP, avec un timer
systemd quotidien. Rien à remplir : si Traefik n'a pas encore de certificat,
Mailcow garde son certificat interne et le timer réessaie. Pour forcer :
`sudo make mail-cert-sync`.

#### 7. Si l'IP ou le domaine change

- mettez à jour l'`A mail` et le `PTR` ;
- le `CNAME *` reste valable ;
- la clé DKIM ne dépend pas de l'IP ; `sudo make mail-dkim` réaffiche
  l'enregistrement ;
- si le domaine change, mettez à jour `.env` et `MAILCOW_HOSTNAME` dans
  `$MAILCOW_DIR/mailcow.conf`, relancez `sudo make mail-up`, puis ajoutez les
  nouveaux DNS.

## Commandes

### Afficher l'aide

`sudo make help`

### Aide-mémoire

- `sudo make up-service SERVICE=azuriom` : démarre un service ;
- `sudo make rebuild-service SERVICE=bot` : reconstruit l'image sans cache puis recrée le service ;
- `sudo make restart-service SERVICE=azuriom` : redémarre un service ;
- `sudo CONFIRM=yes make clean-service SERVICE=azuriom` : supprime un service ciblé, ses conteneurs et ses volumes exclusifs (**__DESTRUCTIF__**).

### Liste complète

- **__help__** : Affiche cette aide
- **__init__** : Génère `.env`, les mots de passe, les htpasswd et les réseaux Docker
- **__check-env__** : Vérifie que `.env` contient les secrets nécessaires avant `make up`
- **__ensure-networks__** : Crée les réseaux Docker externes manquants
- **__ensure-auth__** : Génère les fichiers htpasswd manquants (automatique avec `up` / `up-service`)
- **__ensure-traefik__** : Reconstruit et recrée Traefik si ses templates ont changé
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
- **__forgejo-runner__** : Vérifie que le runner Forgejo Actions est en ligne (automatique avec `up` / `up-service`)
- **__forgejo-mirror__** : Importe les dépôts GitHub dans Forgejo, configure le miroir push et démarre la CI des dépôts importés (automatique avec `up` / `up-service`) ; options `--dry-run`, `--reset-stuck`, `--run-actions`, `--force`
- **__uptime-kuma-admin__** : Crée le compte admin Uptime Kuma depuis .env (automatique avec `up` / `up-service`)
- **__uptime-kuma-docker-sync__** : Ajoute les moniteurs Docker manquants et configure la notification Discord dans Uptime Kuma (automatique avec `up` / `up-service` si Uptime Kuma tourne) ; mode détaillé avec `VERBOSE=1`
- **__mail-install__** : Clone et configure Mailcow si absent
- **__mail-setup__** : Installe, démarre et configure Mailcow en une commande
- **__mail-integrate__** : Prépare l'override Traefik, le réseau et la clé API de mailcow
- **__mail-check__** : Vérifie que mailcow peut démarrer (réseau, ports, override)
- **__mail-cert-sync__** : Copie le certificat Traefik vers mailcow (SMTP/IMAP)
- **__mail-cert-timer__** : Installe le timer systemd de synchro du certificat
- **__mail-up__** : Démarre mailcow, installe le timer, synchronise le certificat et vérifie
- **__mail-dkim__** : Crée/importe la clé DKIM et affiche le TXT DNS
- **__mail-dkim-key__** : Pré-génère la clé DKIM avant l'installation de mailcow
- **__mail-mailboxes__** : Crée les boîtes de base (admin, contact, root, ...)
- **__mail-down__** : Arrête mailcow
- **__mail-logs__** : Suit les logs de mailcow
- **__clean__** : Supprime tous les conteneurs ET les volumes (**__DESTRUCTIF__**, `CONFIRM=yes`)
- **__clean-service__** : Supprime un service ciblé, ses conteneurs et ses volumes exclusifs (**__DESTRUCTIF__**, `CONFIRM=yes`)
- **__down-clean__** : Arrête puis supprime tous les conteneurs ET les volumes (**__DESTRUCTIF__**, `CONFIRM=yes`)
- **__down-clean-service__** : Arrête puis supprime un service ciblé et ses volumes exclusifs (**__DESTRUCTIF__**, `CONFIRM=yes`)
- **__stop__** : Arrête un service (ex: make stop `SERVICE=azuriom`)
- **__rebuild-service__** : Reconstruit sans cache une image puis recrée un service (ex: make rebuild-service `SERVICE=bot`)
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
- `db-nextcloud` : Base de données Nextcloud
- `db-php` : Base de données pour le site PHP

### Services de développement
- `code-server` : Interface web pour VS Code
- `phpmyadmin` : Gestionnaire de bases MariaDB via une interface web
- `forgejo` : Forge Git auto-hébergée
- `keeweb` : Gestion des mots de passe (`.kdbx` / KeePass)

### Services Web
- `php-site` : Site web PHP
- `meme` : Site de redirection de mèmes
- `azuriom` : Site et panneau d'administration pour serveur Minecraft
- `nextcloud` : Cloud personnel (fichiers, calendriers, contacts)
- `nextcloud-cron` : Tâches de fond Nextcloud
- `nextcloud-redis` : Cache, verrous et sessions Nextcloud

### Services système
- `traefik` : Proxy HTTPS et certificats
- `dockhand` : Interface d'administration Docker
- `uptime-kuma` : Supervision des services et des conteneurs
- `uptime-kuma-docker-proxy` : Proxy Docker en lecture seule pour Uptime Kuma
- `fail2ban` : Protection anti-brute force (Traefik + SSH)
- `bot` : Bot Discord

### Messagerie
- `mail-install` : Clone et configure Mailcow si absent
- `mail-setup` : Installe, démarre et configure Mailcow en une commande
- `mail-integrate` : Override Traefik dans `MAILCOW_DIR`
- `mail-check` : Vérifie le réseau, les ports et l'override Mailcow
- `mail-cert-sync` : Copie le certificat Traefik vers mailcow (SMTP/IMAP)
- `mail-cert-timer` : Installe le timer systemd de synchro du certificat
- `mail-dkim` : Crée/importe la clé DKIM et affiche le TXT DNS
- `mail-dkim-key` : Pré-génère la clé DKIM avant l'installation de mailcow
- `mail-mailboxes` : Crée les boîtes de base (admin, contact, root, ...)
- `mail-up` / `mail-down` : Gestion de Mailcow
- `mail-logs` : Logs de Mailcow

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
  - `nextcloud_internal`
  - `uptime_kuma_internal`
  - `db_admin`
  - `php_internal`

## Utilisation
- `sudo make init` - Initialisation (création des secrets, htpasswd et réseaux)
- `sudo make up` - Démarrage complet (génère les htpasswd manquants et met Traefik à jour)
- `sudo make ensure-auth` - Génère uniquement les fichiers htpasswd manquants
- `sudo make ensure-traefik` - Reconstruit et recrée Traefik si ses templates ont changé
- `sudo make down` - Arrêt complet sans supprimer les conteneurs
- `sudo make down-service SERVICE=azuriom` - Arrêt d'un service sans supprimer son conteneur
- `sudo make services` - Liste complète des services disponibles
- `sudo CONFIRM=yes make clean` - Suppression complète des conteneurs et volumes
- `sudo CONFIRM=yes make clean-service SERVICE=azuriom` - Suppression d'un service et de ses volumes
- `sudo CONFIRM=yes make down-clean-service SERVICE=azuriom` - Arrêt puis suppression d'un service et de ses volumes
