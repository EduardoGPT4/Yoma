<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit; }

// La web y el puente de MAL pueden cargar cada uno su copia: se declara una vez.
if (!function_exists('yoma_sync_schema')) {

/*
 * Sincronización de Yoma por cuenta de MyAnimeList.
 *
 * La identidad es la cuenta de MAL: la app la acredita con su device_token
 * (sa1_yomashi_devices.mal_user_id) y la web con sa1_mal_connections. Cada
 * elemento (tipo + clave) guarda su contenido, la fecha en que cambió y una
 * revisión creciente por cuenta. Gana el cambio más reciente de cada elemento;
 * un borrado es un elemento marcado como borrado, para que llegue a todos.
 *
 * Tipos (v1, YomaTV):
 *   anime    clave = slug                 {saved, favorite, status, title, cover}
 *   episode  clave = slug:número           {episode_id, position_ms, duration_ms, watched, title}
 * Tipos (v2, YomaShi; solo manga online, identificado por su URL):
 *   manga           clave = huella de la URL  {url, title, cover}            (biblioteca; borrado = quitado)
 *   manga_progress  clave = huella de la URL  {url, title, cover, chapter_url, chapter_title, page, source}
 *   manga_read      clave = huella de la URL del capítulo {url}           (leído; borrado = no leído)
 * La huella son los 40 primeros caracteres hexadecimales del SHA-256 de la URL.
 */
define('YOMA_SYNC_KINDS', ['anime', 'episode', 'manga', 'manga_progress', 'manga_read']);
define('YOMA_SYNC_STATUSES', ['planned', 'watching', 'completed', 'paused', 'dropped']);
define('YOMA_SYNC_PUSH_MAX', 200);
define('YOMA_SYNC_PULL_MAX', 500);
define('YOMA_SYNC_PAYLOAD_MAX', 4096);
define('YOMA_SYNC_ITEMS_MAX', 50000);

function yoma_sync_schema(PDO $db): void {
  $db->exec('CREATE TABLE IF NOT EXISTS sa1_yoma_sync (mal_user_id BIGINT NOT NULL, kind VARCHAR(16) NOT NULL, item_key VARCHAR(200) NOT NULL, payload TEXT NOT NULL, updated_at BIGINT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, rev BIGINT NOT NULL, PRIMARY KEY(mal_user_id, kind, item_key))');
  $db->exec('CREATE TABLE IF NOT EXISTS sa1_yoma_sync_rev (mal_user_id BIGINT NOT NULL PRIMARY KEY, rev BIGINT NOT NULL)');
  try { $db->exec('CREATE INDEX sa1_yoma_sync_rev_idx ON sa1_yoma_sync (mal_user_id, rev)'); } catch (PDOException) { /* ya existe */ }
}

function yoma_sync_now_ms(): int { return (int) floor(microtime(true) * 1000); }

/** Clave válida para el tipo, o error. */
function yoma_sync_key(string $kind, mixed $key): string {
  $slug = '[A-Za-z0-9_-]{1,160}';
  $ok = is_string($key) && match ($kind) {
    'anime' => preg_match('/^'.$slug.'$/D', $key) === 1,
    'episode' => preg_match('/^'.$slug.':[0-9]{1,6}(?:\.[0-9]{1,3})?$/D', $key) === 1,
    'manga', 'manga_progress', 'manga_read' => preg_match('/^[a-f0-9]{40}$/D', $key) === 1,
    default => false,
  };
  if (!$ok) throw new WebError('Elemento de sincronización inválido.');
  return $key;
}

/** Contenido normalizado: solo los campos conocidos, con sus tipos. */
function yoma_sync_payload(string $kind, mixed $payload): array {
  if (!is_array($payload) || array_is_list($payload) && $payload !== []) throw new WebError('Contenido de sincronización inválido.');
  $text = static fn(mixed $v, int $max): string => is_string($v) ? mb_substr($v, 0, $max) : '';
  $int = static fn(mixed $v, int $max): int => is_int($v) && $v >= 0 ? min($v, $max) : 0;
  $url = static fn(mixed $v): string => is_string($v) && preg_match('#^https?://[^\s"\'<>]{1,900}$#D', $v) ? $v : '';
  if ($kind === 'manga' || $kind === 'manga_progress' || $kind === 'manga_read') {
    $out = ['url' => $url($payload['url'] ?? '')];
    if ($out['url'] === '') throw new WebError('Contenido de sincronización inválido.');
    if ($kind === 'manga_read') return $out;
    $out += ['title' => $text($payload['title'] ?? '', 300), 'cover' => $url($payload['cover'] ?? '')];
    if ($kind === 'manga') return $out;
    return $out + [
      'chapter_url' => $url($payload['chapter_url'] ?? ''),
      'chapter_title' => $text($payload['chapter_title'] ?? '', 300),
      'page' => $int($payload['page'] ?? 0, 100000),
      'source' => preg_match('/^[a-z0-9_.-]{1,40}$/D', (string) ($payload['source'] ?? '')) ? $payload['source'] : '',
    ];
  }
  if ($kind === 'anime') {
    $status = $payload['status'] ?? 'planned';
    return [
      'saved' => ($payload['saved'] ?? false) === true,
      'favorite' => ($payload['favorite'] ?? false) === true,
      'status' => in_array($status, YOMA_SYNC_STATUSES, true) ? $status : 'planned',
      'title' => $text($payload['title'] ?? '', 300),
      'cover' => preg_match('#^https://[^\s"\'<>]{1,500}$#D', (string) ($payload['cover'] ?? '')) ? $payload['cover'] : '',
    ];
  }
  return [
    'episode_id' => $int($payload['episode_id'] ?? 0, 2147483647),
    'position_ms' => $int($payload['position_ms'] ?? 0, 86400000),
    'duration_ms' => $int($payload['duration_ms'] ?? 0, 86400000),
    'watched' => ($payload['watched'] ?? false) === true,
    'title' => $text($payload['title'] ?? '', 300),
  ];
}

/** Siguiente revisión de la cuenta (dentro de la transacción). */
function yoma_sync_next_rev(PDO $db, int $mal): int {
  $mysql = $db->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql';
  $row = sql($db, 'SELECT rev FROM sa1_yoma_sync_rev WHERE mal_user_id=?'.($mysql ? ' FOR UPDATE' : ''), [$mal])->fetch();
  $next = ($row ? (int) $row['rev'] : 0) + 1;
  if ($row) sql($db, 'UPDATE sa1_yoma_sync_rev SET rev=? WHERE mal_user_id=?', [$next, $mal]);
  else sql($db, 'INSERT INTO sa1_yoma_sync_rev (mal_user_id, rev) VALUES (?,?)', [$mal, $next]);
  return $next;
}

function yoma_sync_cursor(PDO $db, int $mal): int {
  $row = sql($db, 'SELECT rev FROM sa1_yoma_sync_rev WHERE mal_user_id=?', [$mal])->fetch();
  return $row ? (int) $row['rev'] : 0;
}

/**
 * Guarda un cambio si es más reciente que lo guardado. Devuelve la revisión
 * asignada, o null si se descartó por antiguo.
 */
function yoma_sync_put(PDO $db, int $mal, string $kind, string $key, array $payload, int $updatedAt, bool $deleted): ?int {
  $current = sql($db, 'SELECT updated_at FROM sa1_yoma_sync WHERE mal_user_id=? AND kind=? AND item_key=?', [$mal, $kind, $key])->fetch();
  if ($current && (int) $current['updated_at'] >= $updatedAt) return null;
  if (!$current) {
    $count = (int) sql($db, 'SELECT COUNT(*) AS n FROM sa1_yoma_sync WHERE mal_user_id=?', [$mal])->fetch()['n'];
    if ($count >= YOMA_SYNC_ITEMS_MAX) throw new WebError('La sincronización llegó a su límite de elementos.', 413);
  }
  $rev = yoma_sync_next_rev($db, $mal);
  $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
  if ($current) {
    sql($db, 'UPDATE sa1_yoma_sync SET payload=?, updated_at=?, deleted=?, rev=? WHERE mal_user_id=? AND kind=? AND item_key=?',
      [$json, $updatedAt, $deleted ? 1 : 0, $rev, $mal, $kind, $key]);
  } else {
    sql($db, 'INSERT INTO sa1_yoma_sync (mal_user_id, kind, item_key, payload, updated_at, deleted, rev) VALUES (?,?,?,?,?,?,?)',
      [$mal, $kind, $key, $json, $updatedAt, $deleted ? 1 : 0, $rev]);
  }
  return $rev;
}

/** Valida una petición de la app antes de tocar la base de datos. */
function yoma_sync_validate(array $input): void {
  $action = $input['action'];
  if ($action === 'sync_pull') {
    $since = $input['since'] ?? 0;
    $limit = $input['limit'] ?? YOMA_SYNC_PULL_MAX;
    if (!is_int($since) || $since < 0 || !is_int($limit) || $limit < 1 || $limit > YOMA_SYNC_PULL_MAX) throw new WebError('Petición de sincronización inválida.');
  }
  if ($action === 'sync_push') {
    $changes = $input['changes'] ?? null;
    if (!is_array($changes) || !array_is_list($changes) || count($changes) > YOMA_SYNC_PUSH_MAX) throw new WebError('Cambios de sincronización inválidos.');
    foreach ($changes as $change) {
      if (!is_array($change) || !in_array($change['kind'] ?? null, YOMA_SYNC_KINDS, true)) throw new WebError('Cambios de sincronización inválidos.');
      yoma_sync_key($change['kind'], $change['key'] ?? null);
      if (!is_int($change['updated_at'] ?? null) || $change['updated_at'] < 1577836800000) throw new WebError('Fecha de sincronización inválida.');
      if (array_key_exists('deleted', $change) && !is_bool($change['deleted'])) throw new WebError('Cambios de sincronización inválidos.');
      $raw = json_encode($change['payload'] ?? [], JSON_THROW_ON_ERROR);
      if (strlen($raw) > YOMA_SYNC_PAYLOAD_MAX) throw new WebError('Elemento de sincronización demasiado grande.', 413);
    }
  }
}

/** Acciones de la app: sync_capabilities, sync_pull y sync_push. */
function yoma_sync_dispatch(PDO $db, int $mal, array $input): array {
  // Las tablas ya existen: yoma_sync_schema() se llama antes de abrir la transacción.
  if ($mal < 1) throw new WebError('Conecta tu cuenta de MyAnimeList.', 401);
  $action = $input['action'];
  if ($action === 'sync_capabilities') return ['sync' => 1, 'kinds' => YOMA_SYNC_KINDS, 'push_max' => YOMA_SYNC_PUSH_MAX, 'pull_max' => YOMA_SYNC_PULL_MAX];
  if ($action === 'sync_pull') {
    $since = $input['since'] ?? 0;
    $limit = $input['limit'] ?? YOMA_SYNC_PULL_MAX;
    $rows = sql($db, 'SELECT kind, item_key, payload, updated_at, deleted, rev FROM sa1_yoma_sync WHERE mal_user_id=? AND rev>? ORDER BY rev LIMIT '.((int) $limit + 1), [$mal, $since])->fetchAll();
    $more = count($rows) > $limit;
    $rows = array_slice($rows, 0, $limit);
    $changes = array_map(static fn(array $r): array => [
      'kind' => $r['kind'], 'key' => $r['item_key'],
      'payload' => json_decode($r['payload'], true, 8, JSON_THROW_ON_ERROR),
      'updated_at' => (int) $r['updated_at'], 'deleted' => (int) $r['deleted'] === 1, 'rev' => (int) $r['rev'],
    ], $rows);
    $cursor = $changes ? end($changes)['rev'] : max($since, $more ? $since : yoma_sync_cursor($db, $mal));
    return ['changes' => $changes, 'cursor' => $cursor, 'more' => $more];
  }
  // sync_push: una fecha del futuro (reloj adelantado) no puede bloquear cambios posteriores.
  $limit = yoma_sync_now_ms() + 600000;
  $accepted = 0;
  foreach ($input['changes'] as $change) {
    $kind = $change['kind'];
    $key = yoma_sync_key($kind, $change['key']);
    $deleted = ($change['deleted'] ?? false) === true;
    $payload = $deleted ? [] : yoma_sync_payload($kind, $change['payload'] ?? []);
    if (yoma_sync_put($db, $mal, $kind, $key, $payload, min($change['updated_at'], $limit), $deleted) !== null) $accepted++;
  }
  return ['accepted' => $accepted, 'cursor' => yoma_sync_cursor($db, $mal)];
}
}
