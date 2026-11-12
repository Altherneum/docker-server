# shellcheck shell=sh
# =============================================================================
# 27-report.sh - rapport final et prochaines étapes
# =============================================================================

# Affiche le résumé final et les prochaines étapes.
show_report() {
    section "Installation terminée"

    authorized="$(admin_home)/.ssh/authorized_keys"

    echo "  Dépôt           : $SERVER_DIR"
    echo "  Compte admin    : $ADMIN_USER"
    echo "  Port SSH        : $SSH_PORT"
    echo "  Clés autorisées : $(count_keys "$authorized")"
    echo "  Sauvegardes     : $BACKUP_DIR"

    if [ -n "$ADMIN_INITIAL_PASSWORD" ]; then
        echo
        echo "  Mot de passe initial de $ADMIN_USER : $ADMIN_INITIAL_PASSWORD"
        echo "  Changez-le avec : sudo passwd $ADMIN_USER"
    elif [ -n "$ADMIN_PASSWORD" ] && [ "$ADMIN_PASSWORD" != "CHANGE_ME" ]; then
        echo
        echo "  Mot de passe de $ADMIN_USER : défini dans .env"
        echo "  Variable : HARDEN_ADMIN_PASSWORD"
    fi

    cat <<EOF

  TESTEZ LA CONNEXION DANS UN AUTRE TERMINAL :
    ssh -p $SSH_PORT $ADMIN_USER@<ip-du-serveur>
  Puis, pour passer root : su -

  Vérifications utiles :
    sudo ufw status verbose
    sudo sshd -T | grep -Ei 'passwordauthentication|permitrootlogin|port'
    sudo ss -lntp | grep ":$SSH_PORT"
    sudo systemctl status ssh
    docker exec fail2ban fail2ban-client status sshd   # après make up

  Les services ne sont PAS encore démarrés.

  Prochaines étapes :
  1. Renseigner les secrets dans .env :
       cd $SERVER_DIR
       \$EDITOR .env
     Variables obligatoires : DISCORD_BOT_TOKEN, MINECRAFT_DISCORD_TOKEN_*,
     AZURIOM_ADMIN_GAME_ID.
     Si mailcow est utilisé, créer les boîtes noreply@, git@ et cloud@.

  2. Vérifier la configuration :
       make check-env

  3. Construire les images (10-20 min) :
       make build

  4. Démarrer :
       make up

  5. Vérifier :
       make ps

  Documentation : $SERVER_DIR/docs/README.md
  Index des services : $SERVER_DIR/docs/services/README.md
EOF
}
