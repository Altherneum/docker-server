# ToDo list
## SSH + UFW
- Quand docker-server est installé
- il faut ajouter les clefs SSH privés
- Configurer UFW ?
## JDA bot discord convert
- Vérifier + tester si la conversion vers JDA est OK
## Liste
| Services | Sous-Section | Description | Validation |
|---|---|---|---|
| `traefik` | ------------ | ------------ | OK |
| `traefik` #2 | TLS pour remplacer cerbot | Vérifier si le TLS se crée sur un VPS avec DNS | à faire |
| `php-site` | ------------ | ------------ | OK |
| `php-site` #1 | Vérifie le /api/deploy | Vérifier si le git pull marche bien lors d'un /api/deploy | à re valider |
| `azuriom` | ------------ | ------------ | OK |
| `azuriom` #1 | ------------ | Vérifier la boutique, si les commandes sont bien envoyés, ainsi que les clés privés de payement "dédipass" etc | à faire |
| `azuriom` #2 | Image dynamique | Dans le futur, ajouter les images à la racine, et indiquer à l'utilisateur de les remplacer au besoin (car avec le logo Altherneum, et le projet doit pouvoir changer de nom/identité facilement), images dans un dossier ".env", les copiers de ce .env vers le bon endroit (azuriom, logo minecraft server.png, etc) | à faire |
| `keeweb` | ------------ | ------------ | OK |
| `keeweb` | Test WebDav | Le WebDav est censé être vide, et n'a jamais été testé, ajouetr une clé et tester | à faire |
| `phpmyadmin` | ------------ | ------------ | OK |
| `meme` | ------------ | ------------ | à faire |
| `meme` | Dynamic variable .env | Cacher les termes "Altherneum" dans le code source, utiliser une variable, et l'ajouter au .env, puis faire un script qui remplace la variable lors de l'installation de ce site | à faire |
| `forgejo`, `db-forgejo`, `admin account` | ------------ | ------------ | OK |
| `forgejo` | Clone repo | Cloner les repo et faire une synchro mirroire | à faire |
| `forgejo` | Basic auth | Ajouter une basic auth password avec Traefik | à faire |
| `code-server` | ------------ | ------------ | OK |
| `code-server` #1 | git clone | Cloner les repo par défaut pour aller plus vite | à faire |
| `velocity`, `mc-*` | ------------ | ------------ | OK |
| `Plugin` | ------------ | ------------ | OK |
| `Plugin` #1 | Logo resource pack | Je crois qu'un logo manque / est cassé : Logo du shop vanilla (diamond), alors qu'il devrait (de mémoire) être un billet doré | à faire |
| `bot` | ------------ | ------------ | à faire |
| `bot` | Test avec token | Ajouter le token et tester si le bot marche toujours, rapide et simple | à faire |
| `fail2ban` | ------------ | ------------ | à faire |
| `nextcloud`, `db-nextcloud`, `nextcloud-redis`, `nextcloud-cron` | ------------ | Installer la stack et vérifier la connexion, les synchronisations et les tâches cron | à tester |
| `dockhand` | ------------ | Tester l'accès, la protection Basic Auth et la gestion des conteneurs | à tester |
| `uptime-kuma` | ------------ | Tester l'accès, le compte admin automatique et les moniteurs Docker | à tester |
| `mailcow` | ------------ | ------------ | à faire |