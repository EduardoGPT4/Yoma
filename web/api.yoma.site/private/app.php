<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}
/*
 * api.yoma.site: servicios compartidos de Yoma (puente de MyAnimeList y
 * sincronización), separados del hosting web de YomaTV.
 *
 * Usa la misma base de datos y la misma configuración de MAL que tv.yoma.site:
 * private/config.local.php se copia a mano desde tv.yoma.site y nunca está en
 * el repositorio. No hay sesiones web: la app se acredita con su device_token.
 * La autorización en el navegador (yomashi-connect.php y mal-callback.php)
 * sigue en tv.yoma.site, que es la dirección de retorno registrada en MAL.
 */
date_default_timezone_set('America/Mexico_City');
ini_set('display_errors', '0');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');

final class WebError extends RuntimeException
{
  public function __construct(string $message, public int $status = 422)
  {
    parent::__construct($message);
  }
}

/** Base de datos compartida con tv.yoma.site. El esquema lo mantiene la web. */
function db(): PDO
{
  static $pdo;
  if ($pdo) {
    return $pdo;
  }
  $sqlite = getenv('SEASON_WEB_SQLITE');
  if ($sqlite) {
    // Solo pruebas locales (igual que la web).
    $pdo = new PDO('sqlite:' . $sqlite);
    $pdo->exec('PRAGMA busy_timeout=5000');
  } else {
    $file = __DIR__ . '/config.local.php';
    if (!is_file($file)) {
      throw new RuntimeException('La conexión de este sitio todavía no está configurada.');
    }
    $c = require $file;
    $pdo = new PDO(
      'mysql:host=' . $c['host'] . ';port=' . (int) $c['port'] . ';dbname=' . $c['database'] . ';charset=utf8mb4',
      $c['username'],
      $c['password'],
      [PDO::ATTR_TIMEOUT => 8],
    );
  }
  $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
  $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
  $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
  return $pdo;
}

// Copia literal de tv.yoma.site/private/db.php (test/backend/test_api_site.py lo comprueba).
function sql(PDO $db, string $query, array $args = []): PDOStatement
{
  $started=hrtime(true);
  try {$s=$db->prepare($query);$s->execute($args);return $s;}
  finally {if(function_exists('observe_query'))observe_query($query,(hrtime(true)-$started)/1e6);}
}

// Copia literal de tv.yoma.site/private/bootstrap.php (test/backend/test_api_site.py lo comprueba).
function rate(PDO $db, string $key, int $max, int $seconds): void
{
  if(!consume_limit($db,$key,$max,$seconds))throw new WebError('Espera un momento antes de volver a intentarlo.',429);
}

// Copia literal de tv.yoma.site/private/runtime.php (test/backend/test_api_site.py lo comprueba).
function consume_limit(PDO $db,string $key,int $maximum,int $seconds,?int $at=null): bool
{
  $now=$at??time();$reset=$now+$seconds;
  $q='INSERT INTO sa1_limits(name,hits,reset_at) VALUES(?,1,?)';
  if($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'){
    // assignments are deliberately ordered: expiry is evaluated before reset_at changes.
    $q.=' ON DUPLICATE KEY UPDATE hits=IF(reset_at<=?,1,LEAST(hits+1,2147483647)),reset_at=IF(reset_at<=?,VALUES(reset_at),reset_at)';
  }else $q.=' ON CONFLICT(name) DO UPDATE SET hits=CASE WHEN reset_at<=? THEN 1 ELSE MIN(hits+1,2147483647) END,reset_at=CASE WHEN reset_at<=? THEN excluded.reset_at ELSE reset_at END';
  $own=!$db->inTransaction();if($own)$db->beginTransaction();
  try{
    sql($db,$q,[$key,$reset,$now,$now]);
    $row=sql($db,'SELECT hits FROM sa1_limits WHERE name=?'.($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'?' FOR UPDATE':''),[$key])->fetch();
    $allowed=(int)$row['hits']<=$maximum;if($own)$db->commit();return $allowed;
  }catch(Throwable $error){if($own&&$db->inTransaction())$db->rollBack();throw $error;}
}

// Copia literal de tv.yoma.site/private/runtime.php (test/backend/test_api_site.py lo comprueba).
function release_remote_session(): void
{
  // PHP keeps this request's actor in memory. No session data is changed after I/O.
  if(session_status()===PHP_SESSION_ACTIVE)session_write_close();
}

// Copia literal de tv.yoma.site/private/mal.php (test/backend/test_api_site.py lo comprueba).
function mal_tokens(array $response, ?string $oldRefresh = null): array
{
  $access = $response['access_token'] ?? null;
  $refresh = $response['refresh_token'] ?? $oldRefresh;
  $type = strtolower((string) ($response['token_type'] ?? ''));
  $seconds = filter_var($response['expires_in'] ?? null, FILTER_VALIDATE_INT);
  foreach ([$access, $refresh] as $token) {
    if (
      !is_string($token) ||
      strlen($token) < 8 ||
      strlen($token) > 16384 ||
      preg_match('/[\x00-\x20\x7f]/', $token)
    ) {
      throw new MalRemoteError(502);
    }
  }
  if (
    $type !== 'bearer' ||
    !$seconds ||
    $seconds < 30 ||
    $seconds > 366 * 86400
  ) {
    throw new MalRemoteError(502);
  }
  return [
    'access_token' => $access,
    'refresh_token' => $refresh,
    'expires_at' => time() + $seconds,
  ];
}

// Copia literal de tv.yoma.site/private/mal.php (test/backend/test_api_site.py lo comprueba).
function mal_profile_data(array $response): array
{
  $id = filter_var($response['id'] ?? null, FILTER_VALIDATE_INT);
  $name = $response['name'] ?? null;
  if (
    !$id ||
    $id < 1 ||
    !is_string($name) ||
    !preg_match('/^[a-zA-Z0-9_-]{1,60}$/D', $name)
  ) {
    throw new MalRemoteError(502);
  }
  return ['id' => $id, 'name' => $name, 'picture' => mal_avatar_url($response['picture']??'')];
}

// Copia literal de tv.yoma.site/private/mal-avatar.php (test/backend/test_api_site.py lo comprueba).
function mal_avatar_url(mixed $value): string
{
  if (!is_string($value) || strlen($value)>2048 || preg_match('/[\x00-\x20\\\\]/',$value)) return '';
  $url=parse_url($value);
  return is_array($url) && ($url['scheme']??'')==='https' && ($url['host']??'')==='cdn.myanimelist.net'
    && !isset($url['user']) && !isset($url['pass'])
    && in_array($url['port']??443,[443],true) && !isset($url['fragment']) ? $value : '';
}

require __DIR__ . '/mal-http.php';
