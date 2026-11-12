<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}
require __DIR__ . '/db.php';
require __DIR__ . '/scraper.php';
require_once __DIR__.'/runtime.php';
date_default_timezone_set('America/Mexico_City');
ini_set('display_errors', '0');
session_name('SEASONAV1_WEB');
$cookiePath = str_replace(
  '\\',
  '/',
  dirname($_SERVER['SCRIPT_NAME'] ?? '/index.php'),
);
session_set_cookie_params([
  'httponly' => true,
  'samesite' => 'Lax',
  'secure' => !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
  'path' => rtrim($cookiePath, '/') . '/',
]);
session_start();
if (empty($_SESSION['csrf'])) {
  $_SESSION['csrf'] = bin2hex(random_bytes(24));
}
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
function player_preview_url(): ?string
{
  $url = (string) getenv('SEASON_WEB_PLAYER_TEST_URL');
  return getenv('SEASON_WEB_SQLITE') &&
    preg_match(
      '~^http://127\.0\.0\.1:[0-9]{4,5}/__qa_player/frame\.html$~D',
      $url,
    )
    ? $url
    : null;
}
$previewPlayerOrigin = player_preview_url()
  ? ' http://127.0.0.1:' . parse_url(player_preview_url(), PHP_URL_PORT)
  : '';
$bridgePort = 47653;
if (getenv('SEASON_WEB_SQLITE')) {
  $previewPort = filter_var(
    getenv('SEASON_WEB_BRIDGE_PORT'),
    FILTER_VALIDATE_INT,
    ['options' => ['min_range' => 1024, 'max_range' => 65535]],
  );
  if ($previewPort) {
    $bridgePort = $previewPort;
  }
}
header(
  "Content-Security-Policy: default-src 'self'; script-src 'self' https://www.youtube.com https://s.ytimg.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://cdn.animeav1.com https://cdn.myanimelist.net https://i.ytimg.com; connect-src 'self' https://api.github.com http://127.0.0.1:$bridgePort; frame-src https://www.youtube-nocookie.com https://www.youtube.com https://www.mp4upload.com https://mp4upload.com https://voe.sx$previewPlayerOrigin; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
);
header('Referrer-Policy: strict-origin-when-cross-origin');

final class WebError extends RuntimeException
{
  public function __construct(string $message, public int $status = 422)
  {
    parent::__construct($message);
  }
}
function uid(): int
{
  return (int) ($_SESSION['user_id'] ?? 0);
}
function member(): int
{
  if (!uid()) {
    throw new WebError('Inicia sesión para guardar tu biblioteca.', 401);
  }
  return uid();
}
function log_event(
  PDO $db,
  int $user,
  string $message,
  string $level = 'info',
): int {
  sql(
    $db,
    'INSERT INTO sa1_history (user_id,level,message,created_at) VALUES (?,?,?,?)',
    [$user, $level, $message, time()],
  );
  return (int) $db->lastInsertId();
}
function rate(PDO $db, string $key, int $max, int $seconds): void
{
  if(!consume_limit($db,$key,$max,$seconds))throw new WebError('Espera un momento antes de volver a intentarlo.',429);
}
