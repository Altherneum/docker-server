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
| `forgejo` #1 | CI/CD auto start | Lorsque les repos sont clonés, le CI CD ne se lance pas automatiquement | à tester puis OK |
| `code-server` | ------------ | ------------------------------------ | OK |
| `code-server` | Forgejo remote | Check comment ajouter Forgejo en remote git host, pour push vers (ou pull), et continuer aussi via github (les deux si possible) | à faire |
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

# deployCetteNuit

## 0. Avant de toucher au VPS
- [ ] Commit + push `docker-server`
- [ ] Push `plugin` (5 commits en attente sur `main`)
- [ ] Attendre le CI du plugin et noter la version publiée (`v.<N>`)
- [ ] Vérifier que la release GitHub `v.<N>` existe

## 1. Ancien mailcow (sur le VPS actuel, s'il existe)
- [ ] Sauvegarde si des données doivent être gardées :
      `sudo tar czf /root/mailcow-$(date +%F).tgz -C /opt mailcow-dockerized`
- [ ] `cd /opt/mailcow-dockerized && sudo docker compose down`
      (sans `-v` : les volumes restent)
- [ ] Si aucune donnée à garder : `sudo docker compose down -v`
      puis `sudo rm -rf /opt/mailcow-dockerized`
- [ ] Vérifier les restes :
      `docker ps -a | grep mailcow`
      `docker volume ls | grep mailcow`
      `docker network ls | grep mailcow`
- [ ] Chaîne iptables : `sudo iptables -S | grep MAILCOW`
      (à supprimer seulement si le nouveau mailcow n'est pas lancé)
      `sudo iptables -D FORWARD -j MAILCOW 2>/dev/null || true`
      `sudo iptables -F MAILCOW 2>/dev/null || true`
      `sudo iptables -X MAILCOW 2>/dev/null || true`

## 2. Code sur le VPS
- [ ] `cd /opt/docker-server && git pull --rebase`
- [ ] Vérifier `.env` : `DOMAIN_NAME=altherneum`, `TLD=.fr`,
      `MAIL_ENABLED=true`, `MAIL_CREATE_KEYS=no`
- [ ] Mettre `PLUGIN_VERSION` à la version publiée par le CI
- [ ] `sudo make up-service SERVICE=mc-plugins`
      (télécharge le nouveau JAR ; le conteneur s'arrête ensuite, c'est normal)
- [ ] `sudo make build` seulement si des Dockerfiles/scripts ont changé.
      Mailcow n'est pas rebuild : il utilise les images officielles.

## 3. DKIM + DNS
- [ ] `sudo make mail-dkim-key` → noter le TXT affiché
- [ ] Vérifier que `A @` pointe toujours vers l'IP actuelle
- [ ] Zone DNS :
      - `A mail` → IP du VPS (pas un CNAME)
      - `MX @` → `mail.altherneum.fr.` priorité 10
      - `TXT @` SPF → `v=spf1 mx ~all`
        (remplacer l'ancien qui contient `ip4:45.159.229.139`)
      - `TXT dkim._domainkey` → valeur générée
      - `TXT _dmarc` → conserver
      - supprimer l'ancien `default._domainkey` (corrompu, entités HTML)
- [ ] PTR : normalement déjà créé par Contabo. Vérifier
      `dig -x <IP> +short` ; sinon panneau Contabo (reverse DNS)
- [ ] Attendre la propagation, puis :
      `dig +short A mail.altherneum.fr`
      `dig +short MX altherneum.fr`
      `dig +short TXT dkim._domainkey.altherneum.fr`

## 4. Ports et pare-feu
- [ ] `sudo ufw allow 25,110,143,465,587,993,995,4190/tcp`
- [ ] Pare-feu Contabo : autoriser 25/80/443/110/143/465/587/993/995/4190
      en entrée
- [ ] **Port 25 sortant** (souvent bloqué) :
      `nc -vz gmail-smtp-in.l.google.com 25`
      Si bloqué : ticket Contabo pour le débloquer
- [ ] Depuis un autre poste : `nc -vz mail.altherneum.fr 25` et `:993`

## 5. Mailcow
- [ ] `sudo make mail-setup`
- [ ] `sudo make mail-check` → 0 erreur, timer actif
- [ ] `systemctl list-timers mail-cert-sync.timer`
- [ ] `openssl s_client -connect mail.altherneum.fr:993 -servername mail.altherneum.fr </dev/null 2>/dev/null | openssl x509 -noout -issuer -dates`
      → Let's Encrypt

## 6. Minecraft
- [ ] `for s in velocity mc-hub mc-survie mc-creatif mc-anarchie mc-rpg mc-skyblock mc-opprison mc-test; do sudo make stop SERVICE=$s; done`
- [ ] `for s in velocity mc-hub mc-survie mc-creatif mc-anarchie mc-rpg mc-skyblock mc-opprison mc-test; do sudo make up-service SERVICE=$s; done`

## 7. Vérifications finales
- [ ] Envoyer un mail depuis `contact@` vers une adresse perso :
      SPF/DKIM/DMARC = PASS
- [ ] Recevoir un mail depuis l'extérieur vers `contact@`
- [ ] Tester sur mail-tester.com
- [ ] Mettre la ligne `mailcow` de la table à `OK`
