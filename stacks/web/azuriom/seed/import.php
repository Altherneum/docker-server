#!/usr/bin/env php
<?php
/**
 * Importe les données de démonstration Azuriom.
 *
 * Les fichiers SQL proviennent de l'ancien dépôt « server » et contiennent
 * l'ensemble des paramètres, rôles, liens, images et catégories/packages de la
 * boutique. Ils ne contiennent que des données : le schéma appartient aux
 * migrations Azuriom et du plugin Shop. Ils sont rejouables sans perte de
 * données grâce aux upserts.
 *
 * Usage : php import.php [dossier_sql]
 */

declare(strict_types=1);

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function fail(string $message): void
{
    fwrite(STDERR, "Erreur : {$message}\n");
    exit(1);
}

function envValue(string $name): ?string
{
    $value = getenv($name);

    return $value === false ? null : $value;
}

function appKey(): string
{
    $appKey = null;
    $configFile = (envValue('AZURIOM_CONFIG_DIR') ?: '/var/www/config').'/.env';

    if (is_file($configFile)) {
        foreach (file($configFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
            if (str_starts_with($line, 'APP_KEY=')) {
                $appKey = trim(substr($line, 8), " \t\n\r\0\x0B\"'");
                break;
            }
        }
    }

    $appKey ??= trim(envValue('APP_KEY') ?? '', " \t\n\r\0\x0B\"'");

    if ($appKey === '') {
        fail('APP_KEY introuvable pour chiffrer le mot de passe RCON.');
    }

    return $appKey;
}

function encryptedRconPassword(): string
{
    static $encrypted = null;

    if ($encrypted !== null) {
        return $encrypted;
    }

    $password = envValue('MINECRAFT_RCON_PASSWORD');

    if ($password === null || $password === '') {
        fail('MINECRAFT_RCON_PASSWORD est requis pour configurer les serveurs RCON.');
    }

    $webroot = envValue('AZURIOM_WEBROOT') ?: '/var/www/html';
    $autoload = $webroot.'/vendor/autoload.php';

    if (! is_file($autoload)) {
        fail("autoload introuvable : {$autoload}");
    }

    require_once $autoload;

    $key = appKey();
    $key = str_starts_with($key, 'base64:')
        ? base64_decode(substr($key, 7), true)
        : $key;

    if ($key === false || strlen($key) !== 32) {
        fail('APP_KEY invalide : une clé de 32 octets est requise.');
    }

    $encrypter = new Illuminate\Encryption\Encrypter($key, 'AES-256-CBC');
    $encrypted = $encrypter->encrypt($password, false);

    return $encrypted;
}

function rconPort(): string
{
    $port = envValue('MINECRAFT_RCON_PORT');

    if ($port === null || $port === '') {
        $port = '25575';
    }

    if (! ctype_digit($port)) {
        fail('MINECRAFT_RCON_PORT doit être un nombre entier.');
    }

    $number = (int) $port;

    if ($number < 1 || $number > 65535) {
        fail('MINECRAFT_RCON_PORT doit être compris entre 1 et 65535.');
    }

    return (string) $number;
}

function replaceSeedPlaceholders(string $sql, mysqli $db): string
{
    if (! str_contains($sql, '{{rcon-')) {
        return $sql;
    }

    $replacements = [
        '{{rcon-port}}' => rconPort(),
    ];

    if (str_contains($sql, '{{rcon-password}}')) {
        $replacements['{{rcon-password}}'] = $db->real_escape_string(encryptedRconPassword());
    }

    return strtr($sql, $replacements);
}

/**
 * Ordre d'import : les dépendances passent avant les tables qui les utilisent
 * (rôles avant permissions et utilisateurs, catégories avant packages).
 */
const IMPORT_ORDER = [
    'settings.sql',
    'roles.sql',
    'permissions.sql',
    'social_links.sql',
    'navbar_elements.sql',
    'images.sql',
    'servers.sql',
    'shop_categories.sql',
    'shop_packages.sql',
    'users.sql',
];

$databaseDir = $argv[1] ?? __DIR__ . '/database';

$host = envValue('DB_HOST') ?: 'db-azuriom';
$port = (int) (envValue('DB_PORT') ?: 3306);
$name = envValue('DB_DATABASE');
$user = envValue('DB_USERNAME');
$password = envValue('DB_PASSWORD');

if ($name === null || $name === '' || $user === null) {
    fail('DB_DATABASE et DB_USERNAME doivent être définis.');
}

try {
    $db = new mysqli($host, $user, $password ?? '', $name, $port);
    $db->set_charset('utf8mb4');
} catch (mysqli_sql_exception $e) {
    fail('connexion à la base impossible : ' . $e->getMessage());
}

function tableExists(mysqli $db, string $table): bool
{
    $stmt = $db->prepare(
        'SELECT 1 FROM information_schema.tables
         WHERE table_schema = DATABASE() AND table_name = ?'
    );
    $stmt->bind_param('s', $table);
    $stmt->execute();
    $stmt->store_result();
    $exists = $stmt->num_rows > 0;
    $stmt->close();

    return $exists;
}

function settingValue(mysqli $db, string $name): ?string
{
    $stmt = $db->prepare('SELECT value FROM settings WHERE name = ? LIMIT 1');
    $stmt->bind_param('s', $name);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    $stmt->close();

    return $row === null ? null : (string) $row['value'];
}

function upsertSetting(mysqli $db, string $name, string $value): void
{
    $stmt = $db->prepare(
        'INSERT INTO settings (name, value) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE value = ?'
    );
    $stmt->bind_param('sss', $name, $value, $value);
    $stmt->execute();
    $stmt->close();
}

$shopInstalled = tableExists($db, 'shop_categories')
    && tableExists($db, 'shop_packages');

$files = [];

foreach (IMPORT_ORDER as $file) {
    $path = $databaseDir . '/' . $file;

    if (! is_file($path)) {
        fail("fichier SQL introuvable : {$path}");
    }

    if (! $shopInstalled && str_starts_with($file, 'shop_')) {
        fwrite(STDERR, "→ {$file} ignoré (plugin Shop non installé)\n");
        continue;
    }

    $files[] = $path;
}

foreach ($files as $path) {
    $file = basename($path);
    $sql = file_get_contents($path);

    if ($sql === false) {
        fail("lecture impossible : {$path}");
    }

    $sql = replaceSeedPlaceholders($sql, $db);

    try {
        $db->multi_query($sql);

        do {
            if ($result = $db->store_result()) {
                $result->free();
            }
        } while ($db->more_results() && $db->next_result());
    } catch (mysqli_sql_exception $e) {
        fail("{$file} : " . $e->getMessage());
    }

    echo "  ✓ {$file}\n";
}
//remplace les valeurs en utilisant le .env
$overrides = [
    'url' => envValue('APP_URL'),
    'mail.from.address' => envValue('MAIL_FROM_ADDRESS'),
    'mail.mailer' => envValue('MAIL_MAILER'),
    'mail.smtp.host' => envValue('MAIL_HOST'),
    'mail.smtp.port' => envValue('MAIL_PORT'),
    'mail.smtp.username' => envValue('MAIL_USERNAME'),
    'mail.smtp.password' => envValue('MAIL_PASSWORD'),
];

$encryption = strtolower(envValue('MAIL_ENCRYPTION') ?? '');
if ($encryption === 'ssl') {
    $overrides['mail.smtp.scheme'] = 'smtps';
} elseif ($encryption !== '') {
    $overrides['mail.smtp.scheme'] = 'smtp';
}

foreach ($overrides as $key => $value) {
    if ($value !== null && $value !== '') {
        upsertSetting($db, $key, $value);
    }
}

/*
 * Si le thème Prism n'a pas pu être copié, on retire le réglage pour éviter
 * qu'Azuriom cherche des vues et des assets inexistants.
 */
$theme = settingValue($db, 'theme');
$webroot = envValue('AZURIOM_WEBROOT') ?: '/var/www/html';

if ($theme !== null && $theme !== '' && ! is_dir($webroot . '/resources/themes/' . $theme)) {
    fwrite(STDERR, "Attention : thème « {$theme} » absent, réglage theme retiré.\n");
    $stmt = $db->prepare("DELETE FROM settings WHERE name = 'theme'");
    $stmt->execute();
    $stmt->close();
}

$db->close();
