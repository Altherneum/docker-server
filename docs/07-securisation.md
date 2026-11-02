# Sécurisation de l'hôte

`install.sh` installe et sécurise l'hôte en une seule fois.

La clé SSH publique est **obligatoire**. `install.sh` la vérifie avant toute
installation : sans clé valide, rien n'est modifié.

- `install.sh` installe Docker, clone le dépôt et génère `.env` ;
- il crée ensuite le compte admin, configure SSH, UFW et les mises à jour
  automatiques ; fail2ban est le conteneur `stacks/fail2ban/`.

> **À lire avant de lancer.** Le script bloque SSH par mot de passe et l'accès
> root. Testez toujours la connexion par clé dans un **second terminal** avant
> de fermer votre session. Aucun rollback global n'est prévu : les fichiers
> modifiés sont sauvegardés dans `/var/backups/harden/` pour une restauration
> manuelle. Seule la configuration sshd est restaurée automatiquement si
> `sshd -t` échoue, pour ne pas laisser SSH dans un état invalide.

## 1. Préparer la clé SSH

Sur votre poste, créez une clé si vous n'en avez pas :

```sh
ssh-keygen -t ed25519 -C "admin@mon-poste"
```

Cela crée deux fichiers :

- `~/.ssh/id_ed25519` : la clé **privée**, à garder secrète sur votre poste ;
- `~/.ssh/id_ed25519.pub` : la clé **publique**, à envoyer au serveur.

Copiez la clé publique sur le serveur :

```sh
scp ~/.ssh/id_ed25519.pub root@<ip-du-serveur>:/tmp/id_ed25519.pub
```

La clé privée ne quitte **jamais** votre machine.

## 2. Installer et sécuriser

Avec `install.sh`, la clé publique est transmise directement :

```sh
sudo ./install.sh --pubkey-file /tmp/id_ed25519.pub
```

`install.sh` refuse de continuer si le fichier est absent, vide ou ne contient
aucune clé publique valide. Il n'y a pas d'option pour ignorer la sécurisation.

Pour relancer l'installation et la sécurisation :

```sh
cd /opt/docker-server
sudo ./install.sh --pubkey-file /tmp/id_ed25519.pub
```

Le script est idempotent : vous pouvez le relancer plus tard.

## 3. Vérifier la connexion

Dans un **second terminal** :

```sh
ssh -p <port> admin@<ip-du-serveur>
sudo -v
su -
```

Le port est `HARDEN_SSH_PORT` dans `.env` (`22` par défaut). Si vous l'avez
changé, pensez à utiliser `ssh -p <port>`.

## Comment marche la clé SSH

1. Le script écrit votre clé **publique** dans
   `/home/admin/.ssh/authorized_keys`.
2. Quand vous vous connectez, SSH envoie cette clé publique au serveur.
3. Le serveur vérifie qu'elle est autorisée, puis demande à votre poste de
   prouver qu'il possède la clé **privée** correspondante.
4. La clé privée reste sur votre machine.

La clé publique est **obligatoire**. Si aucune clé n'est fournie, le script
s'arrête avant de modifier quoi que ce soit. Il ne génère pas de clé et ne
reprend pas les clés de `root`.

## Ce que fait le script

### Compte admin

- Crée `admin` s'il n'existe pas (`HARDEN_ADMIN_USER` pour changer, mais `root`
  est interdit). Si un groupe `admin` existe déjà, il est utilisé comme groupe
  principal du compte.
- L'ajoute au groupe `sudo` (Debian/Ubuntu) ou `wheel` (Alpine/Arch), et au
  groupe `docker` s'il existe (pour `docker ps` dans le MOTD).
- Écrit une règle sudo dédiée dans
  `/etc/sudoers.d/90-docker-server-<admin>`, vérifiée avec `visudo -c`.
- Génère un mot de passe aléatoire si le compte n'en a pas. Il est affiché une
  seule fois à la fin. Changez-le avec `sudo passwd admin`.

### Clés SSH

- Exige une clé publique via `--pubkey-file`, `--pubkey` ou
  `HARDEN_SSH_PUBKEY_FILE`.
- S'arrête immédiatement si aucune clé n'est fournie.
- Importe la clé dans `/home/<admin>/.ssh/authorized_keys`.
- Applique les droits : `.ssh` en `700`, `authorized_keys` en `600`.

### Configuration SSH

- Écrit `/etc/ssh/sshd_config.d/00-docker-server-hardening.conf`.
- Ajoute `Include /etc/ssh/sshd_config.d/*.conf` dans `sshd_config` si absent.
- Désactive l'authentification par mot de passe et l'authentification
  interactive.
- Bloque totalement root en SSH (`PermitRootLogin no`). On se connecte en
  `admin`, puis on utilise `su -` (ou `sudo -i`) pour root.
- Limite les tentatives (`MaxAuthTries 3`) et le délai de connexion.
- Désactive X11, les tunnels et les transferts d'agent.
- Vérifie avec `sshd -t` puis `sshd -T`, puis recharge SSH.
- Sauvegarde la configuration avant modification.

### Port SSH

Le port SSH n'est pas détecté automatiquement : c'est `HARDEN_SSH_PORT` dans
`.env` qui est appliqué.

```dotenv
HARDEN_SSH_PORT=22
```

Pour cacher SSH, remplacez `22` par un autre port (par exemple `2222`) avant
de lancer l'installation. Le script :

1. écrit `Port <port>` dans le fichier inclus en premier ;
2. commente les anciennes directives `Port` du `sshd_config` principal ;
3. ouvre ce port dans UFW avec `ufw limit` ;
4. prépare ce port pour la jail SSH du conteneur fail2ban ;
5. vérifie que `sshd -T` ne renvoie que ce port.

### Pare-feu UFW

- Refuse les connexions entrantes et autorise les sortantes.
- Autorise SSH avec `ufw limit` sur `HARDEN_SSH_PORT`.
- Ouvre les ports utiles (voir la liste plus bas).
- Autorise le forwarding nécessaire à Docker.

### fail2ban (conteneur)

`install.sh` n'installe plus fail2ban sur l'hôte. Le conteneur
`stacks/fail2ban/` surveille les logs SSH de la machine et ceux de Traefik.

- Monte `/var/log` de l'hôte en lecture seule dans `/host/var/log`.
- Sur Debian/Ubuntu et Arch, `install.sh` installe et active `rsyslog` pour
  fournir `auth.log`.
- Détecte `auth.log`, `secure`, `messages` ou `syslog` ; le chemin peut être
  forcé avec `FAIL2BAN_SSH_LOG`.
- Crée une jail `[sshd]` sur `HARDEN_SSH_PORT` et bannit dans la chaîne
  `INPUT`, car le SSH de l'hôte ne passe pas par Docker.
- Bannit une IP après `HARDEN_FAIL2BAN_MAXRETRY` échecs pendant
  `HARDEN_FAIL2BAN_FINDTIME`, pour `HARDEN_FAIL2BAN_BANTIME`.
- Bannit le trafic Traefik dans `DOCKER-USER`, pour protéger les conteneurs.
- Utilise `network_mode: host` et les capacités `NET_ADMIN` / `NET_RAW`.

Le conteneur démarre avec `sudo make up` ou
`sudo make up-service SERVICE=fail2ban`. Voir
[la fiche fail2ban](services/fail2ban.md).

### Mises à jour automatiques

- **Debian/Ubuntu** : `unattended-upgrades`, sans redémarrage automatique.
- **Alpine** : script hebdomadaire `/etc/periodic/weekly/99-docker-server-upgrade`
  et activation de `crond`.
- **Arch** : timer systemd hebdomadaire qui lance `pacman -Syu --noconfirm`.
- Aucun redémarrage automatique n'est effectué.

UFW et les mises à jour automatiques sont **toujours configurés**. fail2ban
est fourni par le conteneur `stacks/fail2ban/`, lancé avec les autres services.

### MOTD et notifications Discord

- Installe un MOTD simple à l'ouverture d'une session interactive :
  OS, noyau, uptime, charge, RAM, disque, IP, `docker ps`,
  `docker stats --no-stream` et `who`.
- `/etc/ssh/sshrc` envoie un message Discord pour les connexions SSH
  **non interactives** (commande distante, `scp`, etc.).
- `/etc/profile.d/00-docker-server-session.sh` envoie un message pour les
  sessions **interactives**, avec le changement de session éventuel
  (`login > utilisateur courant`).
- Les URL viennent de `.env` :
  ```dotenv
  DISCORD_WEBHOOK_SSH=
  DISCORD_WEBHOOK_SESSION=
  ```
  Si `DISCORD_WEBHOOK_SESSION` est vide, `DISCORD_WEBHOOK_SSH` est utilisé.
- Les URL sont stockées dans `/etc/docker-server/ssh-webhooks.conf`, lisible
  par root et par le groupe de l'admin.

### Fichier `.env`

Force `.env` en `600` pour que seul root puisse le lire.

## Ports ouverts

| Port | Protocole | Utilité |
|---|---|---|
| `HARDEN_SSH_PORT` (`22`) | TCP | SSH |
| `80` | TCP | Redirection HTTP et certificats |
| `443` | TCP | HTTPS via Traefik |
| `MINECRAFT_PORT` (`25565`) | TCP | Minecraft Java via Traefik |
| `19132` | TCP + UDP | Minecraft Bedrock (Geyser) |
| `19133` | UDP | Minecraft Bedrock (NetherNet) |

Le port `8080` (code-server) reste **interne au réseau Docker** : Traefik le
joint sans qu'il soit publié sur l'hôte. Il ne doit pas être ouvert.

RCON n'est **pas ouvert dans UFW** et n'est pas publié par défaut par
`docker-compose`. Il reste interne au réseau Docker. RCON donne un contrôle
total sur le serveur Minecraft : ne le publiez pas sur Internet sans protection
adaptée.

Pour ajouter un autre port, modifiez `.env` :

```dotenv
HARDEN_EXTRA_TCP=9000
HARDEN_EXTRA_UDP=19134
```

## Docker et UFW

UFW ne filtre **pas** les ports publiés par Docker : Docker les redirige avant
le pare-feu. Le conteneur fail2ban ajoute donc ses règles dans `DOCKER-USER`
pour les jails Traefik, et dans `INPUT` pour SSH.

Conséquence : tout port présent dans `ports:` d'un `compose.yaml` est accessible
depuis Internet, même s'il n'est pas dans la liste UFW. Vérifiez donc vos
fichiers `compose.yaml` avant de publier un port.

HTTP passe par `80` et `443` via Traefik. RCON et les services internes
(MariaDB, phpMyAdmin, code-server) n'ont pas besoin d'être publiés.

## Sauvegardes et restauration manuelle

Chaque fichier modifié est sauvegardé dans
`/var/backups/harden/AAAA-MM-JJ-HHMMSS/`.

Restauration manuelle de SSH :

```sh
sudo cp -a /var/backups/harden/<horodatage>/etc__ssh__sshd_config /etc/ssh/sshd_config
sudo rm -f /etc/ssh/sshd_config.d/00-docker-server-hardening.conf
sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd
```

## Options de `install.sh`

| Option | Effet |
|---|---|
| `--pubkey-file FICHIER` | Clé publique obligatoire, validée avant installation |

Les réglages se font dans `.env` : port SSH, ports supplémentaires, jail
fail2ban et webhooks Discord.

## Variables dans `.env`

| Variable | Défaut | Rôle |
|---|---|---|
| `HARDEN_ADMIN_USER` | `admin` | Nom du compte admin |
| `HARDEN_ADMIN_PASSWORD` | vide | Mot de passe sudo (sinon généré) |
| `HARDEN_SSH_PUBKEY_FILE` | vide | Clé publique si pas de `--pubkey-file` |
| `HARDEN_SSH_PORT` | `22` | Port SSH appliqué à sshd, UFW et fail2ban |
| `HARDEN_FAIL2BAN_MAXRETRY` | `3` | Échecs avant bannissement |
| `HARDEN_FAIL2BAN_BANTIME` | `1h` | Durée du bannissement |
| `HARDEN_FAIL2BAN_FINDTIME` | `10m` | Période de comptage |
| `FAIL2BAN_SSH_LOG` | vide | Journal SSH lu par le conteneur |
| `HARDEN_EXTRA_TCP` | vide | Ports TCP en plus |
| `HARDEN_EXTRA_UDP` | vide | Ports UDP en plus |
| `MINECRAFT_PORT` | `25565` | Port Minecraft Java |
| `MINECRAFT_RCON_PORT` | `25575` | Port RCON (Paper et Azuriom) |
| `DISCORD_WEBHOOK_SSH` | vide | Webhook des connexions SSH |
| `DISCORD_WEBHOOK_SESSION` | vide | Webhook des sessions interactives |

Les options de la ligne de commande sont prioritaires sur `.env`. Si votre
`.env` existait avant l'ajout des variables `HARDEN_*`, les valeurs absentes
utilisent les valeurs par défaut du tableau.

## Fichiers créés

| Fichier | Rôle |
|---|---|
| `/etc/sudoers.d/90-docker-server-admin` | Règle sudo |
| `/home/admin/.ssh/authorized_keys` | Clés autorisées |
| `/etc/ssh/sshd_config.d/00-docker-server-hardening.conf` | Réglages SSH |
| `stacks/fail2ban/jail.d/` | Jails Traefik |
| `stacks/fail2ban/entrypoint.sh` | Génère la jail SSH de l'hôte |
| `/etc/apt/apt.conf.d/20auto-upgrades` | Mises à jour Debian/Ubuntu |
| `/etc/apt/apt.conf.d/51docker-server-unattended` | Réglages Debian/Ubuntu |
| `/etc/periodic/weekly/99-docker-server-upgrade` | Mises à jour Alpine |
| `/etc/systemd/system/docker-server-upgrade.*` | Mises à jour Arch |
| `/etc/ssh/sshrc` | Webhook des connexions SSH non interactives |
| `/etc/profile.d/00-docker-server-session.sh` | Webhook des sessions interactives |
| `/etc/profile.d/00-docker-server-motd.sh` | MOTD SSH |
| `/etc/docker-server/ssh-webhooks.conf` | URL des webhooks |
| `/var/backups/harden/<horodatage>/` | Sauvegardes des fichiers modifiés |

## Dépannage

### Je ne peux plus me connecter en SSH

Utilisez la console de secours de votre hébergeur, puis :

```sh
sudo rm -f /etc/ssh/sshd_config.d/00-docker-server-hardening.conf
sudo cp -a /var/backups/harden/<horodatage>/etc__ssh__sshd_config /etc/ssh/sshd_config
sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd
sudo ufw allow 22/tcp
sudo ufw disable          # seulement en dernier recours
```

Si vous avez changé de port, pensez à autoriser ce port dans UFW avant de
relancer SSH.

### `sshd -t` signale une erreur

Le script restaure automatiquement la sauvegarde. Vérifiez les conflits dans
`/etc/ssh/sshd_config` et `/etc/ssh/sshd_config.d/`, puis relancez.

### Un port Docker est accessible alors qu'il ne devrait pas

C'est normal : UFW ne filtre pas Docker. Retirez le port de `ports:` dans le
`compose.yaml`, ou utilisez le pare-feu de votre hébergeur.

### fail2ban ne bannit personne

```sh
sudo make ps-service SERVICE=fail2ban
sudo make logs-service SERVICE=fail2ban
docker exec fail2ban fail2ban-client status sshd
```

Vérifiez que le journal SSH est bien monté et lu (`/var/log/auth.log` sur
Debian/Ubuntu, `/var/log/messages` sur Alpine). Si nécessaire, renseignez
`FAIL2BAN_SSH_LOG` dans `.env`.

### Les mises à jour automatiques ne tournent pas

- Debian/Ubuntu : `systemctl list-timers | grep apt`.
- Alpine : `rc-service crond status`.
- Arch : `systemctl status docker-server-upgrade.timer`.

## Autres méthodes de hardening

Ces mesures ne sont pas automatisées par le script. Elles dépendent de votre
infrastructure.

### Accès

- **VPN WireGuard** pour réserver SSH et les interfaces d'administration à un
  réseau privé.
- **Clé FIDO2** (`ssh-keygen -t ed25519-sk`) contre le vol de clé.
- **2FA** sur les interfaces web sensibles (Authelia, Authentik).
- **`AllowUsers`** dans sshd pour n'autoriser que les comptes utiles.

### Système

- **Réglages noyau** : `sysctl` pour `tcp_syncookies`, `rp_filter`,
  `kptr_restrict`, `dmesg_restrict`, `yama.ptrace_scope`.
- **Audit** : `auditd`, `aide` ou `rkhunter`.
- **Benchmark** : `lynis` ou un scan CIS.
- **Sauvegardes** : copie hors ligne ou chiffrée, et test de restauration.

### Docker

- **Ne pas exposer le socket Docker.** Le dépôt monte
  `/var/run/docker.sock:ro` dans Traefik ; `ro` n'empêche pas les appels à
  l'API. Utilisez `tecnativa/docker-socket-proxy` avec seulement les endpoints
  nécessaires, ou Docker rootless.
- **Moindre privilège** : `no-new-privileges`, `read_only`,
  `cap_drop: [ALL]`, utilisateur non-root.
- **Images** : épingler les versions, reconstruire régulièrement, scanner avec
  `trivy image`.
- **Secrets** : préférer les fichiers Docker secrets aux variables
  d'environnement visibles dans `docker inspect`.

### Surveillance

- Uptime Kuma, Prometheus/Alertmanager ou un service externe pour l'espace
  disque, les certificats et la disponibilité.
- Journalisation distante et alertes sur les erreurs critiques.
- NTP pour garder l'heure synchronisée.
