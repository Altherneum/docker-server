SHELL := /bin/sh
COMPOSE := docker compose
MAILCOW_DIR := $(or $(shell sed -n 's/^MAILCOW_DIR=//p' .env 2>/dev/null | tail -n1),/opt/mailcow-dockerized)
SERVICE ?=
FORGEJO_MIRROR_ARGS ?=

.PHONY: help init check-env ensure-networks build base php-base mariadb-base postgres-base paper-base ensure-base up down restart ps logs config backup restore \
        php-site-src php-site-env \
        forgejo-admin forgejo-runner forgejo-mirror mail-integrate mail-up mail-down mail-logs clean clean-service down-clean down-clean-service \
        stop restart-service logs-service up-service rebuild-service down-service \
        ps-service services azuriom-seed

help: ## Affiche cette aide
	@awk 'BEGIN {FS = ":.*##"; printf "\nCommandes disponibles :\n\n"} /^[a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n"

init: ## Génère .env, les mots de passe, les htpasswd et les réseaux Docker
	./scripts/init.sh

check-env: ## Vérifie que .env contient les secrets nécessaires avant make up
	./scripts/check-env.sh

ensure-networks: ## Crée les réseaux Docker externes manquants
	./scripts/ensure-networks.sh

build: base ## Construit les images de base puis celles des stacks
	$(COMPOSE) build

php-site-src: ## Clone le dépôt website dans stacks/web/php-site/src
	./scripts/php-site-src.sh

php-site-env: ## Régénère stacks/web/php-site/src/.env depuis .env
	PHP_SITE_ENV_OVERWRITE=true ./scripts/php-site-src.sh

php-base: ## Construit uniquement l'image de base PHP/Apache
	docker build --pull --no-cache -t php-apache:latest images/php-apache

mariadb-base: ## Construit uniquement l'image de base MariaDB
	docker build -t mariadb:11.8 images/mariadb

postgres-base: ## Construit uniquement l'image de base PostgreSQL
	docker build -t postgres:18 images/postgres

paper-base: ## Construit l'image commune des serveurs Paper
	docker build -t paper:1.21.11 stacks/minecraft/paper

base: php-base mariadb-base postgres-base paper-base ## Construit toutes les images de base

ensure-base: ## Construit les images de base manquantes
	@docker image inspect php-apache:latest >/dev/null 2>&1 || $(MAKE) php-base
	@docker image inspect mariadb:11.8 >/dev/null 2>&1 || $(MAKE) mariadb-base
	@docker image inspect postgres:18 >/dev/null 2>&1 || $(MAKE) postgres-base
	@docker image inspect paper:1.21.11 >/dev/null 2>&1 || $(MAKE) paper-base

up: check-env ensure-networks ensure-base php-site-src ## Démarre toute l'infrastructure
	$(COMPOSE) up -d --remove-orphans
	@./scripts/forgejo-admin.sh
	@./scripts/forgejo-runner.sh \
		|| echo "Attention : runner Forgejo Actions indisponible (voir les messages ci-dessus)."
	@./scripts/forgejo-github-mirror.sh \
		|| echo "Attention : import GitHub dans Forgejo incomplet (voir les messages ci-dessus)."

down: ## Arrête toute l'infrastructure sans supprimer les conteneurs (volumes conservés)
	$(COMPOSE) stop

restart: ## Redémarre toute l'infrastructure
	$(COMPOSE) restart

ps: ## Liste l'état des conteneurs
	$(COMPOSE) ps

logs: ## Suit les logs de tous les conteneurs
	$(COMPOSE) logs -f --tail=200

config: ## Valide et affiche la configuration Compose fusionnée
	$(COMPOSE) config

backup: ## Sauvegarde les bases et les volumes applicatifs
	./scripts/backup.sh

restore: ## Restaure une sauvegarde : make restore BACKUP=backups/AAAA...
	@test -n "$(BACKUP)" || (echo "Usage : make restore BACKUP=backups/AAAA-MM-JJ_HHMMSS"; exit 1)
	CONFIRM=yes ./scripts/restore.sh "$(BACKUP)"

forgejo-admin: ## Crée le compte admin Forgejo depuis .env (idempotent)
	./scripts/forgejo-admin.sh

forgejo-runner: ## Vérifie que le runner Forgejo Actions est enregistré et en ligne
	./scripts/forgejo-runner.sh

forgejo-mirror: ## Importe les dépôts GitHub dans Forgejo et configure le miroir push
	./scripts/forgejo-github-mirror.sh $(FORGEJO_MIRROR_ARGS)

azuriom-seed: ## Réapplique les données de démonstration Azuriom (paramètres, rôles, boutique)
	@printf "Cette commande réapplique les données de démonstration Azuriom. Confirmer avec CONFIRM=yes\n"
	@test "$${CONFIRM:-no}" = "yes"
	@docker ps --filter name=^/azuriom$$ --format '{{.Names}}' | grep -qx azuriom \
		|| (echo "Le conteneur azuriom n'est pas démarré."; exit 1)
	docker exec azuriom /usr/local/bin/azuriom-seed

mail-integrate: ## Installe l'override Traefik dans MAILCOW_DIR
	./scripts/mail-integrate.sh

mail-up: ## Démarre mailcow avec l'intégration Traefik
	cd "$(MAILCOW_DIR)" && docker compose -f docker-compose.yml -f docker-compose.override.yml up -d

mail-down: ## Arrête mailcow
	cd "$(MAILCOW_DIR)" && docker compose down

mail-logs: ## Suit les logs de mailcow
	cd "$(MAILCOW_DIR)" && docker compose logs -f --tail=200

clean: ## Supprime tous les conteneurs ET les volumes (DESTRUCTIF)
	@printf "Cette commande supprime toutes les données Docker. Confirmer avec CONFIRM=yes\n"
	@test "$${CONFIRM:-no}" = "yes"
	$(COMPOSE) down -v --remove-orphans

clean-service: ## Supprime un service, ses conteneurs et ses volumes exclusifs (DESTRUCTIF)
	@test -n "$(SERVICE)" || (echo "Usage: make clean-service SERVICE=nom"; exit 1)
	@test "$$(echo $(SERVICE) | wc -w)" -eq 1 || (echo "Erreur: clean-service ne cible qu'un seul service"; exit 1)
	@printf "Cette commande supprime le service $(SERVICE) et ses volumes. Confirmer avec CONFIRM=yes\n"
	@test "$${CONFIRM:-no}" = "yes"
	./scripts/clean-service.sh $(SERVICE)

down-clean: ## Arrête puis supprime tous les conteneurs ET volumes (DESTRUCTIF)
	@printf "Cette commande supprime toutes les données Docker. Confirmer avec CONFIRM=yes\n"
	@test "$${CONFIRM:-no}" = "yes"
	$(COMPOSE) stop
	$(COMPOSE) down -v --remove-orphans

down-clean-service: ## Arrête puis supprime un service et ses volumes exclusifs (DESTRUCTIF)
	@test -n "$(SERVICE)" || (echo "Usage: make down-clean-service SERVICE=nom"; exit 1)
	@test "$$(echo $(SERVICE) | wc -w)" -eq 1 || (echo "Erreur: down-clean-service ne cible qu'un seul service"; exit 1)
	@printf "Cette commande supprime le service $(SERVICE) et ses volumes. Confirmer avec CONFIRM=yes\n"
	@test "$${CONFIRM:-no}" = "yes"
	$(COMPOSE) --env-file .env stop $(SERVICE)
	./scripts/clean-service.sh $(SERVICE)

# --- Opérations sur un service unique ---
stop: ## Arrête un service (ex: make stop SERVICE=azuriom)
	@test -n "$(SERVICE)" || (echo "Usage: make stop SERVICE=nom"; exit 1)
	$(COMPOSE) --env-file .env stop $(SERVICE)

restart-service: ## Redémarre un service (ex: make restart-service SERVICE=azuriom)
	@test -n "$(SERVICE)" || (echo "Usage: make restart-service SERVICE=nom"; exit 1)
	$(COMPOSE) --env-file .env restart $(SERVICE)

logs-service: ## Suit les logs d'un service (ex: make logs-service SERVICE=azuriom)
	@test -n "$(SERVICE)" || (echo "Usage: make logs-service SERVICE=nom"; exit 1)
	$(COMPOSE) --env-file .env logs -f --tail=200 $(SERVICE)

up-service: ## Démarre un service (ex: make up-service SERVICE=azuriom)
	@test -n "$(SERVICE)" || (echo "Usage: make up-service SERVICE=nom"; exit 1)
	@./scripts/ensure-networks.sh
	@if [ -n "$(filter $(SERVICE),php-site)" ]; then \
		$(MAKE) php-site-src ; \
	fi
	@if [ -n "$(filter $(SERVICE),php-site azuriom)" ]; then \
		docker image inspect php-apache:latest >/dev/null 2>&1 \
			|| $(MAKE) php-base ; \
	fi
	@if [ -n "$(filter $(SERVICE),php-site azuriom nextcloud nextcloud-cron db-php db-azuriom db-nextcloud)" ]; then \
		docker image inspect mariadb:11.8 >/dev/null 2>&1 \
			|| $(MAKE) mariadb-base ; \
	fi
	@if [ -n "$(filter $(SERVICE),forgejo forgejo-runner db-forgejo)" ]; then \
		docker image inspect postgres:18 >/dev/null 2>&1 \
			|| $(MAKE) postgres-base ; \
	fi
	@if [ -n "$(filter $(SERVICE),mc-hub mc-survie mc-creatif mc-anarchie mc-rpg mc-skyblock mc-opprison mc-test)" ]; then \
		docker image inspect paper:1.21.11 >/dev/null 2>&1 \
			|| $(MAKE) paper-base ; \
	fi
	@if [ "$(SERVICE)" = "forgejo" ]; then \
		$(COMPOSE) --env-file .env up -d --build forgejo forgejo-runner ; \
	elif [ "$(SERVICE)" = "forgejo-runner" ]; then \
		$(COMPOSE) --env-file .env up -d --build forgejo-runner ; \
	elif [ "$(SERVICE)" = "nextcloud" ]; then \
		$(COMPOSE) --env-file .env up -d --build nextcloud nextcloud-cron ; \
	else \
		$(COMPOSE) --env-file .env up -d --build $(SERVICE) ; \
	fi
	@if [ "$(SERVICE)" = "forgejo" ]; then \
		./scripts/forgejo-admin.sh ; \
		./scripts/forgejo-runner.sh \
			|| echo "Attention : runner Forgejo Actions indisponible (voir les messages ci-dessus)." ; \
		./scripts/forgejo-github-mirror.sh \
			|| echo "Attention : import GitHub dans Forgejo incomplet (voir les messages ci-dessus)." ; \
	elif [ "$(SERVICE)" = "forgejo-runner" ]; then \
		./scripts/forgejo-admin.sh ; \
		./scripts/forgejo-runner.sh \
			|| echo "Attention : runner Forgejo Actions indisponible (voir les messages ci-dessus)." ; \
	fi

rebuild-service: ## Reconstruit sans cache puis recrée un service (ex: make rebuild-service SERVICE=bot)
	@test -n "$(SERVICE)" || (echo "Usage: make rebuild-service SERVICE=nom"; exit 1)
	@./scripts/ensure-networks.sh
	$(COMPOSE) --env-file .env build --no-cache --pull $(SERVICE)
	$(COMPOSE) --env-file .env up -d --force-recreate --no-deps $(SERVICE)

down-service: ## Arrête un service sans supprimer son conteneur (ex: make down-service SERVICE=azuriom)
	@test -n "$(SERVICE)" || (echo "Usage: make down-service SERVICE=nom"; exit 1)
	$(COMPOSE) --env-file .env stop $(SERVICE)

ps-service: ## État d'un service (ex: make ps-service SERVICE=azuriom)
	@test -n "$(SERVICE)" || (echo "Usage: make ps-service SERVICE=nom"; exit 1)
	$(COMPOSE) --env-file .env ps $(SERVICE)

# Lister les services disponibles
services: ## Liste tous les noms de services
	$(COMPOSE) --env-file .env config --services
