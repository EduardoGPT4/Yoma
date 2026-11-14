<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit; }

// La web y el puente de MAL pueden cargar cada uno su copia: se declara una vez.
if (!function_exists('yoma_sync_web')) {

/*
 * La web de YomaTV en la sincronización de Yoma (ver yoma-sync.php).
 *
 * Una cuenta web con MyAnimeList conectado (sa1_mal_connections) comparte su
 * biblioteca y su progreso con la app de esa misma cuenta de MAL:
 *
 *   sa1_follow   ↔ anime    (guardado, favorito y estado)
 *   sa1_watched  ↔ episode  (visto)
 *   sa1_playback → episode  (posición: la web la comparte, pero no la recibe;
 *                            su tabla de reproducción tiene control de sesión propio)
 *
 * Se ejecuta al cargar la web (state/home), como mucho cada 30 segundos por
 * usuario. Detecta lo que cambió en la web comparando con lo que vio la vez
 * anterior (sa1_yoma_sync_web_items) y lo sube; después aplica lo que cambió
 * en otros sitios. Un fallo aquí nunca impide cargar la web.
 */
define('YOMA_SYNC_WEB_INTERVAL', 30);

function yoma_sync_web_schema(PDO $db): void {
  yoma_sync_schema($db);
  $db->exec('CREATE TABLE IF NOT EXISTS sa1_yoma_sync_web (user_id INTEGER NOT NULL PRIMARY KEY, mal_user_id BIGINT NOT NULL, cursor_rev BIGINT NOT NULL DEFAULT 0, checked_at BIGINT NOT NULL DEFAULT 0)');
  $db->exec('CREATE TABLE IF NOT EXISTS sa1_yoma_sync_web_items (user_id INTEGER NOT NULL, kind VARCHAR(16) NOT NULL, item_key VARCHAR(200) NOT NULL, hash VARCHAR(64) NOT NULL, PRIMARY KEY(user_id, kind, item_key))');
}

function yoma_sync_web_hash(array $payload): string {
  ksort($payload);
  return hash('sha256', json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
}

/**
 * Biblioteca y progreso de la cuenta web, en el formato de la sincronización.
 * Devuelve [kind => [key => ['payload' => [...], 'at' => ms]]].
 */
function yoma_sync_web_snapshot(PDO $db, int $user): array {
  $items = ['anime' => [], 'episode' => []];
  foreach (sql($db, 'SELECT f.slug, f.status, f.favorite, a.title, a.cover FROM sa1_follow f JOIN sa1_anime a ON a.slug=f.slug WHERE f.user_id=? AND f.excluded=0', [$user])->fetchAll() as $row) {
    $items['anime'][$row['slug']] = ['payload' => yoma_sync_payload('anime', [
      'saved' => true, 'favorite' => (int) $row['favorite'] === 1, 'status' => $row['status'],
      'title' => $row['title'], 'cover' => $row['cover'],
    ]), 'at' => 0];
  }
  $episodes = [];
  foreach (sql($db, 'SELECT e.slug, e.number, w.episode_id, w.watched_at, a.title FROM sa1_watched w JOIN sa1_episodes e ON e.id=w.episode_id JOIN sa1_anime a ON a.slug=e.slug WHERE w.user_id=?', [$user])->fetchAll() as $row) {
    $key = $row['slug'].':'.$row['number'];
    $episodes[$key] = ['episode_id' => (int) $row['episode_id'], 'watched' => true, 'position' => 0.0, 'duration' => 0.0, 'title' => $row['title'], 'at' => (int) $row['watched_at']];
  }
  foreach (sql($db, 'SELECT e.slug, e.number, p.episode_id, p.position, p.duration, p.updated_at, a.title FROM sa1_playback p JOIN sa1_episodes e ON e.id=p.episode_id JOIN sa1_anime a ON a.slug=e.slug WHERE p.user_id=? ORDER BY p.updated_at', [$user])->fetchAll() as $row) {
    $key = $row['slug'].':'.$row['number'];
    $old = $episodes[$key] ?? ['episode_id' => (int) $row['episode_id'], 'watched' => false, 'title' => $row['title'], 'at' => 0];
    // Varias formas de reproducir el mismo episodio: vale la más reciente.
    $episodes[$key] = [...$old, 'position' => (float) $row['position'], 'duration' => (float) $row['duration'], 'at' => max($old['at'], (int) $row['updated_at'])];
  }
  foreach ($episodes as $key => $e) {
    if (!preg_match('/^[A-Za-z0-9_-]{1,160}:[0-9]{1,6}(?:\.[0-9]{1,3})?$/D', $key)) continue;
    $items['episode'][$key] = ['payload' => yoma_sync_payload('episode', [
      'episode_id' => $e['episode_id'], 'watched' => $e['watched'],
      'position_ms' => (int) round($e['position'] * 1000), 'duration_ms' => (int) round($e['duration'] * 1000),
      'title' => $e['title'],
    ]), 'at' => $e['at'] * 1000];
  }
  foreach ($items['anime'] as $slug => $_) {
    if (!preg_match('/^[A-Za-z0-9_-]{1,160}$/D', (string) $slug)) unset($items['anime'][$slug]);
  }
  return $items;
}

/** Aplica a la web un cambio de la app. Devuelve si cambió algo. */
function yoma_sync_web_apply(PDO $db, int $user, string $kind, string $key, array $payload, bool $deleted, int $updatedAt): bool {
  if ($kind === 'anime') {
    $follow = sql($db, 'SELECT status, favorite, excluded FROM sa1_follow WHERE user_id=? AND slug=?', [$user, $key])->fetch();
    if ($follow && (int) $follow['excluded'] === 1) return false; // Lo ocultó en la web: no se toca.
    $keep = !$deleted && (($payload['saved'] ?? false) || ($payload['favorite'] ?? false));
    if (!$keep) {
      if (!$follow) return false;
      sql($db, 'DELETE FROM sa1_follow WHERE user_id=? AND slug=?', [$user, $key]);
      return true;
    }
    if (!sql($db, 'SELECT 1 FROM sa1_anime WHERE slug=?', [$key])->fetch()) return false; // No está en el catálogo web.
    $status = in_array($payload['status'] ?? '', YOMA_SYNC_STATUSES, true) ? $payload['status'] : 'planned';
    $favorite = ($payload['favorite'] ?? false) ? 1 : 0;
    if ($follow) {
      if ($follow['status'] === $status && (int) $follow['favorite'] === $favorite) return false;
      sql($db, 'UPDATE sa1_follow SET status=?, favorite=? WHERE user_id=? AND slug=?', [$status, $favorite, $user, $key]);
    } else {
      sql($db, "INSERT INTO sa1_follow (user_id, slug, status, favorite, excluded, score, notes) VALUES (?,?,?,?,0,0,'')", [$user, $key, $status, $favorite]);
    }
    return true;
  }
  // La web solo tiene anime: el manga de YomaShi no se aplica aquí.
  if ($kind !== 'episode') return false;
  // Episodio: el mismo id y anime en el catálogo web.
  [$slug, $number] = explode(':', $key, 2);
  $episode = sql($db, 'SELECT id FROM sa1_episodes WHERE slug=? AND number=?', [$slug, $number])->fetch();
  if (!$episode) return false;
  $id = (int) $episode['id'];
  $watched = !$deleted && ($payload['watched'] ?? false) === true;
  $exists = (bool) sql($db, 'SELECT 1 FROM sa1_watched WHERE user_id=? AND episode_id=?', [$user, $id])->fetch();
  if ($watched === $exists) return false;
  if ($watched) sql($db, 'INSERT INTO sa1_watched (user_id, episode_id, watched_at) VALUES (?,?,?)', [$user, $id, intdiv($updatedAt, 1000)]);
  else sql($db, 'DELETE FROM sa1_watched WHERE user_id=? AND episode_id=?', [$user, $id]);
  return true;
}

/** Sincroniza la cuenta web [$user] con la de su MyAnimeList. */
function yoma_sync_web(PDO $db, int $user, bool $force = false): array {
  if ($user < 1) return ['linked' => false];
  yoma_sync_web_schema($db);
  $connection = sql($db, 'SELECT mal_user_id FROM sa1_mal_connections WHERE user_id=?', [$user])->fetch();
  $mal = $connection ? (int) $connection['mal_user_id'] : 0;
  if ($mal < 1) return ['linked' => false];
  $state = sql($db, 'SELECT mal_user_id, cursor_rev, checked_at FROM sa1_yoma_sync_web WHERE user_id=?', [$user])->fetch();
  if (!$force && $state && (int) $state['mal_user_id'] === $mal && time() - (int) $state['checked_at'] < YOMA_SYNC_WEB_INTERVAL) return ['linked' => true, 'skipped' => true];
  $own = !$db->inTransaction();
  if ($own) $db->beginTransaction();
  try {
    // Otra cuenta de MAL: se empieza de cero con la nueva.
    if ($state && (int) $state['mal_user_id'] !== $mal) {
      sql($db, 'DELETE FROM sa1_yoma_sync_web_items WHERE user_id=?', [$user]);
      $state = false;
    }
    $cursor = $state ? (int) $state['cursor_rev'] : 0;
    $first = !$state;
    $known = [];
    foreach (sql($db, 'SELECT kind, item_key, hash FROM sa1_yoma_sync_web_items WHERE user_id=?', [$user])->fetchAll() as $row) $known[$row['kind']][$row['item_key']] = $row['hash'];
    $now = yoma_sync_now_ms();
    $snapshot = yoma_sync_web_snapshot($db, $user);
    // 1. Lo que cambió en la web desde la última vez sube a la cuenta.
    $sent = 0;
    foreach ($snapshot as $kind => $items) {
      foreach ($items as $key => $item) {
        if (($known[$kind][$key] ?? null) === yoma_sync_web_hash($item['payload'])) continue;
        // Primera vez: la biblioteca web entra como antigua para no pisar lo de la app.
        $at = $item['at'] > 0 ? min($item['at'], $now) : ($first ? 1577836800000 : $now);
        if (yoma_sync_put($db, $mal, $kind, $key, $item['payload'], $at, false) !== null) $sent++;
      }
      foreach ($known[$kind] ?? [] as $key => $_) {
        if (isset($items[$key])) continue;
        // Quitado en la web: deja de seguirse o deja de estar visto.
        $gone = $kind === 'anime' ? ['saved' => false, 'favorite' => false] : ['watched' => false];
        if (yoma_sync_put($db, $mal, $kind, $key, yoma_sync_payload($kind, $gone), $now, false) !== null) $sent++;
      }
    }
    // 2. Lo que cambió en otros sitios se aplica a la web.
    $applied = 0;
    do {
      $rows = sql($db, 'SELECT kind, item_key, payload, updated_at, deleted, rev FROM sa1_yoma_sync WHERE mal_user_id=? AND rev>? ORDER BY rev LIMIT 500', [$mal, $cursor])->fetchAll();
      foreach ($rows as $row) {
        $cursor = (int) $row['rev'];
        $payload = json_decode($row['payload'], true, 8, JSON_THROW_ON_ERROR);
        if (yoma_sync_web_apply($db, $user, $row['kind'], $row['item_key'], is_array($payload) ? $payload : [], (int) $row['deleted'] === 1, (int) $row['updated_at'])) $applied++;
      }
    } while (count($rows) === 500);
    // 3. Lo que hay ahora en la web es la base para la próxima vez.
    sql($db, 'DELETE FROM sa1_yoma_sync_web_items WHERE user_id=?', [$user]);
    foreach (yoma_sync_web_snapshot($db, $user) as $kind => $items) {
      foreach ($items as $key => $item) {
        sql($db, 'INSERT INTO sa1_yoma_sync_web_items (user_id, kind, item_key, hash) VALUES (?,?,?,?)', [$user, $kind, $key, yoma_sync_web_hash($item['payload'])]);
      }
    }
    if ($state) sql($db, 'UPDATE sa1_yoma_sync_web SET mal_user_id=?, cursor_rev=?, checked_at=? WHERE user_id=?', [$mal, $cursor, time(), $user]);
    else sql($db, 'INSERT INTO sa1_yoma_sync_web (user_id, mal_user_id, cursor_rev, checked_at) VALUES (?,?,?,?)', [$user, $mal, $cursor, time()]);
    if ($own) $db->commit();
    return ['linked' => true, 'sent' => $sent, 'applied' => $applied];
  } catch (Throwable $e) {
    if ($own && $db->inTransaction()) $db->rollBack();
    throw $e;
  }
}
}
