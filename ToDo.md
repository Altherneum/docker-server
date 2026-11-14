# ToDo list
## Liste
| Services | Sous-Section | Description | Validation |
|---|---|---|---|
| `traefik` | ------------ | ------------------------------------ | OK |
| `php-site` | ------------ | ------------------------------------ | OK |
| `php-site` #1 | Vérifie le /api/deploy | Vérifier si le git pull marche bien lors d'un /api/deploy | à re valider |
| `php-site` #2 | doc.altherneum.fr | Supprimer l'ancien altherneum.github.io, et récupérer le DNS `doc` pour le relier sur php-site | à faire |
| `azuriom` | ------------ | ------------------------------------ | OK |
| `azuriom` #1 | Dedipass | Vérifier la boutique, si les commandes sont bien envoyés, ainsi que les clés privés de payement "dédipass" etc | à faire |
| `azuriom` #2 | Images & GIF dynamique | Dans le futur, ajouter les images à la racine, et indiquer à l'utilisateur de les remplacer au besoin (car avec le logo Altherneum, et le projet doit pouvoir changer de nom/identité facilement), images dans un dossier ".env", les copiers de ce .env vers le bon endroit (azuriom, logo minecraft server.png, etc) | à faire |
| `keeweb` | ------------ | ------------------------------------ | OK |
| `keeweb` #1 | Test WebDav | Le WebDav est censé être vide, et n'a jamais été testé, ajouetr une clé et tester | à faire |
| `phpmyadmin` | ------------ | ------------------------------------ | OK |
| `meme` | ------------ | ------------------------------------ | à faire |
| `meme` #1 | Dynamic variable .env | Cacher les termes "Altherneum" dans le code source, utiliser une variable, et l'ajouter au .env, puis faire un script qui remplace la variable lors de l'installation de ce site | à faire |
| `forgejo` | ------------ | ------------------------------------ | OK |
| `forgejo` #1 | CI/CD auto start | Lorsque les repos sont clonés, le CI CD ne se lance pas automatiquement | à faire |
| `code-server` | ------------ | ------------------------------------ | OK |
| `velocity`, `mc-*` | ------------ | ------------------------------------ | OK |
| `Plugin` | ------------ | ------------------------------------ | OK |
| `Plugin` #1 | Logo resource pack | Je crois qu'un logo manque / est cassé : Logo du shop vanilla (diamond), alors qu'il devrait (de mémoire) être un billet doré | à faire |
| `Plugin` #2 | ID resource pack | La console indique que l'ID (ou le hash je sais plus) manque dans la config | à faire |
| `bot` | ------------ | ------------------------------------ | à faire |
| `bot` #1 | Server cloner | Copier le code de l'ancien bot qui permet de cloner un serveur et l'ajouter dans le nouveau bot rewrite JDA | à faire |
| `fail2ban` | ------------ | ------------------------------------ | OK |
| `nextcloud` | ------------ | ------------------------------------ | Polish / test |
| `nextcloud` #1 | ------------ | Vérifier la connexion, les synchronisations depuis l'appli et aussi la version Android | à tester |
| `dockhand` | ------------ | ------------------------------------ | Polish |
| `dockhand` #1 | ------------ | Ajouter un compte admin par défaut pour rajouter une sécurité en plus (car insecure) | à faire |
| `uptime-kuma` | ------------ | ------------------------------------ | OK |
| `mailcow` | ------------ | ------------------------------------ | à faire |
| `mailcow` #1 | SPF & DKIM auto gen | Faire en sorte que les clées DKIM, SPF, etc soit check via dig, et si non existantes / mal configurés, créer via un script la clée et demander à l'admin d'ajouter ce qu'il faut sur le DNS pour correspondre | à faire |