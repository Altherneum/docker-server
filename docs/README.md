# Documentation
Cette documentation explique simplement comment installer, démarrer, arrêter et
nettoyer les services de ce dépôt

## Démarrage rapide

```sh
# 1. Cloner le dépôt
git clone https://github.com/lx78WyY0J5/docker-server.git
cd docker-server

# 2. Créer et remplir .env
cp .env.example .env
chmod 600 .env
nano .env

# 3. Sur votre poste : créer la clé SSH et copier la clé publique
#    ssh-keygen -t ed25519
#    scp ~/.ssh/id_ed25519.pub root@<ip>:/tmp/id_ed25519.pub

# 4. Installer Docker, générer les secrets et sécuriser l'hôte
sudo ./install.sh --pubkey-file /tmp/id_ed25519.pub

# 5. Tester la connexion SSH dans un autre terminal AVANT de fermer
#    ssh -p <port> admin@<ip>
#    su -

# 6. Démarrer les services
sudo make check-env
sudo make up
sudo make ps
```

> La clé SSH est obligatoire. Ne fermez pas la fenêtre d'installation avant
> d'avoir testé la connexion par clé.
> Si votre utilisateur est dans le groupe `docker`, vous pouvez retirer `sudo`
> des commandes `make`. Les commandes se lancent **toujours depuis la racine du
> dépôt**.

Pour la méthode manuelle (paquets, hardening) et la liste des conteneurs, voir
[Installation](01-installation.md). Pour arrêter, redémarrer, sauvegarder ou
restaurer, voir [Commandes](03-commandes.md).

## Comprendre les adresses

Les adresses sont construites à partir de deux variables de `.env` :

- `DOMAIN_NAME` : le nom, sans extension. Exemple : `supername`
- `TLD` : l'extension, avec le point. Exemple : `.fr` (ou vide pour `localhost`)

L'adresse d'un service suit ce modèle :

```text
https://<service>.<DOMAIN_NAME><TLD>
```

Exemples :

| `DOMAIN_NAME` | `TLD` | Adresse de Forgejo |
|---|---|---|
| `supername` | `.fr` | `https://git.supername.fr` |
| `monprojet` | `.com` | `https://git.monprojet.com` |
| `localhost` | *(vide)* | `https://git.localhost` |

Le domaine `supername.fr` utilisé dans les exemples n'est **pas obligatoire** :
remplacez-le par le vôtre. Voir [Accès et URL](04-acces-et-urls.md).

## Trouver un mot de passe

La plupart des mots de passe sont générés par `sudo make init` et stockés dans
`.env`. Pour en lire un :

```sh
sudo grep '^CODE_SERVER_PASSWORD=' .env
```

Ne partagez jamais `.env` et ne le commitez jamais : il contient tous les
secrets. Le fichier est déjà ignoré par Git.

## Repères dans le dépôt

| Dossier / fichier | Contenu |
|---|---|
| `compose.yaml` | Point d'entrée de toutes les stacks |
| `Makefile` | Commandes `make` |
| `.env` | Configuration et secrets (jamais commité) |
| [`stacks/`](../stacks/README.md) | Une stack par service |
| [`images/`](../images/README.md) | Images Docker de base |
| [`scripts/`](../scripts/README.md) | Scripts appelés par le `Makefile` |
| [`backups/`](../backups/README.md) | Sauvegardes locales |
| `install.sh` + `install/` | Installation complète : Docker, dépôt, `.env`, sécurisation |

## Guides généraux

| Guide | Contenu |
|---|---|
| [Installation](01-installation.md) | Installation simple ou manuelle, conteneurs, commandes, DNS, ports |
| [Sécurisation de l'hôte](07-securisation.md) | Compte admin, SSH, UFW, fail2ban, mises à jour |
| [Configuration `.env`](02-configuration-env.md) | Variables, secrets, mots de passe |
| [Commandes](03-commandes.md) | Démarrer, arrêter, redémarrer, nettoyer |
| [Accès et URL](04-acces-et-urls.md) | Toutes les adresses et les ports |
| [DNS](08-dns.md) | Domaine, sous-domaines et certificats HTTPS |
| [Sauvegarde et restauration](05-backup-restore.md) | `make backup`, `make restore` |
| [Dépannage](06-depannage.md) | Erreurs fréquentes et solutions |

## Fiches par service

| Service | Fiche | Adresse par défaut (exemple) |
|---|---|---|
| Traefik (proxy) | [traefik.md](services/traefik.md) | `https://traefik.supername.fr` |
| Site PHP | [php-site.md](services/php-site.md) | `https://php.supername.fr` |
| Azuriom | [azuriom.md](services/azuriom.md) | `https://minecraft.supername.fr` |
| Forgejo | [forgejo.md](services/forgejo.md) | `https://git.supername.fr` |
| code-server | [code-server.md](services/code-server.md) | `https://code.supername.fr` |
| KeeWeb | [keeweb.md](services/keeweb.md) | `https://keeweb.supername.fr` |
| phpMyAdmin | [phpmyadmin.md](services/phpmyadmin.md) | `https://phpmyadmin.supername.fr` |
| Site de memes | [meme.md](services/meme.md) | `https://meme.supername.fr` |
| Minecraft | [minecraft.md](services/minecraft.md) | `mc.supername.fr:25565` |
| Bot Discord | [discord-bot.md](services/discord-bot.md) | *(pas d'URL)* |
| fail2ban | [fail2ban.md](services/fail2ban.md) | *(pas d'URL)* |
| Mailcow | [mailcow.md](services/mailcow.md) | `https://mail.supername.fr` |
| Bases de données | [databases.md](services/databases.md) | *(accès interne)* |
| Images de base | [base-images.md](services/base-images.md) | *(pas d'URL)* |

## Règles d'or

1. **Sauvegardez avant de nettoyer.** `clean` et `clean-service` suppriment des
   données.
2. **Ne modifiez pas `.env` à la légère après le premier démarrage.** Certains
   mots de passe sont déjà enregistrés dans les applications ou les bases.
3. **Traefik doit tourner** pour que les sites HTTPS répondent.
4. **Ouvrez les bons ports** sur le routeur/pare-feu : `80`, `443`, `25565`,
   et les ports Bedrock si vous utilisez Minecraft.
