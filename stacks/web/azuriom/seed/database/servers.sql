SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";

-- Serveurs Paper du stack, joignables par leur nom de conteneur sur le réseau
-- Docker `minecraft`. Le port 25565 sert au ping Minecraft et le port RCON est
-- fourni par MINECRAFT_RCON_PORT dans .env (25575 par défaut), en interne au
-- réseau Docker. Le mot de passe RCON est chiffré avec l'APP_KEY de l'instance
-- au moment de l'import : il ne peut pas être stocké en clair dans ce fichier.
-- Le serveur 1 (Hub) est la cible des commandes de la boutique configurées
-- avec "server":"1".
INSERT INTO `servers` (`id`, `name`, `address`, `port`, `type`, `token`, `join_url`, `data`, `home_display`, `created_at`, `updated_at`) VALUES
(1, 'Hub', 'mc-hub', 25565, 'mc-rcon', NULL, NULL, '{"rcon-port":{{rcon-port}},"rcon-password":"{{rcon-password}}"}', 0, NOW(), NOW()),
(2, 'Survie', 'mc-survie', 25565, 'mc-rcon', NULL, NULL, '{"rcon-port":{{rcon-port}},"rcon-password":"{{rcon-password}}"}', 0, NOW(), NOW()),
(3, 'Créatif', 'mc-creatif', 25565, 'mc-rcon', NULL, NULL, '{"rcon-port":{{rcon-port}},"rcon-password":"{{rcon-password}}"}', 0, NOW(), NOW()),
(4, 'Anarchie', 'mc-anarchie', 25565, 'mc-rcon', NULL, NULL, '{"rcon-port":{{rcon-port}},"rcon-password":"{{rcon-password}}"}', 0, NOW(), NOW()),
(5, 'RPG', 'mc-rpg', 25565, 'mc-rcon', NULL, NULL, '{"rcon-port":{{rcon-port}},"rcon-password":"{{rcon-password}}"}', 0, NOW(), NOW()),
(6, 'SkyBlock', 'mc-skyblock', 25565, 'mc-rcon', NULL, NULL, '{"rcon-port":{{rcon-port}},"rcon-password":"{{rcon-password}}"}', 0, NOW(), NOW()),
(7, 'OP-Prison', 'mc-opprison', 25565, 'mc-rcon', NULL, NULL, '{"rcon-port":{{rcon-port}},"rcon-password":"{{rcon-password}}"}', 0, NOW(), NOW()),
(8, 'Test', 'mc-test', 25565, 'mc-rcon', NULL, NULL, '{"rcon-port":{{rcon-port}},"rcon-password":"{{rcon-password}}"}', 0, NOW(), NOW())
ON DUPLICATE KEY UPDATE
    `name` = VALUES(`name`),
    `address` = VALUES(`address`),
    `port` = VALUES(`port`),
    `type` = VALUES(`type`),
    `token` = VALUES(`token`),
    `join_url` = VALUES(`join_url`),
    `data` = VALUES(`data`),
    `home_display` = VALUES(`home_display`),
    `updated_at` = VALUES(`updated_at`);
