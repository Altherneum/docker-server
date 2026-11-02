# fail2ban

**Rôle :** lit les logs de Traefik **et les logs SSH de l'hôte**, puis bloque
les adresses IP qui font trop d'erreurs ou de tentatives de connexion.

**Conteneur :** `fail2ban`  
**Adresse :** aucune. C'est un service de protection en arrière-plan.

## Mot de passe

Aucun. Il n'y a pas d'interface web.

## Variables `.env`

| Variable | Rôle |
|---|---|
| `HARDEN_SSH_PORT` | Port SSH surveillé (`22` par défaut) |
| `HARDEN_FAIL2BAN_MAXRETRY` | Échecs avant bannissement (`3`) |
| `HARDEN_FAIL2BAN_FINDTIME` | Période de comptage (`10m`) |
| `HARDEN_FAIL2BAN_BANTIME` | Durée du bannissement (`1h`) |
| `FAIL2BAN_SSH_LOG` | Journal SSH à lire (vide = détection automatique) |
| `TZ` | Fuseau horaire |

La configuration est dans `stacks/fail2ban/`. Le conteneur monte le dossier
hôte `/var/log` en lecture seule dans `/host/var/log`. Sur Debian/Ubuntu et
Arch, `install.sh` installe et active `rsyslog` pour que `auth.log` existe.

## Logs SSH

Le conteneur détecte automatiquement le journal SSH :

- Debian / Ubuntu : `/host/var/log/auth.log` ;
- Alpine : `/host/var/log/messages` ;
- autres systèmes : `secure`, `messages` ou `syslog`.

Pour forcer un chemin, mettez par exemple dans `.env` :

```dotenv
FAIL2BAN_SSH_LOG=/var/log/auth.log
```

Le conteneur préfixe automatiquement avec `/host` si nécessaire.

Si aucun journal n'existe, la jail SSH est désactivée et un message est écrit
dans les logs du conteneur. Sans `install.sh`, installez `rsyslog` sur
Debian/Ubuntu, ou utilisez `FAIL2BAN_SSH_LOG` avec un fichier alimenté par SSH.

## Démarrer / arrêter

```sh
sudo make up-service SERVICE=fail2ban
sudo make ps-service SERVICE=fail2ban
sudo make logs-service SERVICE=fail2ban
sudo make stop SERVICE=fail2ban
```

`fail2ban` est lancé automatiquement par `sudo make up`.

## Nettoyer

```sh
sudo CONFIRM=yes make clean-service SERVICE=fail2ban
```

Cela supprime le volume `fail2ban-data` (base des bannissements).

## Fonctionnement

### SSH de l'hôte

- Lit le journal SSH monté depuis l'hôte.
- Bannit dans la chaîne `INPUT`, car le SSH de l'hôte ne passe pas par Docker.
- Utilise le port `HARDEN_SSH_PORT`.
- Bannit après `HARDEN_FAIL2BAN_MAXRETRY` échecs pendant
  `HARDEN_FAIL2BAN_FINDTIME`, pour `HARDEN_FAIL2BAN_BANTIME`.

### Traefik et conteneurs

- Lit `/var/log/traefik/access.log`.
- Bannit dans la chaîne `DOCKER-USER`, qui bloque le trafic destiné aux
  conteneurs publiés par Docker.
- `5` erreurs en `24 h` donnent un bannissement de `24 h`.
- Les bannissements sont progressifs, jusqu'à `90` jours.
- La jail `traefik-404` bannit après `10` erreurs 404 en `1 h`.
- Les réseaux privés et la boucle locale ne sont jamais bannis.

Les jails Traefik sont dans `stacks/fail2ban/jail.d/`. La jail SSH est générée
au démarrage dans le conteneur, car le chemin du journal dépend de l'hôte.

## Commandes utiles

Voir l'état des jails :

```sh
docker exec fail2ban fail2ban-client status
```

Voir la jail SSH :

```sh
docker exec fail2ban fail2ban-client status sshd
```

Débannir une IP :

```sh
docker exec fail2ban fail2ban-client set sshd unbanip 203.0.113.10
```

Voir les logs :

```sh
sudo make logs-service SERVICE=fail2ban
```

## Sécurité

- Le conteneur utilise `network_mode: host` et les capacités `NET_ADMIN` et
  `NET_RAW` : il modifie le pare-feu de l'hôte.
- Il est prévu pour Linux.
- Si vous vous bannissez vous-même, utilisez la commande de débannissement
  ci-dessus depuis une autre connexion.

## Dépannage

- **fail2ban ne démarre pas** : vérifiez que le volume de logs Traefik existe et
  que Traefik a déjà écrit `access.log`.
- **Jail SSH désactivée** : vérifiez que `/var/log/auth.log` existe sur l'hôte,
  ou renseignez `FAIL2BAN_SSH_LOG`.
- **Aucun bannissement SSH** : vérifiez que SSH écrit bien dans le journal lu,
  puis regardez `docker exec fail2ban fail2ban-client status sshd`.
- **Trafic bloqué à tort** : consultez `fail2ban-client status`, puis débannissez
  l'IP.
