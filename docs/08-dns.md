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

Si vous utilisez Cloudflare :

- laissez le proxy **désactivé** (« DNS only ») pour les noms gérés par
  Traefik, sinon la validation HTTP-01 peut échouer ;
- si vous voulez garder le proxy Cloudflare, il faut passer Traefik en
  validation DNS-01 et demander un certificat wildcard (non configuré dans ce
  dépôt) ;
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
- erreur de certificat : vérifiez le port `80`, le DNS et le proxy Cloudflare.

## Messagerie (optionnel, Mailcow)

À ajouter **uniquement** si Mailcow est utilisé. Le port web `mail` passe par
Traefik, mais SMTP/IMAP doivent joindre directement le serveur.

| Type | Nom / hôte | Valeur | Rôle |
|---|---|---|---|
| `A` | `mail` | IP du serveur | nom d'hôte Mailcow, sans proxy |
| `MX` | `@` | `mail.altherneum.fr.` (priorité `10`) | réception des e-mails |
| `TXT` | `@` | `v=spf1 mx ~all` | SPF |
| `TXT` | `dkim._domainkey` | valeur fournie par Mailcow | DKIM |
| `TXT` | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:postmaster@altherneum.fr` | DMARC |
| `CNAME` | `autodiscover` | `mail.altherneum.fr.` | configuration Outlook |
| `CNAME` | `autoconfig` | `mail.altherneum.fr.` | configuration Thunderbird |
| `PTR` | IP du serveur | `mail.altherneum.fr.` | reverse DNS, chez l'hébergeur |

Ouvrez aussi les ports mail (`25`, `465`, `587`, `143`, `993`) et configurez le
reverse DNS chez l'hébergeur : ce n'est pas un enregistrement de la zone DNS.

## Si vous ne pouvez pas utiliser de wildcard

Créez un enregistrement `A` (ou `AAAA`) pour chaque nom listé dans
« Sous-domaines servis », avec la même IP que `@`. Utilisez `CNAME` uniquement
pour les alias (`www`, `git.arch`, `autodiscover`, `autoconfig`). Le wildcard
reste la solution la plus simple et la plus facile à maintenir : si l'IP change,
un seul enregistrement est à modifier.
