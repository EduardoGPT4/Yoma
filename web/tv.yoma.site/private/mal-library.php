<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function title_key(string $title): string
{
  $title = html_entity_decode($title, ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $ascii =
    function_exists('iconv') &&
    !preg_match('/[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]/u', $title)
      ? @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $title)
      : false;
  if ($ascii !== false && preg_match('/[a-zA-Z0-9]/', $ascii)) {
    $title = $ascii;
  }
  return preg_replace('/[^\p{L}\p{N}]+/u', '', mb_strtolower($title)) ?? '';
}
function mal_node(PDO $db, array $node, bool $fromApi = true): array
{
  $id = filter_var($node['id'] ?? null, FILTER_VALIDATE_INT);
  $title = trim((string) ($node['title'] ?? ''));
  if (!$id || $id < 1 || $title === '' || mb_strlen($title) > 400) {
    throw new WebError('Ficha de MAL inválida.');
  }
  $old =
    sql($db, 'SELECT * FROM sa1_mal_anime WHERE mal_id=?', [$id])->fetch() ?:
    [];
  $alternatives = $node['alternative_titles'] ?? [];
  $aliases = [$title];
  foreach (['en', 'ja'] as $key) {
    if (!empty($alternatives[$key])) {
      $aliases[] = mb_substr((string) $alternatives[$key], 0, 400);
    }
  }
  foreach (array_slice($alternatives['synonyms'] ?? [], 0, 30) as $alias) {
    if (is_string($alias)) {
      $aliases[] = mb_substr($alias, 0, 400);
    }
  }
  if (count($aliases) === 1 && isset($old['aliases'])) {
    $aliases = array_merge($aliases, json_decode($old['aliases'], true) ?: []);
  }
  $genres = array_values(
    array_filter(
      array_map(
        fn($g) => mb_substr((string) ($g['name'] ?? ''), 0, 80),
        array_slice($node['genres'] ?? [], 0, 30),
      ),
    ),
  );
  $cover =
    (string) ($node['main_picture']['large'] ??
      ($node['main_picture']['medium'] ?? ($old['cover'] ?? '')));
  if (!preg_match('~^https://cdn\.myanimelist\.net/~', $cover)) {
    $cover = '';
  }
  $row = [
    'mal_id' => $id,
    'title' => $title,
    'aliases' => json_encode(
      array_values(array_unique($aliases)),
      JSON_UNESCAPED_UNICODE,
    ),
    'search_key' => implode(
      ' ',
      array_map('title_key', array_values(array_unique($aliases))),
    ),
    'cover' => $cover,
    'media_type' =>
      (string) ($node['media_type'] ?? ($old['media_type'] ?? '')),
    'start_date' =>
      (string) ($node['start_date'] ?? ($old['start_date'] ?? '')),
    'airing_status' =>
      (string) ($node['status'] ?? ($old['airing_status'] ?? '')),
    'num_episodes' => max(
      0,
      min(100000, (int) ($node['num_episodes'] ?? ($old['num_episodes'] ?? 0))),
    ),
    'duration_seconds' => max(
      0,
      min(
        43200,
        (int) ($node['average_episode_duration'] ??
          ($old['duration_seconds'] ?? 0)),
      ),
    ),
    'genres' => $genres
      ? json_encode($genres, JSON_UNESCAPED_UNICODE)
      : $old['genres'] ?? '[]',
    'updated_at' => time(),
  ];
  upsert(
    $db,
    'sa1_mal_anime',
    array_keys($row),
    [$row],
    ['mal_id'],
    array_keys(array_diff_key($row, ['mal_id' => 1])),
  );
  if ($fromApi) catalog_cache_metadata($db, $row, $node);
  return $row;
}
function mal_catalog_index(PDO $db): array
{
  $byKey = [];
  foreach (
    sql(
      $db,
      'SELECT slug,title,start_date,category,cover FROM sa1_anime',
    )->fetchAll()
    as $a
  ) {
    $byKey[title_key($a['title'])][] = $a;
  }
  return $byKey;
}
function compatible_match(array $local, array $mal): bool
{
  if (
    $local['start_date'] &&
    $mal['start_date'] &&
    substr($local['start_date'], 0, 4) !== substr($mal['start_date'], 0, 4)
  ) {
    return false;
  }
  if (
    preg_match('/^\d{4}-\d{2}/', (string) $local['start_date']) &&
    preg_match('/^\d{4}-\d{2}/', $mal['start_date']) &&
    substr($local['start_date'], 0, 7) !== substr($mal['start_date'], 0, 7)
  ) {
    return false;
  }
  $type = title_key($local['category']);
  $m = $mal['media_type'];
  if (str_contains($type, 'movie') || str_contains($type, 'pelicula')) {
    return $m === '' || $m === 'movie';
  }
  if (str_contains($type, 'ova')) {
    return $m === '' || $m === 'ova';
  }
  if (str_contains($type, 'tv')) {
    return $m === '' || $m === 'tv';
  }
  if ($type === 'ona') {
    return $m === '' || $m === 'ona';
  }
  if (in_array($type, ['especial', 'special'], true)) {
    return $m === '' || $m === 'special';
  }
  return true;
}
function mal_try_match(PDO $db, array $entry, array $index): void
{
  if (
    sql($db, 'SELECT slug FROM sa1_mal_links WHERE user_id=? AND mal_id=?', [
      uid(),
      $entry['mal_id'],
    ])->fetchColumn()
  ) {
    return;
  }
  $matches = [];
  foreach (json_decode($entry['aliases'], true) ?: [$entry['title']] as $name) {
    $key = title_key($name);
    if (mb_strlen($key) < 5) {
      continue;
    }
    foreach ($index[$key] ?? [] as $a) {
      if (compatible_match($a, $entry)) {
        $matches[$a['slug']] = $a;
      }
    }
  }
  if (count($matches) !== 1) {
    return;
  }
  $slug = array_key_first($matches);
  if (
    sql($db, 'SELECT mal_id FROM sa1_mal_links WHERE user_id=? AND slug=?', [
      uid(),
      $slug,
    ])->fetchColumn()
  ) {
    return;
  }
  sql(
    $db,
    'INSERT INTO sa1_mal_links(user_id,slug,mal_id,confirmed) VALUES(?,?,?,0)',
    [uid(), $slug, $entry['mal_id']],
  );
  mal_copy_follow($db, $slug, $entry['mal_id']);
}
function mal_copy_follow(PDO $db, string $slug, int $id): void
{
  $entry = sql($db, 'SELECT * FROM sa1_mal_list WHERE user_id=? AND mal_id=?', [
    uid(),
    $id,
  ])->fetch();
  if (!$entry) {
    return;
  }
  $f = sql($db, 'SELECT * FROM sa1_follow WHERE user_id=? AND slug=?', [
    uid(),
    $slug,
  ])->fetch() ?: [
    'user_id' => uid(),
    'slug' => $slug,
    'favorite' => 0,
    'excluded' => 0,
    'notes' => '',
  ];
  $f['status'] =
    ['plan_to_watch' => 'planned', 'on_hold' => 'paused'][$entry['status']] ??
    $entry['status'];
  $f['score'] = (int) $entry['score'];
  if ($entry['notes'] !== '') {
    $f['notes'] = $entry['notes'];
  }
  upsert(
    $db,
    'sa1_follow',
    array_keys($f),
    [$f],
    ['user_id', 'slug'],
    ['status', 'score', 'notes'],
  );
}
function mal_cache_list(
  PDO $db,
  array $node,
  array $status,
  string $source,
  string $run,
): array {
  // XML cannot replace metadata already obtained for another account from MAL.
  $existing =
    $source === 'xml'
      ? sql($db, 'SELECT * FROM sa1_mal_anime WHERE mal_id=?', [
        (int) ($node['id'] ?? 0),
      ])->fetch()
      : false;
  $anime = $existing ?: mal_node($db, $node, $source !== 'xml');
  $state = (string) ($status['status'] ?? 'plan_to_watch');
  if (
    !in_array(
      $state,
      ['watching', 'completed', 'on_hold', 'dropped', 'plan_to_watch'],
      true,
    )
  ) {
    throw new WebError('Estado de MAL inválido.');
  }
  $row = [
    'user_id' => uid(),
    'mal_id' => $anime['mal_id'],
    'status' => $state,
    'watched' => max(
      0,
      min(100000, (int) ($status['num_episodes_watched'] ?? 0)),
    ),
    'score' => max(0, min(10, (int) ($status['score'] ?? 0))),
    'notes' => mb_substr(
      (string) ($status['comments'] ??
        (sql(
          $db,
          'SELECT notes FROM sa1_mal_list WHERE user_id=? AND mal_id=?',
          [uid(), $anime['mal_id']],
        )->fetchColumn() ?:
          '')),
      0,
      2000,
    ),
    'source' => $source,
    'sync_run' => $run,
    'updated_at' => time(),
  ];
  upsert(
    $db,
    'sa1_mal_list',
    array_keys($row),
    [$row],
    ['user_id', 'mal_id'],
    ['status', 'watched', 'score', 'notes', 'source', 'sync_run', 'updated_at'],
  );
  return $anime;
}
function mal_library_rows(
  PDO $db,
  ?string $status = null,
  int $limit = 5000,
): array {
  $args = [uid()];
  $where = $status ? ' AND l.status=?' : '';
  if ($status) {
    $args[] = $status;
  }
  $rows = sql(
    $db,
    'SELECT m.*,l.status,l.watched,l.score,l.notes,l.source,k.slug,k.confirmed FROM sa1_mal_list l JOIN sa1_mal_anime m ON m.mal_id=l.mal_id LEFT JOIN sa1_mal_links k ON k.mal_id=l.mal_id AND k.user_id=l.user_id WHERE l.user_id=?' .
      $where .
      ' ORDER BY l.updated_at DESC,m.title LIMIT ' .
      max(1, min(5000, $limit)),
    $args,
  )->fetchAll();
  foreach ($rows as &$r) {
    foreach (
      ['mal_id', 'watched', 'score', 'num_episodes', 'duration_seconds']
      as $key
    ) {
      $r[$key] = (int) $r[$key];
    }
    $r['aliases'] = json_decode($r['aliases'], true) ?: [];
    $r['genres'] = json_decode($r['genres'], true) ?: [];
  }
  return $rows;
}
function mal_refresh_page(PDO $db, array $input): array
{
  $account = mal_identity_id($db);
  $offset = filter_var($input['offset'] ?? 0, FILTER_VALIDATE_INT);
  if ($offset === false || $offset < 0 || $offset > 10000 || $offset % 50) {
    throw new WebError('Página inválida.');
  }
  $sync = sql($db, 'SELECT * FROM sa1_mal_sync WHERE user_id=?', [
    uid(),
  ])->fetch();
  if (
    $offset &&
    (!$sync ||
      (int) $sync['next_offset'] !== $offset ||
      $sync['updated_at'] < time() - 1800)
  ) {
    throw new WebError('La actualización caducó. Empieza otra vez.', 409);
  }
  $run =
    $offset === 0 ? time() . '-' . bin2hex(random_bytes(16)) : $sync['run_id'];
  $started = (int) explode('-', $run, 2)[0];
  $response = mal_read($db, 'list', [
    'limit' => 50,
    'offset' => $offset,
    'sort' => 'anime_title',
    'nsfw' => 'true',
    'fields' =>
      'list_status,alternative_titles,media_type,start_date,status,num_episodes,average_episode_duration,genres,mean,studios',
  ], 'GET', $account);
  if (!is_array($response['data'] ?? null) || count($response['data']) > 50) {
    throw new MalRemoteError(502);
  }
  $more = !empty($response['paging']['next']);
  if ($more && $offset >= 10000) {
    throw new WebError(
      'La lista supera el límite de esta actualización. Se conservan los datos anteriores.',
      422,
    );
  }
  $index = mal_catalog_index($db);
  $db->beginTransaction();
  try {
    mal_assert_account($db, $account);
    foreach ($response['data'] as $entry) {
      if (mal_is_removed($db, $account, (int)($entry['node']['id'] ?? 0))) continue;
      $edited = sql(
        $db,
        'SELECT updated_at,sync_run FROM sa1_mal_list WHERE user_id=? AND mal_id=?',
        [uid(), (int) ($entry['node']['id'] ?? 0)],
      )->fetch();
      if (
        $edited &&
        $edited['sync_run'] === 'edit' &&
        (int) $edited['updated_at'] >= $started
      ) {
        $m = mal_node($db, $entry['node']);
        sql(
          $db,
          'UPDATE sa1_mal_list SET sync_run=? WHERE user_id=? AND mal_id=?',
          [$run, uid(), $m['mal_id']],
        );
      } else {
        $m = mal_cache_list(
          $db,
          $entry['node'] ?? [],
          $entry['list_status'] ?? [],
          'api',
          $run,
        );
      }
      mal_try_match($db, $m, $index);
      $slug = sql(
        $db,
        'SELECT slug FROM sa1_mal_links WHERE user_id=? AND mal_id=?',
        [uid(), $m['mal_id']],
      )->fetchColumn();
      if ($slug) {
        mal_copy_follow($db, (string) $slug, $m['mal_id']);
      }
    }
    if (!$more) {
      sql(
        $db,
        'DELETE FROM sa1_mal_list WHERE user_id=? AND source=? AND sync_run<>? AND updated_at<?',
        [uid(), 'api', $run, $started],
      );
    }
    upsert(
      $db,
      'sa1_mal_sync',
      ['user_id', 'run_id', 'next_offset', 'updated_at', 'finished_at'],
      [
        [
          'user_id' => uid(),
          'run_id' => $run,
          'next_offset' => $more ? $offset + 50 : 0,
          'updated_at' => time(),
          'finished_at' => $more ? (int) ($sync['finished_at'] ?? 0) : time(),
        ],
      ],
      ['user_id'],
      ['run_id', 'next_offset', 'updated_at', 'finished_at'],
    );
    $db->commit();
  } catch (Throwable $error) {
    $db->rollBack();
    throw $error;
  }
  return [
    'more' => $more,
    'offset' => $more ? $offset + 50 : 0,
    'received' => count($response['data']),
  ];
}
function dispatch_mal_library(PDO $db, string $action, array $input): ?array
{
  if (
    !in_array(
      $action,
      [
        'mal_cached',
        'mal_entry',
        'mal_refresh',
        'mal_candidates',
        'mal_link',
        'mal_unlink',
        'mal_search',
        'mal_save',
        'mal_remove',
        'mal_xml',
      ],
      true,
    )
  ) {
    return null;
  }
  member();
  if (array_key_exists('mal_account_id', $input) &&
    (!is_int($input['mal_account_id']) || $input['mal_account_id'] !== mal_identity_id($db)))
    throw new WebError('La cuenta de MyAnimeList cambió. Reabre la ficha antes de continuar.', 409);
  if ($action === 'mal_entry') {
    $entry = sql(
      $db,
      'SELECT m.*,l.status,l.watched,l.score,l.notes,l.source,k.slug FROM sa1_mal_anime m LEFT JOIN sa1_mal_list l ON l.mal_id=m.mal_id AND l.user_id=? LEFT JOIN sa1_mal_links k ON k.mal_id=m.mal_id AND k.user_id=? WHERE m.mal_id=?',
      [uid(), uid(), (int) ($input['mal_id'] ?? 0)],
    )->fetch();
    if (!$entry) {
      throw new WebError('Ficha de MAL no encontrada.', 404);
    }
    return ['mal_entry' => $entry + ['mal_account_id'=>mal_identity_id($db)]];
  }
  if ($action === 'mal_cached') {
    $rows = mal_library_rows($db);
    $filter = (string) ($input['status'] ?? '');
    $search = title_key((string) ($input['search'] ?? ''));
    $rows = array_values(
      array_filter(
        $rows,
        fn($r) => (!$filter || $r['status'] === $filter) &&
          (!$search ||
            str_contains(
              title_key($r['title'] . ' ' . implode(' ', $r['aliases'])),
              $search,
            )),
      ),
    );
    $total = count($rows);
    $pages = max(1, (int) ceil($total / 50));
    $page = max(1, min($pages, (int) ($input['page'] ?? 1)));
    return [
      'mal_library' => [
        'items' => array_slice($rows, ($page - 1) * 50, 50),
        'total' => $total,
        'page' => $page,
        'pages' => $pages,
      ],
      'mal' => mal_status($db),
    ];
  }
  rate($db, 'mal-library:' . uid(), 300, 3600);
  try {
    if ($action === 'mal_refresh') {
      return [
        'progress' => mal_refresh_page($db, $input),
        'home' => home_data($db),
        'patch' => state_patch($db, [], [], ['refresh_anime' => true]),
      ];
    }
    if ($action === 'mal_xml') {
      return mal_import_xml(
        $db,
        (string) ($input['xml'] ?? ''),
        !empty($input['commit']),
      );
    }
    if ($action === 'mal_search') {
      $query = trim(mb_substr((string) ($input['query'] ?? ''), 0, 80));
      if (mb_strlen($query) < 3) {
        throw new WebError('Escribe al menos tres caracteres.');
      }
      $result = mal_read($db, 'search', [
        'q' => $query,
        'limit' => 8,
        'fields' =>
          'alternative_titles,media_type,start_date,status,num_episodes,genres,mean,studios',
      ]);
      $items = [];
      foreach ($result['data'] ?? [] as $item) {
        $items[] = mal_node($db, $item['node'] ?? []);
      }
      return ['matches' => $items];
    }
    $id = filter_var($input['mal_id'] ?? null, FILTER_VALIDATE_INT);
    $m = $id
      ? sql($db, 'SELECT * FROM sa1_mal_anime WHERE mal_id=?', [$id])->fetch()
      : false;
    if (!$m) {
      throw new WebError(
        'Actualiza tu lista o busca primero el anime en MAL.',
        404,
      );
    }
    if ($action === 'mal_candidates') {
      $names = json_decode($m['aliases'], true) ?: [$m['title']];
      $items = [];
      $search = title_key((string) ($input['search'] ?? ''));
      foreach (mal_catalog_index($db) as $key => $rows) {
        // PHP casts numeric title keys (for example "86") to integers.
        $key = (string) $key;
        $score = 0;
        foreach ($names as $name) {
          $n = title_key($name);
          similar_text($n, $key, $percent);
          $score = max($score, $n === $key ? 100 : $percent);
        }
        if ($search !== '' && !str_contains($key, $search)) {
          continue;
        }
        foreach ($rows as $row) {
          $rowScore = compatible_match($row, $m) ? $score : min(70, $score);
          if ($rowScore >= 35 || $search !== '') {
            $items[] = $row + ['match_score' => round($rowScore)];
          }
        }
      }
      usort($items, fn($a, $b) => $b['match_score'] <=> $a['match_score']);
      return ['matches' => array_slice($items, 0, 12), 'mal_anime' => $m];
    }
    if ($action === 'mal_link') {
      $slug = (string) ($input['slug'] ?? '');
      find_anime($db, $slug);
      $other = sql(
        $db,
        'SELECT slug FROM sa1_mal_links WHERE user_id=? AND mal_id=?',
        [uid(), $id],
      )->fetchColumn();
      if ($other && $other !== $slug) {
        throw new WebError(
          'Este ID de MAL ya está vinculado a otro anime. Desvincúlalo primero.',
          409,
        );
      }
      upsert(
        $db,
        'sa1_mal_links',
        ['user_id', 'slug', 'mal_id', 'confirmed'],
        [
          [
            'user_id' => uid(),
            'slug' => $slug,
            'mal_id' => $id,
            'confirmed' => 1,
          ],
        ],
        ['user_id', 'slug'],
        ['mal_id', 'confirmed'],
      );
      mal_copy_follow($db, $slug, $id);
      return [
        'home' => home_data($db),
        'detail' => detail($db, $slug),
        'patch' => state_patch($db, [$slug]),
        'message' => 'Relación con MAL guardada para tu cuenta.',
      ];
    }
    if ($action === 'mal_unlink') {
      sql($db, 'DELETE FROM sa1_mal_links WHERE user_id=? AND mal_id=?', [
        uid(),
        $id,
      ]);
      return [
        'home' => home_data($db),
        'patch' => state_patch($db, [], [], ['refresh_anime' => true]),
        'message' => 'Relación retirada. La lista de MAL se conserva.',
      ];
    }
    if ($action === 'mal_remove') {
      if (($input['confirmation'] ?? '') !== 'QUITAR') {
        throw new WebError('Confirma que quieres retirar el anime de MAL.');
      }
      $account = mal_identity_id($db);
      $cancel = mal_cancel_title($db, $account, $id);
      try {
        mal_read($db, 'list-status:' . $id, [], 'DELETE', $account);
        mal_assert_account($db, $account);
      } finally {
        sql($db, 'UPDATE sa1_watch_sync SET lock_until=0 WHERE user_id=? AND generation=?', [uid(), $cancel]);
      }
      sql($db, 'DELETE FROM sa1_mal_list WHERE user_id=? AND mal_id=?', [
        uid(),
        $id,
      ]);
      return [
        'home' => home_data($db),
        'message' => 'Anime retirado de tu lista de MAL.',
        'patch' => state_patch($db, [], [], ['refresh_anime'=>true]),
      ];
    }
    $status = (string) ($input['status'] ?? '');
    $score = filter_var($input['score'] ?? null, FILTER_VALIDATE_INT);
    $watched = filter_var($input['watched'] ?? null, FILTER_VALIDATE_INT);
    if (
      !in_array(
        $status,
        ['watching', 'completed', 'on_hold', 'dropped', 'plan_to_watch'],
        true,
      ) ||
      $score === false ||
      $score < 0 ||
      $score > 10 ||
      $watched === false ||
      $watched < 0 ||
      $watched > 100000 ||
      ((int) $m['num_episodes'] > 0 && $watched > (int) $m['num_episodes'])
    ) {
      throw new WebError(
        'Revisa el estado, los capítulos vistos y la puntuación.',
      );
    }
    $account = mal_identity_id($db);
    $localSlug=(string)sql($db,'SELECT slug FROM sa1_mal_links WHERE user_id=? AND mal_id=?',[uid(),$id])->fetchColumn();
    $previousWatched=(int)sql($db,'SELECT watched FROM sa1_mal_list WHERE user_id=? AND mal_id=?',[uid(),$id])->fetchColumn();
    $pendingWatched=$localSlug?(int)sql($db,"SELECT target FROM sa1_watch_sync WHERE user_id=? AND slug=? AND state IN ('pending','saving')",[uid(),$localSlug])->fetchColumn():0;
    $correcting=$localSlug && ($watched<max($previousWatched,$pendingWatched) || !empty($input['reconcile_local']));
    $cancelGeneration=null;
    if($correcting){
      if(($input['confirmation']??'')!=='CORREGIR')throw new WebError('Confirma la corrección del progreso y sus marcas locales.',409);
      $cancelGeneration=mal_cancel_title($db,$account,$id);progress_fence($db,$localSlug);
    }
    try {
    $remote = mal_read(
      $db,
      'list-status:' . $id,
      [
        'status' => $status,
        'score' => $score,
        'num_watched_episodes' => $watched,
      ],
      'PATCH',
      $account,
    );
    mal_assert_account($db, $account);
    } finally {if($cancelGeneration)sql($db,'UPDATE sa1_watch_sync SET lock_until=0 WHERE user_id=? AND generation=?',[uid(),$cancelGeneration]);}
    mal_allow_title($db, $account, $id);
    if (
      !isset(
        $remote['status'],
        $remote['num_episodes_watched'],
        $remote['score'],
      )
    ) {
      throw new MalRemoteError(502);
    }
    mal_cache_list(
      $db,
      ['id' => $id, 'title' => $m['title']],
      $remote,
      'api',
      'edit',
    );
    $slug = sql(
      $db,
      'SELECT slug FROM sa1_mal_links WHERE user_id=? AND mal_id=?',
      [uid(), $id],
    )->fetchColumn();
    if ($slug) {
      if($correcting)progress_reconcile_local($db,(string)$slug,$watched);
      mal_copy_follow($db, (string) $slug, $id);
    }
    $event = log_event(
      $db,
      uid(),
      'Lista de MAL actualizada: ' . $m['title'] . '.',
    );
    return [
      'home' => home_data($db),
      'message' => 'Cambios guardados en MyAnimeList.',
      'patch' => state_patch(
        $db,
        $slug ? [(string) $slug] : [],
        [],
        ['history' => [$event]],
      ),
    ];
  } catch (MalRemoteError $error) {
    throw new WebError(
      $error->httpStatus === 429
        ? 'MAL pidió una pausa. Intenta de nuevo en un minuto.'
        : ($error->httpStatus === 400
          ? 'MAL rechazó los datos. Revisa el formulario.'
          : 'MAL no responde. No se confirmó ningún cambio remoto.'),
      $error->httpStatus === 429 ? 429 : 503,
    );
  }
}
