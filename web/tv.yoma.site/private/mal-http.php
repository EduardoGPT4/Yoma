<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

final class MalRemoteError extends RuntimeException
{
  public function __construct(public int $httpStatus, public string $kind = '')
  {
    // Never include the provider body: it may contain credentials or tokens.
    parent::__construct('MyAnimeList no pudo completar la solicitud.');
  }
}

function mal_config(): array
{
  if (getenv('SEASON_WEB_SQLITE') && getenv('SEASON_WEB_MAL_TEST_URL')) {
    return [
      'client_id' => 'local-test-client',
      'client_secret' => 'local-test-secret',
      'redirect_uri' => 'https://tv.yoma.site/mal-callback.php',
      'encryption_key' => base64_encode(
        hash('sha256', 'local-only-mal-key', true),
      ),
    ];
  }
  $file = __DIR__ . '/config.local.php';
  $config = is_file($file) ? require $file : [];
  return is_array($config['mal'] ?? null) ? $config['mal'] : [];
}

function mal_ready(): bool
{
  $c = mal_config();
  return !empty($c['client_id']) &&
    !empty($c['client_secret']) &&
    ($c['redirect_uri'] ?? '') ===
      'https://tv.yoma.site/mal-callback.php' &&
    strlen(base64_decode((string) ($c['encryption_key'] ?? ''), true) ?: '') ===
      32 &&
    function_exists('openssl_encrypt') &&
    function_exists('curl_init');
}

function mal_require_config(): array
{
  if (!mal_ready()) {
    throw new WebError(
      'La conexión con MyAnimeList aún no está configurada en el servidor.',
      503,
    );
  }
  return mal_config();
}

function mal_http(
  string $endpoint,
  array $parameters = [],
  ?string $token = null,
  string $method = 'GET',
): array {
  $allowed = [
    'token' => 'https://myanimelist.net/v1/oauth2/token',
    'profile' => 'https://api.myanimelist.net/v2/users/@me',
    'list' => 'https://api.myanimelist.net/v2/users/@me/animelist',
    'search' => 'https://api.myanimelist.net/v2/anime',
  ];
  if (preg_match('/^anime:([1-9][0-9]{0,8})$/D', $endpoint, $match)) {
    if ($method !== 'GET') {
      throw new LogicException('Invalid MAL method.');
    }
    $allowed[$endpoint] = 'https://api.myanimelist.net/v2/anime/' . $match[1];
  } elseif (
    preg_match('/^list-status:([1-9][0-9]{0,8})$/D', $endpoint, $match)
  ) {
    if (!in_array($method, ['PATCH', 'DELETE'], true)) {
      throw new LogicException('Invalid MAL method.');
    }
    $allowed[$endpoint] =
      'https://api.myanimelist.net/v2/anime/' . $match[1] . '/my_list_status';
  } elseif ($method !== 'GET') {
    throw new LogicException('Invalid MAL method.');
  }
  if (!isset($allowed[$endpoint])) {
    throw new LogicException('Unknown MAL endpoint.');
  }
  $url = $allowed[$endpoint];
  $test = getenv('SEASON_WEB_SQLITE')
    ? getenv('SEASON_WEB_MAL_TEST_URL')
    : false;
  if ($test) {
    if (!preg_match('~^http://127\.0\.0\.1:[0-9]{4,5}$~D', $test)) {
      throw new LogicException('The mock must be a local fixture.');
    }
    $url = $test . '/' . $endpoint;
  }
  $encoded = http_build_query($parameters, '', '&', PHP_QUERY_RFC3986);
  if ($endpoint !== 'token' && $method === 'GET' && $encoded !== '') {
    $url .= '?' . $encoded;
  }
  $body = '';
  $headers = ['Accept: application/json'];
  if ($token !== null) {
    $headers[] = 'Authorization: Bearer ' . $token;
  }
  if ($endpoint === 'token' || $method === 'PATCH') {
    $headers[] = 'Content-Type: application/x-www-form-urlencoded';
  }
  $curl = curl_init($url);
  curl_setopt_array($curl, [
    CURLOPT_HTTPHEADER => $headers,
    CURLOPT_CONNECTTIMEOUT => 8,
    CURLOPT_TIMEOUT => 20,
    CURLOPT_FOLLOWLOCATION => false,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
    CURLOPT_PROTOCOLS => $test ? CURLPROTO_HTTP : CURLPROTO_HTTPS,
    CURLOPT_USERAGENT => 'SeasonAV1Web/1.0 (MyAnimeList connection)',
    CURLOPT_WRITEFUNCTION => static function ($curl, string $chunk) use (
      &$body,
    ): int {
      if (strlen($body) + strlen($chunk) > 2 * 1024 * 1024) {
        return 0;
      }
      $body .= $chunk;
      return strlen($chunk);
    },
  ]);
  if ($endpoint === 'token') {
    curl_setopt($curl, CURLOPT_POST, true);
    curl_setopt($curl, CURLOPT_POSTFIELDS, $encoded);
  }
  if (in_array($method, ['PATCH', 'DELETE'], true)) {
    curl_setopt($curl, CURLOPT_CUSTOMREQUEST, $method);
    if ($method === 'PATCH') {
      curl_setopt($curl, CURLOPT_POSTFIELDS, $encoded);
    }
  }
  $ok = curl_exec($curl);
  $status = (int) curl_getinfo($curl, CURLINFO_HTTP_CODE);
  curl_close($curl);
  if ($ok && $method === 'DELETE' && $status >= 200 && $status < 300) {
    return [];
  }
  $data = json_decode($body, true);
  if (!$ok || $status < 200 || $status >= 300 || !is_array($data)) {
    $kind =
      is_array($data) && ($data['error'] ?? '') === 'invalid_grant'
        ? 'invalid_grant'
        : '';
    throw new MalRemoteError($status, $kind);
  }
  return $data;
}
