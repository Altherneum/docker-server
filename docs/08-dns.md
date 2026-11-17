# DNS - domaine, sous-domaines et HTTPS

**But :** faire résoudre `altherneum.fr` et ses sous-domaines vers le serveur,
pour que Traefik puisse demander les certificats Let's Encrypt et servir le
HTTPS.

## Domaine à utiliser

Un seul domaine suffit : `altherneum.fr`. Tous les services sont des
sous-domaines de ce domaine. Dans `.env` :

```dotenv
DOMAIN_NAME=altherneum
TLD=.fr
ACME_EMAIL=admin@altherneum.fr
TRAEFIK_DASHBOARD_HOST=traefik.altherneum.fr
```

`DOMAIN_NAME` ne doit **pas** contenir le `.fr` : il est ajouté par `TLD`.
Avec `DOMAIN_NAME=altherneum.fr` et `TLD=.fr`, on obtiendrait
`altherneum.fr.fr`.

## Tableau minimal (web et HTTPS)

Ces enregistrements suffisent pour que `altherneum.fr` et tous ses
sous-domaines arrivent sur Traefik.

| Type | Nom / hôte | Valeur | Statut | Rôle |
|---|---|---|---|---|
| `A` | `@` (`altherneum.fr`) | IP IPv4 du serveur | **obligatoire** | domaine nu, redirection Discord |
| `AAAA` | `@` | IP IPv6 du serveur | si IPv6 | même chose en IPv6 |
| `CNAME` | `*` | `altherneum.fr.` | **obligatoire** | tous les sous-domaines |
| `CNAME` | `www` | `altherneum.fr.` | recommandé | rend `www` explicite |
| `CNAME` | `git.arch` | `altherneum.fr.` | recommandé | nom à deux niveaux |
| `CAA` | `@` | `0 issue "letsencrypt.org"` | recommandé | autorise Let's Encrypt |

Remarques :

- Le wildcard `*` ne couvre **jamais** le domaine nu : c'est pour cela que
  l'enregistrement `A`/`AAAA` sur `@` est obligatoire.
- `www` est normalement déjà couvert par `*`. L'enregistrement explicite est
  là pour garder la main dessus si vous changez `www` plus tard.
- Un wildcard DNS couvre plusieurs niveaux tant qu'aucun nom intermédiaire
  n'existe. Un enregistrement explicite pour `git.arch` évite de dépendre de ce
  comportement et documente ce cas particulier.
- Si votre fournisseur n'accepte pas de `CNAME` sur `*`, utilisez un
  `A` (et éventuellement `AAAA`) sur `*` avec la même IP que `@`.
- Un `CNAME` ne peut pas être placé sur le domaine nu (`@`). Utilisez `A` ou
  `AAAA`, ou l'option `ALIAS`/`ANAME`/`CNAME flattening` du fournisseur.

### Comprendre les types

| Type | Quand l'utiliser |
|---|---|
| `A` | un nom pointe vers une adresse IPv4 |
| `AAAA` | un nom pointe vers une adresse IPv6 |
| `CNAME` | un nom est un alias d'un autre nom (jamais sur `@`) |
| `MX` | réception des e-mails |
| `TXT` | SPF, DKIM, DMARC, vérifications de domaine |
| `CAA` | liste les autorités de certification autorisées |

## Sous-domaines servis

Tous ces noms sont couverts par l'enregistrement `*`. Il n'est donc **pas**
nécessaire d'en créer un par service.

| Service / usage | Noms |
|---|---|
| Traefik | `traefik` |
| Site PHP | `php`, `phpdoc` |
| Azuriom | `minecraft` |
| Forgejo | `git`, `repo`, `forgejo` |
| code-server | `code`, `vscode` |
| KeeWeb | `keeweb`, `keepass`, `keys`, `key` |
| Nextcloud | `cloud`, `nextcloud`, `drive`, `files` |
| Dockhand | `dockhand`, `docker` |
| Uptime Kuma | `status`, `uptime`, `monitor`, `kuma` |
| phpMyAdmin | `phpmyadmin` |
| Site de memes | `meme`, `windows`, `microsoft`, `arch`, `linux` |
| Mailcow | `mail`, `webmail`, `mails` |
| Redirections | `www`, `docs`, `wiki`, `info`, `github`, `search`, `ask`, `ai`, `ia`, `discord`, `vocal`, `lost`, `mc`, `play` |
| Documentation | `doc` (cible de `docs`, `wiki` et `info`) |
| Minecraft Java | `mc`, `play`, puis `hub`, `survie`, `creatif`, `anarchie`, `rpg`, `skyblock`, `opprison`, `test`, etc. |
| Cas à deux niveaux | `git.arch` |

> `doc.altherneum.fr` est utilisé comme adresse de documentation, mais aucun
> routeur Traefik ne le définit dans ce dépôt. Vérifiez qu'un autre service (ou
> un autre serveur) le sert, sinon `docs`, `wiki` et `info` redirigeront vers
> une adresse en erreur.

## Certificats HTTPS

Traefik utilise la validation **HTTP-01** de Let's Encrypt :

- le nom doit résoudre vers l'IP du serveur ;
- le port `80` doit être accessible depuis Internet ;
- Traefik demande un certificat **par nom d'hôte**, lors du premier accès.

Un wildcard DNS (`*`) ne crée donc pas un certificat wildcard : chaque
sous-domaine reçoit son propre certificat. C'est normal et suffisant ici.

Si un proxy ou un CDN est activé devant le domaine :

- désactivez-le pour les noms gérés par Traefik, sinon la validation HTTP-01
  peut échouer ;
- si la zone contient un enregistrement `CAA`, il doit autoriser
  `letsencrypt.org`, sinon aucun certificat ne sera émis.

## Vérifier

```sh
dig +short A altherneum.fr
dig +short A traefik.altherneum.fr
dig +short A git.arch.altherneum.fr
dig +short CAA altherneum.fr
```

Les trois premières commandes doivent renvoyer la même IP publique.

```sh
curl -I https://traefik.altherneum.fr
```

- `200` ou `302` : DNS et HTTPS fonctionnent ;
- `404` : le DNS est bon, mais aucun routeur Traefik ne correspond au nom ;
- `502` : le service derrière Traefik est arrêté ;
- erreur de certificat : vérifiez le port `80`, le DNS et l'absence de proxy
  devant le nom.

## Messagerie (optionnel, Mailcow)

À ajouter **uniquement** si Mailcow est utilisé. Le port web `mail` passe par
Traefik, mais SMTP/IMAP doivent joindre directement le serveur.

| Type | Nom / hôte | Valeur | Rôle |
|---|---|---|---|
| `A` | `mail` | IP du serveur | nom d'hôte Mailcow, sans proxy |
| `MX` | `@` | `mail.altherneum.fr.` (priorité `10`) | réception des e-mails |
| `TXT` | `@` | `v=spf1 mx ~all` | SPF |
| `TXT` | `dkim._domainkey` | valeur affichée par `sudo make mail-dkim-key` (ou `mail-dkim`) | DKIM |
| `TXT` | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:postmaster@altherneum.fr` | DMARC |

- Le `PTR` est attribué automatiquement par l'hébergeur du VPS. 
- À vérifier seulement si les mails sortants posent problème : voir [Mailcow](services/mailcow.md#ptr-reverse-dns).

> Optionnel : `CNAME autodiscover` et `CNAME autoconfig` vers
> `mail.altherneum.fr.` aident Outlook et Thunderbird à trouver les réglages
> automatiquement. Ce ne sont pas des services d'hébergement DNS : ce sont de
> simples alias, non nécessaires au fonctionnement.

> Le `CNAME *` déjà présent suffit pour le web, mais **pas pour le MX** :
> ajoutez un `A` (et éventuellement `AAAA`) sur `mail`. Une cible de MX ne doit
> pas être un CNAME. Mailcow ne gère qu'un seul domaine ; une seule clé DKIM
> couvre toutes les adresses (`contact@`, `admin@`, ...).

Ordre simple :

1. `sudo make mail-dkim-key` (génère la clé et affiche le TXT DKIM) ;
2. ajoutez `A mail`, `MX`, `SPF`, `DKIM` et `DMARC` dans la zone DNS ;
3. `sudo make mail-setup` (installe Mailcow, importe la clé et crée les boîtes
   `admin@`, `contact@`, etc.) ;
4. configurez le `PTR` dans le panneau de l'hébergeur du VPS (section
   « reverse DNS » de l'adresse IP), puis vérifiez la propagation.

Si une clé DKIM existe déjà sur l'ancien serveur, importez-la avec
`MAIL_CREATE_KEYS=no` et `MAIL_DKIM_PRIVATE_KEY_FILE` au lieu de l'étape 1 :
le TXT DNS reste inchangé.

Le sélecteur DKIM est `dkim` par défaut (`MAIL_DKIM_SELECTOR`). Le TXT est
affiché prêt à coller, avec découpage en chaînes de 255 caractères si le panneau
DNS l'exige :

```sh
sudo make mail-dkim
```

- `MAIL_CREATE_KEYS=yes` régénère la clé : remplacez alors le TXT dans le DNS.
- `MAIL_CREATE_KEYS=no` importe la clé privée existante (ou celle générée par
  `mail-dkim-key`) : le TXT ne change pas.
- `make mail-setup` génère automatiquement une clé si aucune n'est disponible.
- Les fichiers sont dans `backups/mail-dkim-<date>/` (le fichier privé est en
  `600`).

Ouvrez aussi les ports mail (`25`, `465`, `587`, `143`, `993`, et si besoin
`110`, `995`, `4190`) et configurez le reverse DNS dans le panneau de
l'hébergeur du VPS, section « reverse DNS » de l'adresse IP : ce n'est pas un
enregistrement de la zone DNS. `MAIL_ENABLED=true` dans `.env` les ouvre dans
UFW lors d'une installation.

## Si vous ne pouvez pas utiliser de wildcard

Créez un enregistrement `A` (ou `AAAA`) pour chaque nom listé dans
« Sous-domaines servis », avec la même IP que `@`. Utilisez `CNAME` uniquement
pour les alias (`www`, `git.arch`, etc.). Le wildcard reste la solution la plus
simple et la plus facile à maintenir : si l'IP change, un seul enregistrement
est à modifier.
