# Commandes

Toutes les commandes se lancent depuis la racine du dépôt :

```sh
cd /opt/docker-server
```

## Aide

```sh
sudo make help          # liste toutes les commandes
sudo make services      # liste les noms de services
```

## Commandes globales

| Commande | Effet |
|---|---|
| `sudo make up` | Construit si besoin et démarre tout |
| `sudo make down` | Arrête tout, sans supprimer les conteneurs ni les volumes |
| `sudo make restart` | Redémarre tout |
| `sudo make ps` | Affiche l'état des conteneurs |
| `sudo make logs` | Suit les logs de tous les services (`Ctrl+C` pour quitter) |
| `sudo make config` | Vérifie et affiche la configuration Compose |
| `sudo make build` | Construit toutes les images |
| `sudo make backup` | Sauvegarde les bases et les volumes |
| `sudo make restore BACKUP=backups/AAAA-MM-JJ_HHMMSS` | Restaure une sauvegarde |
| `sudo CONFIRM=yes make clean` | Supprime tous les conteneurs et volumes (destructif) |
| `sudo CONFIRM=yes make down-clean` | Arrête puis supprime tout (destructif) |

## Maintenance

| Commande | Effet |
|---|---|
| `sudo make init` | Régénère `.env`, les secrets, tous les htpasswd et les réseaux Docker |
| `sudo make ensure-auth` | Génère les fichiers htpasswd absents ou invalides (automatique avec `up`) |
| `sudo make ensure-traefik` | Reconstruit et recrée Traefik (manuel, après modification des templates) |
| `sudo make traefik-reload` | Redémarre Traefik pour recharger les htpasswd (sans rebuild) |
| `sudo make services` | Liste les noms de services |
| `sudo make net-diag` | Diagnostique les ports, UFW, iptables et IPv4/IPv6 (lecture seule) |
| `sudo make fail2ban-unban IP=1.2.3.4` | Retire une IP des bannissements fail2ban |
| `sudo make forgejo-admin` | Crée le compte admin Forgejo |
| `sudo make uptime-kuma-admin` | Crée le compte admin Uptime Kuma (idempotent) |
| `sudo make uptime-kuma-docker-sync` | Ajoute les moniteurs Docker manquants et configure la notification Discord (idempotent) |
| `sudo VERBOSE=1 make up-service SERVICE=nom` | Affiche le détail de la synchronisation Uptime Kuma (hôte, conteneurs déjà présents, notification) |
| `sudo make forgejo-runner` | Vérifie que le runner Forgejo Actions est en ligne |
| `sudo make forgejo-mirror` | Importe les dépôts GitHub dans Forgejo, configure le miroir push et démarre la CI |
| `sudo make forgejo-mirror FORGEJO_MIRROR_ARGS=--dry-run` | Simule l'import GitHub sans modifier Forgejo |
| `sudo make forgejo-mirror FORGEJO_MIRROR_ARGS=--reset-stuck` | Supprime les dépôts bloqués en migration |
| `sudo make forgejo-mirror FORGEJO_MIRROR_ARGS=--run-actions` | Démarre la CI des dépôts déjà présents, sans les réimporter |
| `sudo make forgejo-mirror FORGEJO_MIRROR_ARGS=--force=depot` | Réimporte un dépôt après suppression (destructif) |
| `sudo make php-site-src` | Clone ou met à jour le dépôt du site PHP (`git pull --rebase`) |
| `sudo make mail-install` | Clone et configure Mailcow si absent |
| `sudo make mail-setup` | Installe, démarre et configure Mailcow en une commande |
| `sudo make mail-integrate` | Prépare l'override Traefik, le réseau et la clé API de mailcow, vérifie le flux webmail |
| `sudo make mail-check` | Vérifie que mailcow peut démarrer (réseau, ports, override) |
| `sudo make mail-cert-sync` | Copie le certificat Traefik vers mailcow (SMTP/IMAP) |
| `sudo make mail-cert-timer` | Installe le timer systemd de synchro du certificat |
| `sudo make mail-webmail-url` | Rétablit le flux webmail mailcow (UI → `/SOGo/so`) |
| `sudo make mail-up` | Démarre mailcow, installe le timer, synchronise le certificat et vérifie |
| `sudo make mail-dkim` | Crée/importe la clé DKIM et affiche le TXT DNS |
| `sudo make mail-dkim-key` | Pré-génère la clé DKIM avant l'installation de mailcow |
| `sudo make mail-mailboxes` | Crée les boîtes de base (admin, contact, root, ...) |
| `sudo make mail-down` | Arrête mailcow |
| `sudo make mail-logs` | Suit les logs de mailcow |
| `sudo CONFIRM=yes make azuriom-seed` | Réapplique les données de démonstration Azuriom |

Le mode `VERBOSE=1` est utile pour diagnostiquer la synchronisation Uptime
Kuma : il affiche l'hôte Docker, la notification Discord et les conteneurs
déjà surveillés. Sans cette option, une synchronisation sans changement
affiche seulement une ligne de résumé.

## Commandes pour un seul service

| Commande | Effet |
|---|---|
| `sudo make up-service SERVICE=azuriom` | Construit et démarre un service |
| `sudo make stop SERVICE=azuriom` | Arrête un service |
| `sudo make restart-service SERVICE=azuriom` | Redémarre un service |
| `sudo make ps-service SERVICE=azuriom` | Affiche l'état d'un service |
| `sudo make logs-service SERVICE=azuriom` | Suit les logs d'un service |
| `sudo make down-service SERVICE=azuriom` | Arrête un service sans supprimer son conteneur |
| `sudo CONFIRM=yes make clean-service SERVICE=azuriom` | Supprime le conteneur, ses volumes exclusifs et son code monté (`php-site`) |
| `sudo CONFIRM=yes make down-clean-service SERVICE=azuriom` | Arrête puis supprime le service, ses volumes et son code monté (`php-site`) |

Exemple complet :

```sh
sudo make up-service SERVICE=forgejo
sudo make ps-service SERVICE=forgejo
sudo make logs-service SERVICE=forgejo
sudo make stop SERVICE=forgejo
```

### Cas particulier : Forgejo

`sudo make up-service SERVICE=forgejo` ne se contente pas de démarrer le
conteneur : la commande crée aussi le compte admin, attend le runner Actions,
importe les dépôts GitHub absents (si `FORGEJO_GITHUB_ORG_URL` est renseigné)
et démarre la CI des dépôts nouvellement importés. Aucune commande
supplémentaire n'est nécessaire sur une instance neuve, et il n'est pas utile
de faire `down-service` avant.

Les dépôts déjà présents ne sont pas relancés automatiquement. Pour démarrer
leur CI sans réimporter et sans redémarrer Forgejo :

```sh
sudo make forgejo-mirror FORGEJO_MIRROR_ARGS=--run-actions
```

`make forgejo-runner` et `make logs-service SERVICE=forgejo-runner` servent
uniquement à vérifier/diagnostiquer le runner. Voir la fiche
[Forgejo](services/forgejo.md#démarrage-après-import).

## Nettoyage : les niveaux

| Commande | Conteneurs | Volumes | Données |
|---|---|---|---|
| `make stop SERVICE=...` | conservés | conservés | conservées |
| `make down-service SERVICE=...` | conservés | conservés | conservées |
| `make clean-service SERVICE=...` | supprimés | supprimés s'ils sont exclusifs | **perdues** |
| `make clean` | tous supprimés | tous supprimés | **toutes perdues** |

`make clean` et `make clean-service` demandent une confirmation :

```sh
sudo CONFIRM=yes make clean-service SERVICE=php-site
```

Un volume partagé avec un autre service est conservé automatiquement.

Le site PHP a en plus du code monté depuis `stacks/web/php-site/src` (ce n'est
pas un volume Docker et `make backup` ne le sauvegarde pas) :
`make clean-service SERVICE=php-site` et
`make down-clean-service SERVICE=php-site` suppriment aussi ce dossier, avec
les uploads et `src/.env`. Le démarrage suivant reclone depuis
`PHP_SITE_REPO_URL`.

## Redémarrer après une modification

| Modification | Commande conseillée |
|---|---|
| `.env` d'un service | `sudo make up-service SERVICE=nom` (recrée le conteneur avec les nouvelles variables) |
| `.env` Forgejo : import/CI (`FORGEJO_GITHUB_*`) | `sudo make forgejo-mirror` (variable lue par le script, pas besoin de recréer Forgejo) |
| `.htpasswd` (Traefik, phpMyAdmin, code-server, Forgejo, KeeWeb) | Voir [Traefik et basic auth](#traefik-et-basic-auth) |
| Templates Traefik (`stacks/proxy/templates`) | `sudo make ensure-traefik` (ou `sudo make up-service SERVICE=traefik`) |
| `compose.yaml` | `sudo make up-service SERVICE=nom` |
| `Dockerfile` ou code embarqué dans l'image | `sudo make up-service SERVICE=nom` |
| Image récalcitrante / cache Docker | `sudo make rebuild-service SERVICE=nom` |
| Code du site PHP | `git -C stacks/web/php-site/src pull --rebase` (ou `/api/deploy`) |

`make restart-service` ne fait que redémarrer le conteneur existant : il ne
reconstruit pas l'image et ne réapplique pas les variables de `.env`.
Utiliser `up-service` par défaut, et `rebuild-service` uniquement si Docker
semble réutiliser une image ou un cache obsolète.

Pour la procédure complète après un `git pull --rebase` (images de base,
registres, Minecraft, Mailcow, ordre de redémarrage), voir
[Mise à jour](../README.md#mise-à-jour).

## Traefik et basic auth

Le rebuild de Traefik n'est **plus automatique**. `make up`, `make up-service`
et `make rebuild-service` ne reconstruisent ni ne redémarrent plus Traefik :
seul `ensure-auth` reste appelé automatiquement, et il ne touche pas au
conteneur.

### Choisir la bonne commande

| Ce qui est modifié | Commande | Rebuild ? |
|---|---|---|
| Un fichier `.htpasswd` édité directement | `sudo make traefik-reload` | non |
| Le mot de passe dans `.env` | `sudo make init` puis `sudo make traefik-reload` | non |
| Un fichier `.htpasswd` absent ou supprimé | `sudo make ensure-auth` puis `sudo make traefik-reload` | non |
| Un template (`stacks/proxy/templates`, `entrypoint.sh`, `Dockerfile`) | `sudo make ensure-traefik` | oui |

`ensure-auth` ne régénère que les fichiers absents, vides ou sans utilisateur :
il ne réécrit jamais un fichier existant et valide. Un mot de passe changé dans
`.env` n'est donc pas appliqué par `ensure-auth`, mais par `make init`, qui
réécrit tous les htpasswd depuis `.env`.

À l'inverse, `make init` écrase les htpasswd : une modification faite à la main
dans un fichier est perdue.

### Pourquoi restart et pas rebuild

- `stacks/proxy/compose.yaml` monte `stacks/proxy/auth` dans le conteneur :
  un `restart` suffit pour recharger les htpasswd
- `stacks/proxy/Dockerfile` copie `templates/` **dans l'image** : seuls les
  templates exigent un rebuild
- le volume `traefik-acme` est persistant : un restart ne fait pas perdre les
  certificats, Traefik est seulement indisponible quelques secondes

### Cas d'un service ciblé

`sudo make up-service SERVICE=mc-hub` ne lance que :

```sh
docker compose --env-file .env up -d --build mc-hub
```

Traefik n'est donc ni reconstruit ni redémarré. Deux conséquences :

- si Traefik est arrêté, `up-service` ne le relance pas : utiliser
  `sudo make up-service SERVICE=traefik` (qui rebuild) ou `sudo make up`
- un nouveau routeur ou middleware ajouté au template ne sera visible qu'après
  `sudo make ensure-traefik`

## Docker Compose directement

Les commandes `make` sont des raccourcis. Pour les cas particuliers :

```sh
docker compose --env-file .env ps
docker compose --env-file .env logs -f traefik
docker compose --env-file .env up -d --build forgejo
```

Une stack peut aussi être lancée seule :

```sh
docker compose --env-file .env -f stacks/forgejo/compose.yaml up -d --build
```
