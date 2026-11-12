# Dossier `images`

Images Docker de base construites localement. Elles sont utilisées par les
stacks et n'ont ni URL ni mot de passe.

| Dossier | Image | Utilisée par |
|---|---|---|
| `php-apache` | `php-apache:latest` | Site PHP, Azuriom |
| `mariadb` | `mariadb:11.8` | `db-php`, `db-azuriom`, `db-nextcloud` |
| `postgres` | `postgres:18` | `db-forgejo` |

```sh
sudo make base          # construire toutes les images de base
sudo make ensure-base   # construire seulement celles qui manquent
```

Fiche complète : [Images de base](../docs/services/base-images.md).
