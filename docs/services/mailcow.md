# Mailcow - messagerie

**Rôle :** messagerie complète (SMTP, IMAP, webmail) pour le domaine. Mailcow
est une stack **séparée**, installée hors de ce dépôt.

**Adresse d'administration :** `https://mail.<DOMAIN_NAME><TLD>`  
**Webmail :** `https://webmail.<domaine>` ou `https://mails.<domaine>`  
**Exemple :** `https://mail.supername.fr`

## Où est Mailcow ?

Le dossier est défini par `MAILCOW_DIR` dans `.env` :

```dotenv
MAILCOW_DIR=/opt/mailcow-dockerized
```

Mailcow suit sa propre documentation :
<https://docs.mailcow.email/>. Installez-le d'abord dans ce dossier.

## Mot de passe

| Quoi | Où est le mot de passe ? |
|---|---|
| Compte admin Mailcow | Créé/configuré pendant l'installation de Mailcow, **pas dans ce `.env`** (souvent `admin` / `moohoo` au premier lancement, à changer immédiatement) |
| Boîte `noreply@<domaine>` | `AZURIOM_MAIL_PASSWORD` dans `.env` |
| Boîte `git@<domaine>` | `FORGEJO_MAIL_PASSWORD` dans `.env` |
| Boîte `cloud@<domaine>` | `NEXTCLOUD_MAIL_PASSWORD` dans `.env` |
| Bases Mailcow | Dans `mailcow.conf`, pas dans ce dépôt |

Les mots de passe de ces boîtes sont générés par `make init`. Créez les boîtes
dans l'interface Mailcow avec exactement ces mots de passe.

## Intégration à Traefik

Mailcow ne doit pas publier ses propres ports `80`/`443` : c'est Traefik qui les
gère.

1. Vérifiez que le réseau `PROXY_NETWORK` existe :

```sh
sudo make ensure-networks
```

2. Copiez le modèle d'override et remplacez les placeholders :

```sh
cd /opt/docker-server

# Lire les valeurs résolues depuis .env
ENV_DUMP=$(docker compose --env-file .env config --environment)
get_env() { printf '%s\n' "$ENV_DUMP" | sed -n "s/^$1=//p" | tail -n1; }

DOMAIN_NAME=$(get_env DOMAIN_NAME)
TLD=$(get_env TLD)
DOMAIN="${DOMAIN_NAME}${TLD}"
DOMAIN_REGEX=$(printf '%s' "$DOMAIN" | sed 's/\./[.]/g')
PROXY_NETWORK=$(get_env PROXY_NETWORK)
MAILCOW_DIR=$(get_env MAILCOW_DIR)
MAILCOW_DIR=${MAILCOW_DIR:-/opt/mailcow-dockerized}

sudo cp stacks/mail/traefik.override.yaml.template \
  "$MAILCOW_DIR/docker-compose.override.yml"
sudo sed -i \
  -e "s|@@PROXY_NETWORK@@|$PROXY_NETWORK|g" \
  -e "s|@@DOMAIN_REGEX@@|$DOMAIN_REGEX|g" \
  -e "s|@@DOMAIN@@|$DOMAIN|g" \
  "$MAILCOW_DIR/docker-compose.override.yml"
```

Exemple : `@@DOMAIN@@` devient `supername.fr` et `@@DOMAIN_REGEX@@` devient
`supername[.]fr`.

> `make mail-integrate` est prévu pour automatiser cette étape, mais le script
> actuel ne copie pas encore l'override dans `MAILCOW_DIR`. Vérifiez le fichier
> après l'avoir lancé.

## Démarrer / arrêter

```sh
sudo make mail-up
sudo make mail-logs
sudo make mail-down
```

`make mail-up` lance Mailcow avec `docker-compose.yml` et
`docker-compose.override.yml`.

## Configurer Azuriom, Forgejo et Nextcloud

Une fois Mailcow prêt et les boîtes créées :

```dotenv
AZURIOM_MAIL_MAILER=smtp
AZURIOM_MAIL_HOST=mail.monprojet.com
AZURIOM_MAIL_USERNAME=noreply@monprojet.com
AZURIOM_MAIL_PASSWORD=...

FORGEJO_MAIL_ENABLED=true
FORGEJO_MAIL_HOST=mail.monprojet.com
FORGEJO_MAIL_USER=git@monprojet.com
FORGEJO_MAIL_PASSWORD=...

NEXTCLOUD_MAIL_HOST=mail.monprojet.com
NEXTCLOUD_MAIL_USERNAME=cloud@monprojet.com
NEXTCLOUD_MAIL_PASSWORD=...
NEXTCLOUD_MAIL_FROM_ADDRESS=cloud@monprojet.com
```

Puis redémarrez Azuriom, Forgejo et Nextcloud.

## Nettoyer

Mailcow n'est pas géré par `make clean`. Utilisez ses propres commandes :

```sh
# Remplacez par la valeur de MAILCOW_DIR dans .env
cd /opt/mailcow-dockerized
docker compose down -v
```

> **Destructif** : cela supprime les boîtes, les messages et la base Mailcow.

## Sauvegarde

`make backup` ne sauvegarde **pas** Mailcow. Utilisez la procédure officielle de
Mailcow (`backup_and_restore.sh`) et sauvegardez aussi `mailcow.conf`.

## Dépannage

- **`mail.<domaine>` ne répond pas** : vérifiez que Traefik tourne et que
  l'override est bien chargé.
- **Erreur de certificat** : Mailcow utilise son propre certificat derrière
  Traefik ; l'override désactive la vérification (`insecureSkipVerify`).
- **Les e-mails ne partent pas** : vérifiez les DNS (SPF, DKIM, DMARC) et les
  logs Mailcow.

```sh
sudo make mail-logs
```
