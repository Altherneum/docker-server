# Bot Discord

**Rôle :** bot du serveur Discord.

**Conteneur :** `discord-bot`  
**Adresse :** aucune. Le bot se connecte à Discord ; il n'ouvre pas de site web.

## Token et mot de passe

| Variable `.env` | Obligatoire | Rôle |
|---|---|---|
| `DISCORD_BOT_TOKEN` | Oui | Token du bot, à récupérer sur le portail Discord |
| `DISCORD_BOT_NAME` | Non | Nom affiché par le bot |
| `BOT_URL` | Non | URL du jar téléchargé au build (release GitHub, miroir, URL HTTP accessible au build) |

Le token n'est **pas** généré par `make init` : il faut le créer à la main sur
<https://discord.com/developers/applications>.

Si le token est vide ou vaut `CHANGE_ME`, le conteneur s'arrête avec une erreur.

## Source du bot

`BOT_URL` est transmis au `Dockerfile` comme argument de build. Valeur par
défaut :

```text
https://github.com/lx78WyY0J5/bot-rewrite/releases/latest/download/bot-rewrite-1.0-fat.jar
```

Pour changer de source, modifiez `BOT_URL` dans `.env`, puis reconstruisez :

```sh
sudo make rebuild-service SERVICE=bot
```

Le build sans cache est nécessaire car Docker ne détecte pas les changements de
contenu derrière une URL inchangée.

## Démarrer / arrêter

```sh
sudo make up-service SERVICE=bot
sudo make ps-service SERVICE=bot
sudo make logs-service SERVICE=bot
sudo make stop SERVICE=bot
```

## Ressources

Le conteneur démarre avec un heap Java de `64M` à `256M`
(`-Xms64M -Xmx256M`). C'est suffisant pour JDA, le cache des membres et le cache
des 10 000 derniers messages. Le pic observé reste autour de 150 Mio de RSS.

## Nettoyer

```sh
sudo CONFIRM=yes make clean-service SERVICE=bot
```

Cela supprime les volumes `discord-data` et
`discord-config`. Les données du bot sont perdues.

## Inviter le bot

1. Créez une application sur le portail Discord.
2. Ajoutez un bot et copiez son token dans `DISCORD_BOT_TOKEN`.
3. Générez une URL d'invitation avec les permissions nécessaires.
4. Invitez le bot sur votre serveur.
5. Démarrez le service.

## Sécurité

- Le token donne le contrôle du bot. Ne le montrez jamais et ne le commitez pas.
- S'il est divulgué, régénérez-le sur le portail Discord et mettez à jour
  `.env`.
- Le token est écrit dans `/DiscordBot/data/tokens.yml` dans le conteneur, avec
  des permissions restreintes.

## Sauvegarde

`make backup` archive `discord-data`. Le token reste dans `.env`,
à sauvegarder séparément.

## Dépannage

```sh
sudo make logs-service SERVICE=bot
```

- **`DISCORD_BOT_TOKEN manquant`** : la variable est absente de `.env`.
- **`renseigner DISCORD_BOT_TOKEN`** : la valeur est encore `CHANGE_ME`.
- **Le bot est en ligne mais ne répond pas** : vérifiez les permissions et
  l'activation des intents sur le portail Discord.
