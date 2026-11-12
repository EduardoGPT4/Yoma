<?php
declare(strict_types=1);

// Public installation metadata: no session, database or account configuration.
$manifest = json_decode((string) file_get_contents(__DIR__ . '/manifest.webmanifest'), true, 32, JSON_THROW_ON_ERROR);
$base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/app-manifest.php')), '/') . '/';
$assets = $base . (defined('SEASON_RELEASE_ID') ? 'releases/' . SEASON_RELEASE_ID . '/' : '');
$manifest['id'] = $base;
$manifest['scope'] = $base;
$manifest['start_url'] = $base . '#discover';
foreach ($manifest['icons'] as &$icon) {
    $icon['src'] = $assets . $icon['src'];
}
unset($icon);
header('Content-Type: application/manifest+json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: public, max-age=0, must-revalidate');
echo json_encode($manifest, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
