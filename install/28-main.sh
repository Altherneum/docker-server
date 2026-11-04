# shellcheck shell=sh
# shellcheck disable=SC2034  # variables partagées entre modules
# =============================================================================
# 28-main.sh - ordre d'exécution de l'installation
#
# Le script installe Docker et le dépôt, puis sécurise l'hôte. La lecture de
# .env se fait après make init, pour utiliser les valeurs générées.
# =============================================================================

# Point d’entrée : installation puis sécurisation.
main() {
    # 1. Lire les options et vérifier la clé avant toute modification.
    detect_script_dir
    parse_args "$@"
    require_ssh_key
    need_root
    detect_os

    # 2. Préparer la machine : Docker, dépôt et .env.
    install_os_packages
    ensure_compose_plugin
    configure_docker
    wait_for_docker
    add_user_to_docker
    clone_repo
    run_init

    # 3. Charger les réglages générés dans .env.
    load_security_config
    validate_username
    validate_domain
    validate_ports
    build_ports

    # 4. Créer et sécuriser le compte admin.
    ensure_admin_user
    ensure_ssh_tools
    ensure_ssh_keys

    # 5. Configurer SSH, le pare-feu et les services de sécurité.
    configure_sshd
    configure_ufw
    configure_auto_updates
    configure_webhooks
    configure_hostname
    configure_prompt
    configure_motd
    secure_env

    # 6. Afficher le résumé et les prochaines étapes.
    show_report
}
