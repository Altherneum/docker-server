# Accès et URL

## La règle à retenir

Toutes les adresses web utilisent le même modèle :

```text
https://<sous-domaine>.<DOMAIN_NAME><TLD>
```

Exemple avec `DOMAIN_NAME=supername` et `TLD=.fr` :

```text
https://git.supername.fr
        ^^^  ^^^^^^^^ ^^
sous-domaine, nom, extension

```

Si vous changez `DOMAIN_NAME` ou `TLD`, **toutes les adresses changent**.
Le domaine `supername.fr` n'est qu'un exemple.

| `DOMAIN_NAME` | `TLD` | Adresse Forgejo |
|---|---|---|
| `supername` | `.fr` | `https://git.supername.fr` |
| `monprojet` | `.com` | `https://git.monprojet.com` |
| `localhost` | *(vide)* | `https://git.localhost` |

## Toutes les adresses

| Service | Sous-domaine | Authentification | Mot de passe dans `.env` |
|---|---|---|---|
| Traefik | `traefik` | HTTP Basic | `TRAEFIK_DASHBOARD_USER` / `TRAEFIK_DASHBOARD_PASSWORD` |
| Site PHP | `php` ou `phpdoc` | Compte du site | `WEBSITE_ADMIN_USERNAME` / `WEBSITE_ADMIN_PASSWORD` |
| Azuriom | `minecraft` | Compte Azuriom | `AZURIOM_ADMIN_NAME` / `AZURIOM_ADMIN_PASSWORD` |
| Forgejo | `git`, `repo` ou `forgejo` | Compte Forgejo | `FORGEJO_ADMIN_NAME` / `FORGEJO_ADMIN_PASSWORD` |
| code-server | `code` ou `vscode` | HTTP Basic puis mot de passe éditeur | `CODE_SERVER_HTTP_USER` / `CODE_SERVER_HTTP_PASSWORD` puis `CODE_SERVER_PASSWORD` |
| KeeWeb | `keeweb`, `keepass`, `keys` ou `key` | HTTP Basic | `KEEWEB_UI_USER` / `KEEWEB_UI_PASSWORD` |
| Nextcloud | `cloud`, `nextcloud`, `drive` ou `files` | Compte Nextcloud | `NEXTCLOUD_ADMIN_USER` / `NEXTCLOUD_ADMIN_PASSWORD` |
| phpMyAdmin | `phpmyadmin` | HTTP Basic puis compte MariaDB | `PMA_ADMIN_USER` / `PMA_ADMIN_PASSWORD`, puis `PHP_DB_*`, `AZURIOM_DB_*` ou `NEXTCLOUD_DB_*` |
| Meme | `meme`, `windows`, `microsoft`, `arch` ou `linux` | Aucune | - |
| Mailcow | `mail` | Compte mailcow | Mot de passe créé pendant l'installation de mailcow |
| Webmail | `webmail` ou `mails` | Compte mailcow | Redirige vers `mail.<domaine>` |

Nextcloud n'a **pas** de protection HTTP Basic : son authentification propre
est utilisée pour rester compatible avec les clients desktop/mobile, WebDAV et
CalDAV/CardDAV.

Les bases de données, le bot Discord, fail2ban et les serveurs Paper ne sont
pas accessibles par une URL publique. Voir leurs fiches.

## Adresses Minecraft

| Usage | Adresse |
|---|---|
| Java (premium ou hors-ligne) | `mc.<DOMAIN_NAME><TLD>:25565` |
| Bedrock | `mc.<DOMAIN_NAME><TLD>` port `19132` |
| Accès direct à un serveur | `<serveur>.<DOMAIN_NAME><TLD>:25565` |

Exemples de serveurs : `hub`, `survie`, `creatif`, `anarchie`, `rpg`,
`skyblock`, `opprison`, `test`.

Le port `25565` est publié par Traefik. Les ports `19132` et `19133` sont
publiés par Velocity.

## Redirections automatiques

Traefik redirige aussi certains noms :

| Adresse | Destination |
|---|---|
| `https://<domaine>` et `www` | Discord |
| `docs`, `wiki`, `info` | `https://doc.<domaine>` |
| `discord` | Invitation Discord |
| `vocal` | Invitation Discord vocal |
| `github` | `https://github.com/Altherneum` |
| `search` | Recherche Brave |
| `ask`, `ai`, `ia` | Brave Ask |
| `mc`, `play` | Azuriom (`minecraft.<domaine>`) |

## DNS et certificats

Pour que les adresses fonctionnent :

1. Le nom de domaine doit pointer vers l'IP publique du serveur.
2. Le port `80` doit être accessible (validation Let's Encrypt).
3. Le port `443` doit être accessible (sites HTTPS).

Le plus simple est de créer un wildcard DNS :

```text
*.monprojet.com  ->  IP du serveur
```

Le wildcard ne couvre pas le domaine nu (`monprojet.com`) : gardez un
enregistrement `A`/`AAAA` sur l'apex. Ajoutez aussi un enregistrement explicite
pour les noms à deux niveaux comme `git.arch.monprojet.com` si vous voulez
éviter de dépendre du comportement du fournisseur.

Sinon, créez un enregistrement pour chaque sous-domaine utilisé. Le tableau
minimal complet (apex, wildcard, exceptions, mail) est dans
[DNS](08-dns.md).

Les certificats sont demandés **automatiquement** par Traefik lors du premier
accès. Ils peuvent prendre quelques secondes. Si vous utilisez Cloudflare,
désactivez le proxy pour les noms concernés, sinon la validation HTTP peut
échouer.

## Tester une adresse

```sh
curl -I https://git.monprojet.com
```

Une réponse `200`, `301` ou `302` signifie que Traefik et le service répondent.
Une erreur `404` indique souvent un mauvais nom de domaine. Une erreur `502`
indique que le service derrière Traefik n'est pas démarré.
