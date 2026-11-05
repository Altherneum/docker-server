# Forgejo

**Rôle :** forge Git auto-hébergée (dépôts, utilisateurs, issues, wiki).

**Conteneurs :** `forgejo`, `db-forgejo`  
**Adresse :** `https://git.<DOMAIN_NAME><TLD>`  
**Alias :** `https://repo.<domaine>` et `https://forgejo.<domaine>`  
**Exemple :** `https://git.supername.fr`

## Mot de passe

| Variable `.env` | Utilisation |
|---|---|
| `FORGEJO_HTTP_USER` | Identifiant HTTP Basic (par défaut `forgejo`) |
| `FORGEJO_HTTP_PASSWORD` | Mot de passe HTTP Basic, généré par `make init` |
| `FORGEJO_ADMIN_NAME` | Identifiant admin |
| `FORGEJO_ADMIN_EMAIL` | E-mail admin |
| `FORGEJO_ADMIN_PASSWORD` | Mot de passe admin |
| `FORGEJO_DB_USER` / `FORGEJO_DB_PASSWORD` | Compte PostgreSQL (superutilisateur de l'image) |

Forgejo est protégé par **deux niveaux** :

1. HTTP Basic par Traefik, via `stacks/proxy/auth/forgejo.htpasswd` ;
2. compte admin Forgejo pour l'interface.

Pour changer la protection HTTP : modifiez `FORGEJO_HTTP_PASSWORD` dans `.env`,
lancez `sudo make init`, puis redémarrez Forgejo.

> `FORGEJO_DB_ROOT_PASSWORD` existe dans `.env.example` mais n'est pas utilisé
> par la configuration actuelle de `db-forgejo`. Vous pouvez l'ignorer.

Le compte admin est créé **automatiquement** par `make up` et par
`make up-service SERVICE=forgejo`, à partir des variables `FORGEJO_ADMIN_*`
de `.env`. La commande reste disponible manuellement, par exemple après une
suppression des volumes :

```sh
sudo make forgejo-admin
```

Elle lit `FORGEJO_ADMIN_*` dans `.env` (les valeurs comme `${DOMAIN_NAME}`
sont résolues par Docker Compose), attend que Forgejo soit prêt, et ne recrée
pas le compte s'il existe déjà. Le nom `admin` est réservé par Forgejo :
utilisez un autre nom, par exemple `monprojet`.

## Variables `.env` utiles

| Variable | Rôle |
|---|---|
| `FORGEJO_VERSION` | Version de Forgejo |
| `FORGEJO_DB_NAME` | Nom de la base |
| `FORGEJO_DB_USER` | Utilisateur de la base |
| `FORGEJO_DB_PASSWORD` | Mot de passe de la base |
| `FORGEJO_SECRET_KEY` | Secret applicatif, généré |
| `FORGEJO_INTERNAL_TOKEN` | Jeton interne, généré |
| `FORGEJO_LFS_JWT_SECRET` | Secret LFS, généré |
| `FORGEJO_OAUTH2_JWT_SECRET` | Secret OAuth2, généré |
| `FORGEJO_ADMIN_NAME` | Identifiant admin |
| `FORGEJO_ADMIN_EMAIL` | E-mail admin |
| `FORGEJO_ADMIN_PASSWORD` | Mot de passe admin |
| `FORGEJO_HTTP_USER` | Identifiant HTTP Basic |
| `FORGEJO_HTTP_PASSWORD` | Mot de passe HTTP Basic |
| `FORGEJO_MAIL_*` | Configuration e-mail (optionnelle) |

`FORGEJO_VERSION` définie dans `.env` est la seule source de vérité : elle est
transmise au build (`ARG` du `Dockerfile`, sans valeur par défaut) et sert aussi
de tag à l'image. Si la variable manque, Docker Compose refuse de démarrer avec
une erreur explicite. Après un changement de version, reconstruisez et
redémarrez :

```sh
sudo make up-service SERVICE=forgejo
```

## Démarrer / arrêter

```sh
sudo make up-service SERVICE=forgejo
sudo make ps-service SERVICE=forgejo
sudo make logs-service SERVICE=forgejo
sudo make forgejo-admin
sudo make stop SERVICE=forgejo
```

`db-forgejo` démarre automatiquement avec Forgejo.

## Nettoyer

```sh
sudo CONFIRM=yes make clean-service SERVICE=forgejo
sudo CONFIRM=yes make clean-service SERVICE=db-forgejo
```

Cela supprime les dépôts, les comptes et la base. **Sauvegardez avant.**

## Comportement actuel

- Les inscriptions publiques sont désactivées : l'admin crée les comptes.
- SSH est désactivé : utilisez HTTPS pour cloner et pousser.
- LFS est activé.
- Le compte admin est créé automatiquement par `make up` /
  `make up-service SERVICE=forgejo` ; `make forgejo-admin` reste disponible.
- Les dépôts d'une organisation GitHub peuvent être importés automatiquement
  (voir la section suivante).

## Import et miroir GitHub

Au démarrage, Forgejo peut importer tous les dépôts d'une organisation GitHub,
puis configurer un **miroir push** vers GitHub : un `git push` reçu par Forgejo
est renvoyé vers le dépôt GitHub correspondant.

Renseignez ces variables dans `.env` (section Forgejo) :

| Variable | Rôle |
|---|---|
| `FORGEJO_GITHUB_ORG_URL` | URL de l'organisation, ex. `https://github.com/altherneum`. Vide = import désactivé. |
| `GITHUB_TOKEN` | Jeton GitHub (scope `repo`). Nécessaire pour les dépôts privés et le miroir push. |
| `GITHUB_USER` | Identifiant associé au jeton (`x-access-token` convient pour un PAT). |
| `FORGEJO_OWNER` | Propriétaire Forgejo des dépôts importés (défaut : `FORGEJO_ADMIN_NAME`). |
| `FORGEJO_API_TOKEN` | Jeton API optionnel pour les scripts (sinon `FORGEJO_ADMIN_*`). |
| `FORGEJO_GITHUB_PUSH_MIRROR` | `true` pour créer le miroir push Forgejo → GitHub. |
| `FORGEJO_GITHUB_MIRROR_INTERVAL` | Fréquence de synchronisation (`8h`, `24h`, `0` pour manuel). |
| `FORGEJO_GITHUB_MIRROR_SYNC_ON_COMMIT` | `true` pour synchroniser à chaque push reçu. |

Le script est lancé automatiquement après `make up` et
`make up-service SERVICE=forgejo`, une fois Forgejo et sa base prêts. Il est
idempotent : les dépôts déjà présents ne sont pas réimportés et les miroirs
déjà configurés ne sont pas dupliqués.

```sh
sudo make forgejo-mirror
sudo make forgejo-mirror FORGEJO_MIRROR_ARGS=--dry-run
```

Le mode `--dry-run` liste uniquement les dépôts et les actions prévues, sans
modifier Forgejo.

### Jeton GitHub

Créez un **personal access token** (classic) avec le scope `repo`, ou un
fine-grained token avec les droits `Contents: Read and write` sur les dépôts de
l'organisation. Sans jeton :

- seuls les dépôts publics sont importés ;
- aucun miroir push n'est créé (Forgejo ne peut pas s'authentifier sur GitHub).

Le miroir push ne fonctionne que dans le sens **Forgejo → GitHub**. Un commit
poussé directement sur GitHub n'est pas récupéré automatiquement par Forgejo :
poussez sur Forgejo pour que les deux côtés restent alignés, ou synchronisez le
dépôt manuellement dans Forgejo. `make forgejo-mirror` importe uniquement les
dépôts encore absents ; il ne réimporte pas un dépôt déjà présent.

## Travailler depuis code-server

code-server est sur le même réseau Docker que Forgejo. Utilisez l'URL interne
`http://forgejo:3000` : elle contourne Traefik et sa protection HTTP Basic, ce
qui évite de cumuler deux authentifications sur les commandes Git.

```sh
# Cloner un dépôt Forgejo depuis le terminal de code-server
git clone http://forgejo:3000/<propriétaire>/<dépôt>.git

# Pousser un dépôt déjà cloné
cd ~/workspace/<dépôt>
git remote add forgejo http://forgejo:3000/<propriétaire>/<dépôt>.git
git push -u forgejo main
```

Git demande alors l'identifiant et le mot de passe de votre compte Forgejo
(ou un jeton d'accès créé dans *Settings → Applications*). Voir aussi la fiche
[code-server](code-server.md).

## E-mail

Désactivé par défaut (`FORGEJO_MAIL_ENABLED=false`). Une fois mailcow prêt :

```dotenv
FORGEJO_MAIL_ENABLED=true
FORGEJO_MAIL_HOST=mail.monprojet.com
FORGEJO_MAIL_PORT=587
FORGEJO_MAIL_USER=git@monprojet.com
FORGEJO_MAIL_PASSWORD=...
FORGEJO_MAIL_FROM=git@monprojet.com
```

Le mot de passe `FORGEJO_MAIL_PASSWORD` est généré par `make init`. Créez la
boîte `git@` dans mailcow avec le même mot de passe.

## Sauvegarde

`make backup` sauvegarde :

- la base via un dump PostgreSQL `db-forgejo` ;
- le volume `forgejo-data` (dépôts, comptes, configuration).

## Dépannage

- **Impossible de se connecter** : lancez `sudo make forgejo-admin` et vérifiez
  `FORGEJO_ADMIN_*`.
- **Nom admin refusé** : `admin` est réservé, choisissez un autre nom.
- **Erreur de base** : vérifiez `FORGEJO_DB_*` et que `db-forgejo` est
  `healthy`.
- **Clone SSH impossible** : SSH est désactivé, utilisez l'URL HTTPS.
