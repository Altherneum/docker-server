# Traefik - proxy et HTTPS

**Rôle :** reçoit tout le trafic web, redirige HTTP vers HTTPS, crée les
certificats Let's Encrypt et envoie chaque adresse vers le bon service.

**Conteneur :** `traefik`  
**Adresse :** `https://traefik.<DOMAIN_NAME><TLD>`  
**Exemple :** `https://traefik.supername.fr`

## Mot de passe

Le tableau de bord est protégé par une authentification HTTP Basic :

| Variable `.env` | Rôle |
|---|---|
| `TRAEFIK_DASHBOARD_USER` | Nom d'utilisateur (par défaut `admin`) |
| `TRAEFIK_DASHBOARD_PASSWORD` | Mot de passe généré par `make init` |

Le fichier `stacks/proxy/auth/dashboard.htpasswd` est généré automatiquement à
partir de ces deux variables. Pour changer le mot de passe : modifiez `.env`,
lancez `sudo make init`, puis redémarrez Traefik.

## Variables `.env` utiles

| Variable | Rôle | Exemple |
|---|---|---|
| `DOMAIN_NAME` | Nom de domaine sans extension | `monprojet` |
| `TLD` | Extension avec le point | `.com` |
| `ACME_EMAIL` | E-mail Let's Encrypt | `admin@monprojet.com` |
| `TRAEFIK_DASHBOARD_HOST` | Adresse du dashboard | `traefik.monprojet.com` |
| `TRAEFIK_DASHBOARD_USER` | Utilisateur du dashboard | `admin` |
| `TRAEFIK_DASHBOARD_PASSWORD` | Mot de passe du dashboard | *(généré)* |
| `TRAEFIK_LOG_LEVEL` | Niveau de logs | `INFO` |
| `TRAEFIK_ACME_CA_SERVER` | Serveur ACME | Let's Encrypt production |
| `PROXY_NETWORK` | Réseau Docker partagé | `monprojet_proxy` |
| `MINECRAFT_PORT` | Port Minecraft Java | `25565` |

## Démarrer / arrêter

```sh
sudo make up-service SERVICE=traefik
sudo make ps-service SERVICE=traefik
sudo make logs-service SERVICE=traefik
sudo make stop SERVICE=traefik
```

> Si Traefik est arrêté, **tous les sites HTTPS deviennent inaccessibles**.

## Nettoyer

```sh
sudo CONFIRM=yes make clean-service SERVICE=traefik
```

Cela supprime le conteneur et le volume `traefik-acme` (les
certificats). Le volume `traefik-logs` est partagé avec fail2ban : il
est conservé. Les certificats seront redemandés au prochain démarrage.
Let's Encrypt limite le nombre de demandes : évitez de nettoyer Traefik sans
raison.

## Ports

| Port | Usage |
|---|---|
| `80/tcp` | HTTP, redirection et validation ACME |
| `443/tcp` | HTTPS |
| `25565/tcp` | Minecraft Java (transmis à Velocity) |

## Redirections gérées

| Adresse | Destination |
|---|---|
| `<domaine>` et `www.<domaine>` | Discord |
| `githubio`, `githubpage`, `olddoc` | `https://altherneum.github.io` |
| `discord` | Invitation Discord |
| `vocal` | Invitation Discord vocal |
| `github` | GitHub Altherneum |
| `search` | Brave Search |
| `ask`, `ai`, `ia` | Brave Ask |
| `mc`, `play` | `https://minecraft.<domaine>` |

## Dépannage

- **404** : le nom de domaine ne correspond à aucun routeur. Vérifiez `.env`
  et le DNS.
- **502** : le service cible est arrêté ou écoute sur un autre port.
- **Certificat** : vérifiez que le port `80` est ouvert et que le DNS pointe
  vers le serveur.
- **Dashboard inaccessible** : vérifiez `TRAEFIK_DASHBOARD_HOST` et les
  identifiants.

Logs :

```sh
sudo make logs-service SERVICE=traefik
```
