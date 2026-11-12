<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}
require __DIR__ . '/mal-http.php';
require __DIR__ . '/mal-safety.php';
require __DIR__ . '/mal-avatar.php';

// Persisted authenticated-data identifiers are storage formats, not display branding.
const MAL_TOKEN_AADS = ['YomaTV-MAL:', 'SeasonAV1-MAL:'];

function mal_encrypt(array $tokens, int $user): string
{
  $key = base64_decode(mal_require_config()['encryption_key'], true);
  $iv = random_bytes(12);
  $tag = '';
  $cipher = openssl_encrypt(
    json_encode($tokens, JSON_THROW_ON_ERROR),
    'aes-256-gcm',
    $key,
    OPENSSL_RAW_DATA,
    $iv,
    $tag,
    MAL_TOKEN_AADS[0] . $user,
  );
  if ($cipher === false) {
    throw new RuntimeException('Token encryption failed.');
  }
  return base64_encode($iv . $tag . $cipher);
}

function mal_decrypt(string $cipher, int $user): array
{
  $raw = base64_decode($cipher, true);
  $key = base64_decode(mal_require_config()['encryption_key'], true);
  $plain = false;
  if ($raw && strlen($raw) > 28) {
    foreach (MAL_TOKEN_AADS as $aad) {
      $plain = openssl_decrypt(
        substr($raw, 28),
        'aes-256-gcm',
        $key,
        OPENSSL_RAW_DATA,
        substr($raw, 0, 12),
        substr($raw, 12, 16),
        $aad . $user,
      );
      if ($plain !== false) break;
    }
  }
  if ($plain === false) {
    throw new WebError('Vuelve a conectar tu cuenta de MyAnimeList.', 409);
  }
  $tokens = json_decode($plain, true);
  if (!is_array($tokens)) {
    throw new WebError('Vuelve a conectar tu cuenta de MyAnimeList.', 409);
  }
  return $tokens;
}

function mal_status(PDO $db): array
{
  $row = sql(
    $db,
    "SELECT c.mal_user_id,c.mal_name,c.connected_at,c.checked_at,c.needs_auth,d.payload AS avatar_payload FROM sa1_mal_connections c LEFT JOIN sa1_personal_data d ON d.user_id=c.user_id AND d.kind='mal_avatar' AND d.item_key='profile' WHERE c.user_id=?",
    [member()],
  )->fetch();
  $ready = mal_ready();
  $avatar=$row?mal_avatar_entry($row['avatar_payload'],(int)$row['mal_user_id']):null;
  return [
    'configured' => $ready,
    'connected' => $ready && (bool) $row && !(bool) $row['needs_auth'],
    'needs_auth' => $row ? (bool) $row['needs_auth'] : false,
    'profile' => $row
      ? [
        'id' => (int) $row['mal_user_id'],
        'name' => $row['mal_name'],
        'picture' => $avatar['picture'],
        'avatar_next_refresh' => $avatar['next_refresh'],
        'url' =>
          'https://myanimelist.net/profile/' . rawurlencode($row['mal_name']),
        'connected_at' => (int) $row['connected_at'],
        'checked_at' => (int) $row['checked_at'],
      ]
      : null,
  ];
}

function mal_begin(PDO $db): string
{
  $user = member();
  $config = mal_require_config();
  rate($db, 'mal-connect:' . $user, 10, 600);
  $state = bin2hex(random_bytes(24));
  $verifier = bin2hex(random_bytes(48));
  upsert($db,'sa1_oauth_attempts',['user_id','state_hash','created_at'],[['user_id'=>uid(),'state_hash'=>hash('sha256',$state),'created_at'=>time()]],['user_id'],['state_hash','created_at']);
  $_SESSION['mal_oauth'] = [
    'state' => $state,
    'verifier' => $verifier,
    'user_id' => $user,
    'auth_version' => (int) ($_SESSION['auth_version'] ?? 0),
    'session_hash' => hash('sha256', session_id()),
    'issued_at' => time(),
  ];
  // MAL's authorization flow supports the plain PKCE challenge method.
  return 'https://myanimelist.net/v1/oauth2/authorize?' .
    http_build_query(
      [
        'response_type' => 'code',
        'client_id' => $config['client_id'],
        'redirect_uri' => $config['redirect_uri'],
        'state' => $state,
        'code_challenge' => $verifier,
        'code_challenge_method' => 'plain',
      ],
      '',
      '&',
      PHP_QUERY_RFC3986,
    );
}

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

function mal_complete(PDO $db, array $query): string
{
  validate_session($db);
  $flow = $_SESSION['mal_oauth'] ?? null;
  // An unrelated callback cannot consume a legitimate pending authorization.
  $state = $query['state'] ?? '';
  if (
    !is_array($flow) ||
    !is_string($state) ||
    !hash_equals($flow['state'], $state)
  ) {
    throw new WebError(
      'La autorización no es válida. Conecta MyAnimeList de nuevo.',
      403,
    );
  }
  unset($_SESSION['mal_oauth']);
  if (
    !uid() ||
    $flow['user_id'] !== uid() ||
    $flow['auth_version'] !== (int) ($_SESSION['auth_version'] ?? 0) ||
    !hash_equals($flow['session_hash'], hash('sha256', session_id())) ||
    $flow['issued_at'] < time() - 600 ||
    $flow['issued_at'] > time()
  ) {
    throw new WebError(
      'La autorización caducó. Conecta MyAnimeList de nuevo.',
      403,
    );
  }
  if (isset($query['error'])) {
    return 'denied';
  }
  $code = $query['code'] ?? '';
  if (
    !is_string($code) ||
    $code === '' ||
    strlen($code) > 4096 ||
    preg_match('/[\x00-\x20\x7f]/', $code)
  ) {
    throw new WebError('No se recibió un código de autorización válido.', 422);
  }
  $config = mal_require_config();
  $tokens = mal_tokens(
    mal_http('token', [
      'client_id' => $config['client_id'],
      'client_secret' => $config['client_secret'],
      'grant_type' => 'authorization_code',
      'code' => $code,
      'redirect_uri' => $config['redirect_uri'],
      'code_verifier' => $flow['verifier'],
    ]),
  );
  $profile = mal_profile_data(mal_http('profile', [], $tokens['access_token']));
  guard_remote_actor($db,(int)$flow['user_id'],(int)$flow['auth_version']);
  $db->beginTransaction();
  try {
    $attempt=sql($db,'SELECT state_hash FROM sa1_oauth_attempts WHERE user_id=?'.($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'?' FOR UPDATE':''),[uid()])->fetchColumn();
    if(!is_string($attempt)||!hash_equals($attempt,hash('sha256',$state)))throw new WebError('Hay una autorización más reciente. Completa esa conexión.',409);
    // Keep the last hash until expiry so an older callback cannot replace its notice.
    $identityChanged = mal_bind_identity($db, $profile['id']);
    upsert(
      $db,
      'sa1_mal_connections',
      [
        'user_id',
        'mal_user_id',
        'mal_name',
        'token_cipher',
        'expires_at',
        'connected_at',
        'checked_at',
        'needs_auth',
        'refresh_lock_until',
      ],
      [
        [
          'user_id' => uid(),
          'mal_user_id' => $profile['id'],
          'mal_name' => $profile['name'],
          'token_cipher' => mal_encrypt($tokens, uid()),
          'expires_at' => $tokens['expires_at'],
          'connected_at' => time(),
          'checked_at' => time(),
          'needs_auth' => 0,
          'refresh_lock_until' => 0,
        ],
      ],
      ['user_id'],
      [
        'mal_user_id',
        'mal_name',
        'token_cipher',
        'expires_at',
        'connected_at',
        'checked_at',
        'needs_auth',
        'refresh_lock_until',
      ],
    );
    mal_save_avatar($db,$profile['id'],$profile['picture']);
    log_event(
      $db,
      uid(),
      'Cuenta de MyAnimeList conectada: ' . $profile['name'] . '.' .
        ($identityChanged ? ' Se detuvieron los envíos anteriores y se renovará la lista de esta cuenta. Tu biblioteca web se conserva.' : ''),
    );
    $db->commit();
  } catch (Throwable $error) {
    $db->rollBack();
    throw $error;
  }
  return $identityChanged ? 'account_changed' : 'connected';
}

function mal_mark_expired(PDO $db, array $row): void
{
  sql(
    $db,
    'UPDATE sa1_mal_connections SET needs_auth=1,refresh_lock_until=0 WHERE user_id=? AND token_cipher=?',
    [uid(), $row['token_cipher']],
  );
}

function mal_access(PDO $db, bool $force = false): array
{
  $user = member();
  $config = mal_require_config();
  $row = sql($db, 'SELECT * FROM sa1_mal_connections WHERE user_id=?', [
    $user,
  ])->fetch();
  if (!$row || $row['needs_auth']) {
    throw new WebError(
      'Conecta tu cuenta de MyAnimeList para consultar su lista.',
      409,
    );
  }
  try {
    $tokens = mal_decrypt($row['token_cipher'], $user);
  } catch (WebError $error) {
    mal_mark_expired($db, $row);
    throw $error;
  }
  if (!$force && (int) $row['expires_at'] > time() + 60) {
    return [$row, $tokens];
  }
  $lock = sql(
    $db,
    'UPDATE sa1_mal_connections SET refresh_lock_until=? WHERE user_id=? AND token_cipher=? AND refresh_lock_until<=?',
    [time() + 30, $user, $row['token_cipher'], time()],
  );
  if ($lock->rowCount() !== 1) {
    throw new WebError(
      'Se está renovando la conexión. Intenta de nuevo en unos segundos.',
      503,
    );
  }
  try {
    $fresh = mal_tokens(
      mal_http('token', [
        'client_id' => $config['client_id'],
        'client_secret' => $config['client_secret'],
        'grant_type' => 'refresh_token',
        'refresh_token' => $tokens['refresh_token'],
      ]),
      $tokens['refresh_token'],
    );
    $cipher = mal_encrypt($fresh, $user);
    $updated = sql(
      $db,
      'UPDATE sa1_mal_connections SET token_cipher=?,expires_at=?,refresh_lock_until=0 WHERE user_id=? AND token_cipher=? AND needs_auth=0',
      [$cipher, $fresh['expires_at'], $user, $row['token_cipher']],
    );
    if ($updated->rowCount() !== 1) {
      throw new WebError(
        'La conexión cambió. Consulta tu cuenta otra vez.',
        409,
      );
    }
    $row['token_cipher'] = $cipher;
    return [$row, $fresh];
  } catch (MalRemoteError $error) {
    if ($error->httpStatus === 401 || $error->kind === 'invalid_grant') {
      mal_mark_expired($db, $row);
      throw new WebError(
        'MyAnimeList retiró la autorización. Vuelve a conectar tu cuenta.',
        409,
      );
    }
    throw $error;
  } finally {
    sql(
      $db,
      'UPDATE sa1_mal_connections SET refresh_lock_until=0 WHERE user_id=? AND token_cipher=?',
      [$user, $row['token_cipher']],
    );
  }
}

function mal_read(
  PDO $db,
  string $endpoint,
  array $parameters = [],
  string $method = 'GET',
  ?int $account = null,
): array {
  [$row, $tokens] = mal_access($db);
  $account ??= (int)$row['mal_user_id'];
  if ((int)$row['mal_user_id'] !== $account) throw new WebError('La cuenta de MyAnimeList cambió. Reabre la ficha antes de continuar.', 409);
  mal_assert_account($db, $account);
  try {
    return mal_http($endpoint, $parameters, $tokens['access_token'], $method);
  } catch (MalRemoteError $error) {
    if ($error->httpStatus !== 401) {
      throw $error;
    }
  }
  [$row, $tokens] = mal_access($db, true);
  if ((int)$row['mal_user_id'] !== $account) throw new WebError('La cuenta de MyAnimeList cambió. Reabre la ficha antes de continuar.', 409);
  mal_assert_account($db, $account);
  try {
    return mal_http($endpoint, $parameters, $tokens['access_token'], $method);
  } catch (MalRemoteError $error) {
    if ($error->httpStatus === 401) {
      mal_mark_expired($db, $row);
      throw new WebError('Vuelve a conectar tu cuenta de MyAnimeList.', 409);
    }
    throw $error;
  }
}

function dispatch_mal(PDO $db, string $action, array $input): ?array
{
  if (
    !in_array(
      $action,
      ['mal_connect', 'mal_disconnect', 'mal_profile', 'mal_list', 'mal_avatar'],
      true,
    )
  ) {
    return null;
  }
  member();
  if ($action === 'mal_connect') {
    return ['authorization_url' => mal_begin($db)];
  }
  if ($action === 'mal_avatar') return mal_refresh_avatar($db);
  if ($action === 'mal_disconnect') {
    sql($db,'DELETE FROM sa1_oauth_attempts WHERE user_id=?',[member()]);
    unset($_SESSION['mal_oauth']);
    $identity = mal_identity_id($db);
    if ($identity) upsert($db, 'sa1_mal_identity', ['user_id','mal_user_id'],
      [['user_id'=>uid(),'mal_user_id'=>$identity]], ['user_id'], ['mal_user_id']);
    sql($db, 'DELETE FROM sa1_mal_connections WHERE user_id=?', [uid()]);
    sql($db,"DELETE FROM sa1_personal_data WHERE user_id=? AND kind='mal_avatar'",[uid()]);
    $event = log_event($db, uid(), 'MyAnimeList desvinculado de esta web.');
    return [
      'mal' => mal_status($db),
      'message' =>
        'MyAnimeList desvinculado. Puedes retirar el permiso también desde MAL.',
      'patch' => state_patch($db, [], [], ['history' => [$event]]),
    ];
  }
  rate($db, 'mal-read:' . uid(), 90, 3600);
  try {
    if ($action === 'mal_profile') {
      $profile = mal_profile_data(mal_read($db, 'profile'));
      // Refresh must refer to the same identity originally authorized.
      $changed = sql(
        $db,
        'UPDATE sa1_mal_connections SET mal_name=?,checked_at=? WHERE user_id=? AND mal_user_id=?',
        [$profile['name'], time(), uid(), $profile['id']],
      );
      if (
        $changed->rowCount() === 0 &&
        (mal_status($db)['profile']['id'] ?? 0) !== $profile['id']
      ) {
        throw new WebError(
          'La cuenta de MAL cambió. Vuelve a conectar tu cuenta.',
          409,
        );
      }
      mal_save_avatar($db,$profile['id'],$profile['picture']);
      return [
        'mal' => mal_status($db),
        'message' => 'Conexión con MyAnimeList comprobada.',
      ];
    }
    $offset = filter_var($input['offset'] ?? 0, FILTER_VALIDATE_INT);
    if (
      $offset === false ||
      $offset < 0 ||
      $offset > 10000 ||
      $offset % 50 !== 0
    ) {
      throw new WebError('Página de MyAnimeList no válida.');
    }
    $response = mal_read($db, 'list', [
      'limit' => 50,
      'offset' => $offset,
      'sort' => 'list_updated_at',
      'fields' => 'list_status',
      'nsfw' => 'false',
    ]);
    if (!is_array($response['data'] ?? null) || count($response['data']) > 50) {
      throw new MalRemoteError(502);
    }
    $items = [];
    foreach ($response['data'] as $item) {
      $node = $item['node'] ?? [];
      $id = filter_var($node['id'] ?? null, FILTER_VALIDATE_INT);
      $title = $node['title'] ?? '';
      if (!$id || $id < 1 || !is_string($title) || strlen($title) > 1000) {
        throw new MalRemoteError(502);
      }
      $status = $item['list_status'] ?? [];
      $items[] = [
        'id' => $id,
        'title' => $title,
        'url' => 'https://myanimelist.net/anime/' . $id,
        'status' => in_array(
          $status['status'] ?? '',
          ['watching', 'completed', 'on_hold', 'dropped', 'plan_to_watch'],
          true,
        )
          ? $status['status']
          : 'unknown',
        'score' => max(0, min(10, (int) ($status['score'] ?? 0))),
        'watched' => max(
          0,
          min(100000, (int) ($status['num_episodes_watched'] ?? 0)),
        ),
      ];
    }
    return [
      'mal_list' => [
        'items' => $items,
        'offset' => $offset,
        'limit' => 50,
        'has_more' => !empty($response['paging']['next']) && $offset < 10000,
      ],
      'mal' => mal_status($db),
    ];
  } catch (MalRemoteError $error) {
    if ($error->httpStatus === 429) {
      throw new WebError(
        'MyAnimeList pidió una pausa. Intenta de nuevo en un minuto.',
        429,
      );
    }
    throw new WebError(
      'MyAnimeList no responde en este momento. Tu biblioteca sigue guardada; intenta de nuevo más tarde.',
      503,
    );
  }
}
