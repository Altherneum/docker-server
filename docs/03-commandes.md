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
| `sudo make init` | Régénère `.env`, les secrets et les réseaux Docker |
| `sudo make services` | Liste les noms de services |
| `sudo make forgejo-admin` | Crée le compte admin Forgejo |
| `sudo make forgejo-mirror` | Importe les dépôts GitHub dans Forgejo et configure le miroir push |
| `sudo make forgejo-mirror FORGEJO_MIRROR_ARGS=--dry-run` | Simule l'import GitHub sans modifier Forgejo |
| `sudo make php-site-src` | Met à jour le dépôt du site PHP |
| `sudo make mail-up` | Démarre mailcow |
| `sudo make mail-down` | Arrête mailcow |
| `sudo make mail-logs` | Suit les logs de mailcow |
| `sudo CONFIRM=yes make azuriom-seed` | Réapplique les données de démonstration Azuriom |

## Commandes pour un seul service

| Commande | Effet |
|---|---|
| `sudo make up-service SERVICE=azuriom` | Construit et démarre un service |
| `sudo make stop SERVICE=azuriom` | Arrête un service |
| `sudo make restart-service SERVICE=azuriom` | Redémarre un service |
| `sudo make ps-service SERVICE=azuriom` | Affiche l'état d'un service |
| `sudo make logs-service SERVICE=azuriom` | Suit les logs d'un service |
| `sudo make down-service SERVICE=azuriom` | Arrête un service sans supprimer son conteneur |
| `sudo CONFIRM=yes make clean-service SERVICE=azuriom` | Supprime le conteneur et ses volumes exclusifs |
| `sudo CONFIRM=yes make down-clean-service SERVICE=azuriom` | Arrête puis supprime le service et ses volumes |

Exemple complet :

```sh
sudo make up-service SERVICE=forgejo
sudo make ps-service SERVICE=forgejo
sudo make logs-service SERVICE=forgejo
sudo make stop SERVICE=forgejo
```

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

## Redémarrer après une modification

| Modification | Commande conseillée |
|---|---|
| `.env` d'un service | `sudo make restart-service SERVICE=nom` |
| `.htpasswd` (Traefik, phpMyAdmin, code-server, Forgejo, KeeWeb) | `sudo make init` puis redémarrer |
| `compose.yaml` | `sudo make up-service SERVICE=nom` |
| `Dockerfile` | `sudo make build` puis `sudo make up` |
| Code du site PHP | `/api/deploy` ou `sudo make php-site-src` |

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
