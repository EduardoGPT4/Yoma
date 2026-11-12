<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function dispatch_library_transfer(
  PDO $db,
  string $action,
  array $input,
): ?array {
  if ($action === 'library_export') {
    $user = member();
    $entries = sql(
      $db,
      'SELECT f.slug,a.title,f.status,f.favorite,f.excluded,f.score,f.notes FROM sa1_follow f JOIN sa1_anime a ON a.slug=f.slug WHERE f.user_id=? ORDER BY a.title',
      [$user],
    )->fetchAll();
    foreach ($entries as &$entry) {
      $entry['favorite'] = (bool) $entry['favorite'];
      $entry['excluded'] = (bool) $entry['excluded'];
      $entry['score'] = (int) $entry['score'];
    }
    $watched = sql(
      $db,
      'SELECT e.slug,e.number,w.watched_at FROM sa1_watched w JOIN sa1_episodes e ON e.id=w.episode_id WHERE w.user_id=? ORDER BY e.slug,e.number_value',
      [$user],
    )->fetchAll();
    foreach ($watched as &$episode) {
      $episode['watched_at'] = (int) $episode['watched_at'];
    }
    return [
      'library' => [
        'format' => 'seasonav1.library/v1',
        'exported_at' => date(DATE_ATOM),
        'entries' => $entries,
        'watched' => $watched,
        'extras' => personal_export($db),
      ],
    ];
  }
  if ($action !== 'library_import') {
    return null;
  }
  $user = member();
  $importBatch = $input['batch'] ?? null;
  if ($importBatch === null) rate($db, 'library-import:' . $user, 5, 300);
  else {
    if (!is_array($importBatch) || !preg_match('/^[a-f0-9]{32}$/D', (string)($importBatch['id'] ?? '')) ||
      !is_int($importBatch['index'] ?? null) || !is_int($importBatch['total'] ?? null) ||
      $importBatch['total']<1 || $importBatch['total']>200 || $importBatch['index']<0 || $importBatch['index'] >= $importBatch['total'])
      throw new WebError('El lote de biblioteca no es válido.');
    $batchKey = $user . ':' . $importBatch['id'];
    foreach ($_SESSION['library_imports'] ?? [] as $key=>$flow)
      if ($flow['expires'] < time()) unset($_SESSION['library_imports'][$key]);
    $flow = $_SESSION['library_imports'][$batchKey] ?? null;
    if (!$flow) {
      if ($importBatch['index'] !== 0) throw new WebError('Vuelve a seleccionar la copia para iniciar la importación.',409);
      rate($db, 'library-import:' . $user, 5, 300);
      $flow = ['next'=>0,'total'=>$importBatch['total'],'expires'=>time()+1800];
      $_SESSION['library_imports'][$batchKey] = $flow;
    }
    if ($flow['total'] !== $importBatch['total'] || $importBatch['index'] > $flow['next'])
      throw new WebError('Los bloques deben importarse en orden.',409);
    rate($db, 'library-import-parts:' . $user, 200, 300);
  }
  $library = $input['library'] ?? null;
  if (
    !is_array($library) ||
    ($library['format'] ?? '') !== 'seasonav1.library/v1' ||
    !is_array($library['entries'] ?? null) ||
    !is_array($library['watched'] ?? null) ||
    count($library['entries']) > 5000 ||
    count($library['watched']) > 50000
  ) {
    throw new WebError(
      'Usa un JSON de biblioteca YomaTV válido (hasta 5.000 animes y 50.000 capítulos vistos).',
    );
  }
  $entries = [];
  $watched = [];
  $slugs = [];
  foreach ($library['entries'] as $entry) {
    if (
      !is_array($entry) ||
      !is_string($entry['slug'] ?? null) ||
      !preg_match('/^[A-Za-z0-9_-]{1,240}$/', $entry['slug']) ||
      !in_array(
        $entry['status'] ?? '',
        ['watching', 'planned', 'completed', 'paused', 'dropped'],
        true,
      ) ||
      !is_bool($entry['favorite'] ?? null) ||
      !is_bool($entry['excluded'] ?? null) ||
      !is_int($entry['score'] ?? null) ||
      $entry['score'] < 0 ||
      $entry['score'] > 10 ||
      !is_string($entry['notes'] ?? null) ||
      mb_strlen($entry['notes']) > 2000
    ) {
      throw new WebError(
        'Una ficha de la biblioteca tiene datos inválidos. No se importó ningún cambio.',
      );
    }
    $slug = $entry['slug'];
    $entries[$slug] = [
      'user_id' => $user,
      'slug' => $slug,
      'status' => $entry['status'],
      'favorite' => (int) $entry['favorite'],
      'excluded' => (int) $entry['excluded'],
      'score' => $entry['score'],
      'notes' => $entry['notes'],
    ];
    $slugs[$slug] = true;
  }
  foreach ($library['watched'] as $episode) {
    if (
      !is_array($episode) ||
      !is_string($episode['slug'] ?? null) ||
      !preg_match('/^[A-Za-z0-9_-]{1,240}$/', $episode['slug']) ||
      !is_string($episode['number'] ?? null) ||
      !preg_match('/^\d{1,5}(?:\.\d{1,4})?$/', $episode['number'])
    ) {
      throw new WebError(
        'Un capítulo visto tiene datos inválidos. No se importó ningún cambio.',
      );
    }
    $stamp = $episode['watched_at'] ?? time();
    if (!is_int($stamp) || $stamp < 1 || $stamp > time() + 600) {
      throw new WebError('La fecha de un capítulo visto no es válida.');
    }
    $number = episode_number($episode['number']);
    $watched[$episode['slug'] . '/' . $number] = [
      'slug' => $episode['slug'],
      'number' => $number,
      'watched_at' => $stamp,
    ];
    $slugs[$episode['slug']] = true;
  }
  $known = [];
  $episodeIds = [];
  foreach (array_chunk(array_keys($slugs), 100) as $chunkSlugs) {
    $marks = implode(',', array_fill(0, count($chunkSlugs), '?'));
    foreach (
      sql(
        $db,
        "SELECT slug FROM sa1_anime WHERE slug IN ($marks)",
        $chunkSlugs,
      )->fetchAll()
      as $row
    ) {
      $known[$row['slug']] = true;
    }
    foreach (
      sql(
        $db,
        "SELECT id,slug,number FROM sa1_episodes WHERE slug IN ($marks)",
        $chunkSlugs,
      )->fetchAll()
      as $row
    ) {
      $episodeIds[$row['slug'] . '/' . $row['number']] = (int) $row['id'];
    }
  }
  $rows = array_values(
    array_filter($entries, fn($entry) => isset($known[$entry['slug']])),
  );
  $seen = [];
  foreach ($watched as $key => $episode) {
    if (!isset($episodeIds[$key])) {
      continue;
    }
    $seen[] = [
      'user_id' => $user,
      'episode_id' => $episodeIds[$key],
      'watched_at' => $episode['watched_at'],
    ];
    // Watched entries remain visible in the personal library, even without a follow entry.
    if (
      !isset($entries[$episode['slug']]) &&
      !sql($db, 'SELECT slug FROM sa1_follow WHERE user_id=? AND slug=?', [
        $user,
        $episode['slug'],
      ])->fetchColumn()
    ) {
      $entries[$episode['slug']] = [
        'user_id' => $user,
        'slug' => $episode['slug'],
        'status' => 'watching',
        'favorite' => 0,
        'excluded' => 0,
        'score' => 0,
        'notes' => '',
      ];
      $rows[] = $entries[$episode['slug']];
    }
  }
  $extra=personal_import_validate($db,$library['extras']??[]);
  $db->beginTransaction();
  try {
    upsert(
      $db,
      'sa1_follow',
      ['user_id', 'slug', 'status', 'favorite', 'excluded', 'score', 'notes'],
      $rows,
      ['user_id', 'slug'],
      ['status', 'favorite', 'excluded', 'score', 'notes'],
    );
    upsert(
      $db,
      'sa1_watched',
      ['user_id', 'episode_id', 'watched_at'],
      $seen,
      ['user_id', 'episode_id'],
      ['watched_at'],
    );
    personal_import_apply($db,$extra);
    $event = log_event(
      $db,
      $user,
      'Biblioteca importada: ' .
        count($rows) .
        ' animes y ' .
        count($seen) .
        ' capítulos vistos.',
    );
    $db->commit();
  } catch (Throwable $error) {
    $db->rollBack();
    throw $error;
  }
  $skippedAnime = count(array_diff_key($slugs, $known));
  if ($importBatch !== null) $_SESSION['library_imports'][$batchKey]['next'] = max($flow['next'], $importBatch['index']+1);
  $skippedEpisodes = count($watched) - count($seen);
  return [
    'message' =>
      count($rows) .
      ' animes y ' .
      count($seen) .
      ' capítulos vistos importados.',
    'imported' => [
      'anime' => count($rows),
      'watched' => count($seen),
      'unknown_anime' => $skippedAnime,
      'unknown_episodes' => $skippedEpisodes,
    ],
    'patch' => state_patch(
      $db,
      array_keys($known),
      [],
      ['history' => [$event]],
    ),
  ];
}
