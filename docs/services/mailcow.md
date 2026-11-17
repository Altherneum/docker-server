# Mailcow - messagerie

**Rôle :** messagerie complète (SMTP, IMAP, webmail) pour **un seul domaine**,
`DOMAIN` (`DOMAIN_NAME` + `TLD`). Toutes les adresses de ce domaine
(`contact@`, `admin@`, `noreply@`, etc.) partagent la même clé DKIM.

**Adresse d'administration :** `https://mail.<domaine>`

**Webmail :** `https://webmail.<domaine>` ou `https://mails.<domaine>`  
**Exemple :** `https://mail.altherneum.fr`

## Installation automatique

Le dossier est défini par `MAILCOW_DIR` dans `.env` :

```dotenv
MAILCOW_DIR=/opt/mailcow-dockerized
```

Mailcow est une stack **officielle séparée**, mais le dépôt l'installe
automatiquement. Le clone officiel va dans `MAILCOW_DIR`
(`/opt/mailcow-dockerized`), jamais dans le dépôt `docker-server` :

```sh
cd /opt/docker-server
sudo make mail-setup
```

Cette commande unique :

- clone `https://github.com/mailcow/mailcow-dockerized.git` dans `MAILCOW_DIR`
  si le dossier est absent ;
- génère `mailcow.conf` (hôte, fuseau horaire, mots de passe) sans questions ;
- installe l'override Traefik, choisit un sous-réseau Docker libre et crée la
  clé API ;
- démarre Mailcow et attend les services/API ;
- importe la clé DKIM pré-générée, ou en génère une ;
- crée les boîtes de base et lance `mail-check`.

`sudo make up-service SERVICE=mailcow` fait la même chose. `sudo make mail-up`
installe si besoin et démarre, sans recréer les boîtes ni la clé DKIM.
`sudo make mail-install` exécute seulement le clone et la configuration, sans
démarrer.

Si Mailcow est déjà installé ailleurs, renseignez `MAILCOW_DIR` : il ne sera pas
recloné. Pour une installation manuelle (débogage uniquement) :

```sh
sudo git clone https://github.com/mailcow/mailcow-dockerized.git /opt/mailcow-dockerized
cd /opt/mailcow-dockerized
sudo ./generate_config.sh
```

Dans ce cas, répondez `MAILCOW_HOSTNAME=mail.<domaine>` et gardez les ports
HTTP/HTTPS proposés. Ils restent **internes** : l'override du dépôt retire leur
publication et Traefik les expose.

## Configuration `.env`

```dotenv
MAIL_ENABLED=true
MAILCOW_DIR=/opt/mailcow-dockerized
MAIL_CREATE_KEYS=no           # yes force une nouvelle clé ; no importe/conserve
MAIL_DKIM_SELECTOR=dkim       # préfixe du TXT DNS
MAIL_DKIM_PRIVATE_KEY_FILE=   # seulement pour importer une ancienne clé
MAIL_DKIM_PRIVATE_KEY=
MAILCOW_API_KEY=              # générée automatiquement si vide
```

`MAIL_ENABLED=true` ouvre les ports mail dans UFW **lors de l'installation**.
Si `install.sh` a déjà tourné avec `MAIL_ENABLED=false`, relancez-le ou ouvrez
les ports manuellement :

```sh
sudo ufw allow 25,110,143,465,587,993,995,4190/tcp
```

Vérifiez aussi le pare-feu de l'hébergeur : beaucoup de VPS bloquent le port
`25` par défaut et il faut demander son déblocage.

## Intégration à Traefik

`sudo make mail-setup` (ou `sudo make up-service SERVICE=mailcow`) installe déjà
l'override et démarre la stack. Pour vérifier ou relancer :

```sh
sudo make mail-check
sudo make mail-up
```

L'override généré par le dépôt :

- retire les ports `80`/`443` de `nginx-mailcow` ;
- connecte `nginx-mailcow` au réseau `PROXY_NETWORK` ;
- ajoute les routeurs `mailcow` et `mailcow-webmail` (hôtes `webmail` et
  `mails`) ;
- choisit un sous-réseau Docker libre (le défaut `172.22.1.0/24` entre souvent
  en conflit avec un ancien réseau) ;
- désactive l'ACME de mailcow (`SKIP_LETS_ENCRYPT=y`) : le web passe par
  Traefik ;
- prépare la clé API qui permet de créer le domaine sans passer par l'interface.

`make mail-check` doit finir sur `0 erreur(s)`. Un avertissement DNS est normal
avant la configuration DNS.

Ouvrez ensuite `https://mail.<domaine>`. Le certificat web est demandé par
Traefik. Premier compte Mailcow : `admin` / `moohoo`, à changer immédiatement.

## Clé DKIM

Une seule clé DKIM est nécessaire pour le domaine. Elle signe tous les messages
de toutes les adresses (`contact@`, `admin@`, ...). Les boîtes se créent dans
l'interface Mailcow et n'ont pas de clé individuelle.

Le comportement est piloté par `MAIL_CREATE_KEYS` :

| Valeur | Comportement de `make mail-dkim` |
|---|---|
| `yes` | Génère une nouvelle paire RSA 2048, l'écrit dans mailcow et affiche le TXT à publier |
| `no` | Importe `MAIL_DKIM_PRIVATE_KEY_FILE` (ou `MAIL_DKIM_PRIVATE_KEY`) sans changer le DNS ; si aucune clé n'est fournie, conserve la clé déjà présente dans Redis |

`make mail-setup` complète ce comportement : si `MAIL_CREATE_KEYS=no` et
qu'aucune clé n'existe (ni fichier, ni inline, ni Redis), il génère
automatiquement une clé et repasse `MAIL_CREATE_KEYS=no` ensuite.

### Pré-générer la clé avant l'installation

Pour remplir le TXT DKIM dans le DNS dès le début, sans attendre Mailcow :

```sh
sudo make mail-dkim-key
```

Le script génère la clé dans `backups/dkim/`, affiche le TXT, et met `.env` à
`MAIL_CREATE_KEYS=no` avec `MAIL_DKIM_PRIVATE_KEY_FILE` renseigné. Après
l'installation, `sudo make mail-dkim` importe cette clé sans la régénérer et
sans modifier le DNS.

### Première génération

Normalement `sudo make mail-setup` s'en charge. Pour la lancer seule :

```sh
sudo make mail-dkim
```

Le script :

- importe la clé pré-générée si `MAIL_DKIM_PRIVATE_KEY_FILE` est renseigné
  (mode `MAIL_CREATE_KEYS=no`), donc le TXT DNS ne change pas ;
- avec `MAIL_CREATE_KEYS=yes` (ou `--generate`), génère une nouvelle clé et
  affiche le TXT à publier ;
- sans clé fournie ni clé Redis, s'arrête avec un message explicite : utilisez
  `make mail-setup` (génération automatique) ou passez `MAIL_CREATE_KEYS=yes` ;
- crée le domaine via l'API mailcow si nécessaire (sans clé DKIM automatique) ;
- écrit directement dans Redis (`DKIM_PRIV_KEYS`, `DKIM_PUB_KEYS`,
  `DKIM_SELECTORS`), sans passer par l'interface web ;
- affiche le TXT prêt à copier et le sauvegarde dans
  `backups/mail-dkim-<date>/` (`dns-records.txt` public,
  `private-keys.pem` en `600`) ;
- sauvegarde l'ancienne clé avant un remplacement ;
- redémarre `rspamd-mailcow` pour recharger la clé.

Après une génération, le script repasse automatiquement
`MAIL_CREATE_KEYS=no` : `sudo make mail-dkim` réaffichera la clé existante sans
la régénérer.

> Avec `MAIL_CREATE_KEYS=yes`, le nouveau TXT doit remplacer l'ancien dans le
> DNS. Tant que la propagation n'est pas terminée, DKIM peut échouer.
> Avec `MAIL_CREATE_KEYS=no`, le TXT existant reste valide tant que la clé
> privée correspond et que le sélecteur est le même.

### Reprendre la clé DKIM de l'ancien serveur

Pour ne pas changer le TXT DNS existant, exportez la clé privée de l'ancien
mailcow, copiez-la sur le nouveau serveur, puis utilisez le mode `no` :

```sh
# Sur l'ANCIEN serveur : lire le sélecteur et la clé privée.
OLD_DIR=/opt/mailcow-dockerized
REDISPASS=$(sed -n 's/^REDISPASS=//p' "$OLD_DIR/mailcow.conf")
cd "$OLD_DIR"

docker compose exec -T -e REDISCLI_AUTH="$REDISPASS" redis-mailcow \
  redis-cli --no-auth-warning HGET DKIM_SELECTORS example.com
# → dkim

docker compose exec -T -e REDISCLI_AUTH="$REDISPASS" redis-mailcow \
  redis-cli --no-auth-warning HGET DKIM_PRIV_KEYS dkim.example.com \
  > /tmp/dkim-example.com.pem
```

Copiez `/tmp/dkim-example.com.pem` sur le nouveau serveur (par exemple dans
`/root/dkim-example.com.pem`, permissions `600`), puis dans `.env` :

```dotenv
MAIL_CREATE_KEYS=no
MAIL_DKIM_SELECTOR=dkim
MAIL_DKIM_PRIVATE_KEY_FILE=/root/dkim-example.com.pem
```

`sudo make mail-dkim` réimporte la clé et réaffiche le TXT. Si le TXT DNS
existant est identique, il n'y a rien à changer. La clé peut être au format
PKCS#8 (`BEGIN PRIVATE KEY`) ou PKCS#1 (`BEGIN RSA PRIVATE KEY`).

## Boîtes mail de base

```sh
sudo make mail-mailboxes
```

Par défaut, le script crée `admin@`, `contact@`, `root@`, `postmaster@` et
`abuse@`. Il :

- crée le domaine via l'API s'il n'existe pas encore ;
- crée chaque boîte avec un quota de 1 Go ;
- génère les mots de passe manquants et les écrit dans `.env`
  (`MAILBOX_<NOM>_PASSWORD`) ;
- ne modifie pas une boîte déjà existante (elle est signalée « déjà présente »).

La liste est modifiable :

```dotenv
MAIL_MAILBOXES=admin,contact,root,postmaster,abuse,noreply,git,cloud
```

`noreply` utilise `AZURIOM_MAIL_PASSWORD`, `git` utilise
`FORGEJO_MAIL_PASSWORD` et `cloud` utilise `NEXTCLOUD_MAIL_PASSWORD`.

> `admin@<domaine>` est une boîte mail. Le compte d'administration Mailcow est
> `admin` (sans `@`), avec le mot de passe initial `moohoo`.

## Enregistrements DNS mail

Exemple pour `altherneum.fr` : remplacez le domaine et l'IP par les vôtres.

| Type | Nom / hôte | Valeur | Rôle |
|---|---|---|---|
| `A` | `mail` | IP du serveur | nom d'hôte mailcow ; **pas un CNAME** |
| `MX` | `@` | `mail.altherneum.fr.` (priorité `10`) | réception |
| `TXT` | `@` | `v=spf1 mx ~all` | SPF |
| `TXT` | `dkim._domainkey` | valeur affichée par `make mail-dkim` | DKIM |
| `TXT` | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:postmaster@altherneum.fr` | DMARC |
| `CNAME` | `autodiscover` | `mail.altherneum.fr.` | Outlook |
| `CNAME` | `autoconfig` | `mail.altherneum.fr.` | Thunderbird |
| `PTR` | IP du serveur | `mail.altherneum.fr.` | reverse DNS, chez l'hébergeur |

Points importants :

- Le `CNAME *` déjà présent suffit pour le web, mais **pas pour le MX** :
  ajoutez l'`A mail`. Un MX ne doit pas pointer vers un CNAME.
- S'il existe déjà un TXT SPF, fusionnez-le : il ne doit y avoir qu'un seul
  enregistrement SPF par domaine.
- Le TXT DKIM peut être long : le script fournit la valeur brute et la version
  découpée en chaînes de 255 caractères.
- Pour DMARC, `p=none` permet d'observer avant de passer à `quarantine`.
- Chez Cloudflare : `mail`, `autodiscover` et `autoconfig` en **DNS only**
  (nuage gris). Les MX et TXT ne sont pas proxifiés.
- Le `PTR` se configure chez l'hébergeur du VPS, pas dans la zone DNS.

## Vérifier

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

Envoyez ensuite un message vers un test (Gmail, mail-tester.com) et vérifiez
SPF/DKIM/DMARC. Logs : `sudo make mail-logs`.

## Démarrer / arrêter

```sh
sudo make mail-setup                   # installation + DKIM + boîtes
sudo make up-service SERVICE=mailcow   # alias de mail-setup
sudo make mail-up                      # démarrage / redémarrage seul
sudo make mail-logs
sudo make mail-down
```

`make mail-setup` installe Mailcow si nécessaire, prépare l'override Traefik,
démarre la stack, importe la clé DKIM et crée les boîtes de base. `make mail-up`
installe si besoin et démarre uniquement la stack. `make mail-dkim` n'est
volontairement pas appelé à chaque redémarrage : cela éviterait de régénérer la
clé par accident.

## Configurer Azuriom, Forgejo et Nextcloud

Une fois Mailcow prêt et les boîtes créées (`make mail-mailboxes` avec
`noreply,git,cloud` dans `MAIL_MAILBOXES`, ou via l'interface) :

```dotenv
AZURIOM_MAIL_MAILER=smtp
AZURIOM_MAIL_HOST=mail.altherneum.fr
AZURIOM_MAIL_USERNAME=noreply@altherneum.fr
AZURIOM_MAIL_PASSWORD=...

FORGEJO_MAIL_ENABLED=true
FORGEJO_MAIL_HOST=mail.altherneum.fr
FORGEJO_MAIL_USER=git@altherneum.fr
FORGEJO_MAIL_PASSWORD=...

NEXTCLOUD_MAIL_HOST=mail.altherneum.fr
NEXTCLOUD_MAIL_USERNAME=cloud@altherneum.fr
NEXTCLOUD_MAIL_PASSWORD=...
NEXTCLOUD_MAIL_FROM_ADDRESS=cloud@altherneum.fr
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

## Certificat SMTP/IMAP (optionnel)

Par défaut, `https://mail.<domaine>` utilise le certificat public de Traefik et
SMTP/IMAP utilisent le certificat interne auto-signé de Mailcow. Votre client
peut donc afficher un avertissement.

Pour un certificat public sur SMTP/IMAP, le dépôt peut activer le **DNS-01** de
Mailcow. Il faut les identifiants API de votre fournisseur DNS :

```dotenv
MAIL_ACME_DNS_CHALLENGE=true
MAIL_ACME_DNS_PROVIDER=dns_cf
MAIL_ACME_ACCOUNT_EMAIL=admin@altherneum.fr
MAIL_ACME_DNS_CONFIG_FILE=/root/mailcow-dns-01.conf
```

Le fichier de secrets reprend les variables d’acme.sh. Un modèle est fourni :

```sh
sudo cp stacks/mail/acme-dns.conf.example /root/mailcow-dns-01.conf
sudo chmod 600 /root/mailcow-dns-01.conf
sudo nano /root/mailcow-dns-01.conf
```

Exemple Cloudflare (`dns_cf`) :

```dotenv
CF_Token=votre_token_api
#CF_Account_ID=
#CF_Zone_ID=
```

Puis relance :

```sh
sudo make mail-setup
# ou : sudo make mail-integrate && sudo make mail-up
```

`mail-integrate` écrit automatiquement `SKIP_LETS_ENCRYPT=n`,
`ACME_DNS_CHALLENGE=y`, le fournisseur et l’e-mail dans `mailcow.conf`, puis
copie les secrets dans `$MAILCOW_DIR/data/conf/acme/dns-01.conf`. Mailcow
renouvelle ensuite le certificat automatiquement.

Vérification :

```sh
sudo make mail-check
openssl s_client -connect mail.altherneum.fr:993 -servername mail.altherneum.fr </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

Le fournisseur DNS doit autoriser la création de TXT `_acme-challenge`, et le
domaine doit autoriser Let’s Encrypt via CAA si un enregistrement CAA existe.

## Dépannage

- **`mail.<domaine>` ne répond pas** : vérifiez que Traefik tourne et que
  `sudo make mail-check` ne signale pas d'erreur.
- **Erreur de certificat web** : vérifiez l'`A mail`, le port `80` et
  `sudo make mail-check`.
- **Erreur de certificat SMTP/IMAP** : c'est le certificat interne de Mailcow ;
  acceptez-le dans le client ou configurez DNS-01.
- **Mailcow ne démarre pas** : le sous-réseau `172.22.1.0/24` est peut-être déjà
  utilisé. `make mail-integrate` en choisit un autre automatiquement ; sinon
  renseignez `MAILCOW_IPV4_NETWORK=172.30.1` dans `.env`.
- **Port déjà utilisé** : `sudo make mail-check` indique lequel. Libérez-le ou
  arrêtez l'ancien service mail.
- **DKIM échoue** : vérifiez le sélecteur (`MAIL_DKIM_SELECTOR`), le TXT
  `<selecteur>._domainkey.<domaine>` et la propagation DNS. Relancez
  `sudo make mail-dkim` puis consultez `backups/mail-dkim-*/dns-records.txt`.
- **Les e-mails ne partent pas** : vérifiez les DNS (SPF, DKIM, DMARC), le PTR,
  le port `25` chez l'hébergeur et les logs Mailcow.

```sh
sudo make mail-logs
```
