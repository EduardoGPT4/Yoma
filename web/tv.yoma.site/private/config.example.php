<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}
return [
  'host' => 'mysql.example.com',
  'port' => 3306,
  'database' => 'anime_database',
  'username' => 'anime_user',
  'password' => 'replace-with-your-password',
  // Enable only on hosting that permits scheduled external requests.
  // InfinityFree free hosting: leave false and use administrator visits.
  'external_maintenance' => false,
  // Enable only after verifying that external calendar apps can read .ics without cookies.
  // InfinityFree free hosting requires a browser challenge: keep subscriptions disabled.
  'calendar_subscriptions' => false,
  // Fill only on the server in private/config.local.php. Never package real keys.
  'mal' => [
    'client_id' => '',
    'client_secret' => '',
    'redirect_uri' => 'https://tv.yoma.site/mal-callback.php',
    'encryption_key' => '', // Base64 of 32 random bytes; preserve it across deployments.
  ],
];
