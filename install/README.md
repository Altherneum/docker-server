# Dossier `install`

Tout est lancé par un seul script : **`install.sh`** à la racine.

Il installe un VPS vierge de bout en bout :

1. vérifie la clé SSH ;
2. installe Docker et les outils ;
3. clone le dépôt et génère `.env` ;
4. crée le compte admin ;
5. configure SSH, UFW et les mises à jour.

Le code est découpé en petits modules numérotés. `install.sh` les charge dans
l'ordre, puis appelle `main()` dans `28-main.sh`. **Aucun module ne s'exécute
tout seul.**

## Comprendre en 10 secondes

| Plage | Rôle |
|---|---|
| `00` à `10` | Préparer la machine : configuration, Docker, dépôt, `.env` |
| `11` à `27` | Sécuriser l'hôte : compte admin, SSH, pare-feu, mises à jour |
| `28` | Ordre d'exécution de l'installation |

- Les réglages et les fonctions communes sont dans `00-config.sh`.
- Les valeurs de `.env` sont lues après `make init`, par
  `load_security_config()`. fail2ban est un conteneur séparé dans
  `stacks/fail2ban/` ; il lit les logs SSH de l'hôte.
- La clé SSH publique est vérifiée avant toute modification du système.
- Le port SSH vient de `HARDEN_SSH_PORT` dans `.env` (`22` par défaut).
- `MINECRAFT_RCON_PORT` est utilisé pour Paper et Azuriom ; il n'est pas ouvert
  dans UFW et n'est pas publié sur l'hôte.

## Modules

| Fichier | Rôle |
|---|---|
| `00-config.sh` | Variables globales, messages, lecture de `.env` |
| `01-cli.sh` | Dossier du projet et option `--pubkey-file` |
| `02-key.sh` | Validation de la clé SSH obligatoire |
| `03-system.sh` | Root, détection de l'OS et des services |
| `04-packages.sh` | Helpers d'installation de paquets |
| `05-docker-install.sh` | Installation de Docker et des outils |
| `06-docker-service.sh` | Plugin Compose, logs Docker et attente du démon |
| `07-repo.sh` | Clone ou mise à jour du dépôt |
| `08-init.sh` | `make init` : `.env`, secrets, réseaux |
| `09-files.sh` | Écriture de fichiers et sauvegardes |
| `10-services.sh` | Activation et redémarrage des services |
| `11-ports.sh` | Validation des ports et liste UFW |
| `12-admin-user.sh` | Validation et création du compte admin |
| `13-admin-groups.sh` | Groupes docker, sudo et wheel |
| `14-admin-sudo.sh` | Règle sudo du compte admin |
| `15-admin-password.sh` | Mot de passe du compte admin |
| `16-ssh-tools.sh` | Installation d'OpenSSH et de `rsyslog` |
| `17-ssh-keys.sh` | Clés publiques dans `authorized_keys` |
| `18-sshd-config.sh` | Configuration SSH et orchestration |
| `19-sshd-port.sh` | Port SSH et directives `Port` |
| `20-sshd-validate.sh` | Validation de `sshd -t` |
| `21-sshd-service.sh` | Rechargement et restauration de SSH |
| `22-ufw.sh` | Pare-feu UFW |
| `23-auto-updates.sh` | Mises à jour automatiques Linux |
| `24-webhooks.sh` | Notifications Discord des connexions SSH |
| `25-motd.sh` | Message d'accueil SSH |
| `26-env-permissions.sh` | Permissions de `.env` |
| `27-report.sh` | Rapport final et prochaines étapes |
| `28-main.sh` | Ordre d'exécution |

## Ajouter un module

1. Créer un fichier `NN-nom.sh` avec une ou plusieurs fonctions.
2. Ne rien exécuter au chargement du fichier.
3. Appeler la fonction depuis `main()` dans `28-main.sh`.

Le fichier est chargé automatiquement par `install.sh` grâce à son numéro.
