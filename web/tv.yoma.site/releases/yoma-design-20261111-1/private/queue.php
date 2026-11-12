<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function queue_summary(PDO $db, ?array $slugs = null): array
{
  $args = [uid()]; $filter = '';
  if ($slugs !== null) {
    if (!$slugs) return [];
    $filter = ' AND e.slug IN (' . implode(',', array_fill(0,count($slugs),'?')) . ')';
    array_push($args, ...$slugs);
  }
  $rows = sql($db, "SELECT e.slug,a.title,a.cover,COUNT(*) AS total,MAX(j.id) AS last_id,
    SUM(CASE WHEN j.status IN ('pending','exported') THEN 1 ELSE 0 END) AS queued,
    SUM(CASE WHEN j.status='confirmed' THEN 1 ELSE 0 END) AS confirmed,
    SUM(CASE WHEN j.status='cancelled' THEN 1 ELSE 0 END) AS cancelled,
    SUM(CASE WHEN j.status IN ('pending','exported') AND EXISTS(SELECT 1 FROM sa1_job_events ev WHERE ev.user_id=j.user_id AND ev.job_id=j.id AND ev.state='failed' AND ev.updated_at=(SELECT MAX(ev2.updated_at) FROM sa1_job_events ev2 WHERE ev2.user_id=j.user_id AND ev2.job_id=j.id)) THEN 1 ELSE 0 END) AS failed,
    GROUP_CONCAT(DISTINCT j.language) AS languages
    FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id JOIN sa1_anime a ON a.slug=e.slug
    WHERE j.user_id=?" . $filter . ' GROUP BY e.slug,a.title,a.cover ORDER BY last_id DESC', $args)->fetchAll();
  foreach ($rows as &$row) {
    foreach (['total','last_id','queued','confirmed','cancelled','failed'] as $key) $row[$key] = (int)$row[$key];
    $row['languages'] = explode(',', $row['languages']);
  }
  return $rows;
}

function queue_totals(PDO $db): array
{
  $r = sql($db, "SELECT COUNT(*) AS total,SUM(CASE WHEN status IN ('pending','exported') THEN 1 ELSE 0 END) AS queued,
    SUM(CASE WHEN status='confirmed' THEN 1 ELSE 0 END) AS confirmed,SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) AS cancelled
    FROM sa1_jobs WHERE user_id=?", [uid()])->fetch();
  return array_map('intval', $r);
}

function queue_history(PDO $db, array $input): array
{
  member();
  $slug = (string)($input['slug'] ?? '');
  if($slug!=='')find_anime($db, $slug);
  $cursor = max(0,(int)($input['before'] ?? 0));
  $args = [uid()];
  $condition=$slug!==''?' AND e.slug=?':'';if($slug!=='')$args[]=$slug;
  if(($input['active']??'')==='1')$condition.=" AND j.status IN ('pending','exported')";
  $condition .= $cursor ? ' AND j.id<?' : '';
  if ($cursor) $args[] = $cursor;
  $rows = sql($db, 'SELECT j.*,e.slug,e.number,a.title,a.cover FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id JOIN sa1_anime a ON a.slug=e.slug
    WHERE j.user_id=?' . $condition . ' ORDER BY j.id DESC LIMIT 201', $args)->fetchAll();
  $more = count($rows)>200;
  $rows = array_slice($rows,0,200);
  return ['queue_history'=>['slug'=>$slug,'user_id'=>uid(),'items'=>$rows,'next_before'=>$more?(int)end($rows)['id']:0],
    'patch'=>['user_id'=>uid(),'revision'=>microtime(true),'jobs'=>$rows,'queue_summary'=>queue_summary($db,$slug!==''?[$slug]:null),'queue_totals'=>queue_totals($db)]];
}

function dispatch_queue(PDO $db, string $action, array $input): ?array
{
  if (!in_array($action, ['queue', 'cancel_job', 'export', 'receipt'], true)) {
    return null;
  }
  $user = member();
  if ($action === 'queue') {
    $settings = preferences($db, $user);
    $slugs = $input['slugs'] ?? [];
    $mode = $input['mode'] ?? 'latest';
    if (
      !is_array($slugs) ||
      !$slugs ||
      count($slugs) > 100 ||
      !in_array($mode, ['latest', 'all', 'selected'], true)
    ) {
      throw new WebError('Selecciona animes y capítulos.');
    }
    $wanted = [];
    foreach (array_unique($slugs) as $slug) {
      $a = find_anime($db, (string) $slug);
      if ($mode === 'latest' && !$a['catalog_complete'] && !$a['latest']) {
        admin_member($db);
        sync_anime($db, (string) $slug);
        $a = find_anime($db, (string) $slug);
      }
      $f = sql(
        $db,
        'SELECT excluded FROM sa1_follow WHERE user_id=? AND slug=?',
        [$user, $slug],
      )->fetchColumn();
      if ($f) {
        continue;
      }
      if ($mode === 'all' && !$a['catalog_complete']) {
        throw new WebError(
          'Actualiza el listado de capítulos de «' .
            $a['title'] .
            '» antes de preparar todos.',
        );
      }
      $eps = sql(
        $db,
        'SELECT * FROM sa1_episodes WHERE slug=? ORDER BY number_value',
        [$slug],
      )->fetchAll();
      foreach ($eps as $ep) {
        if ($mode === 'latest' && $ep['number'] !== $a['latest']) {
          continue;
        }
        if (
          $mode === 'selected' &&
          !in_array(
            (int) $ep['id'],
            array_map('intval', $input['episode_ids'] ?? []),
            true,
          )
        ) {
          continue;
        }
        $wanted[] = $ep;
      }
    }
    if (count($wanted) > 2000) {
      throw new WebError('Prepara hasta 2.000 capítulos por lote.');
    }
    $added = 0;
    $queueIds = [];
    $db->beginTransaction();
    try {
      foreach ($wanted as $ep) {
        $old = sql(
          $db,
          'SELECT id,status FROM sa1_jobs WHERE user_id=? AND episode_id=? AND language=?',
          [$user, $ep['id'], $settings['language']],
        )->fetch();
        if ($old && $old['status'] !== 'cancelled') {
          if (in_array($old['status'], ['pending', 'exported'], true)) {
            $queueIds[] = (int) $old['id'];
          }
          continue;
        }
        if ($old) {
          sql(
            $db,
            "UPDATE sa1_jobs SET status='pending',server=?,height=?,added_at=?,exported_at=NULL WHERE id=?",
            [$settings['server'], $settings['height'], time(), $old['id']],
          );
        } else {
          sql(
            $db,
            'INSERT INTO sa1_jobs(user_id,episode_id,language,server,height,status,added_at) VALUES(?,?,?,?,?,?,?)',
            [
              $user,
              $ep['id'],
              $settings['language'],
              $settings['server'],
              $settings['height'],
              'pending',
              time(),
            ],
          );
        }
        $queueIds[] = $old ? (int) $old['id'] : (int) $db->lastInsertId();
        $added++;
      }
      $event = log_event(
        $db,
        $user,
        $added . ' capítulos preparados para YomaTV.',
      );
      $db->commit();
    } catch (Throwable $e) {
      $db->rollBack();
      throw $e;
    }
    return [
      'message' => $added
        ? $added . ' capítulos añadidos a tu cola.'
        : 'Los capítulos ya estaban en la cola o confirmados.',
      'queue_ids' => array_values(array_unique($queueIds)),
      'patch' => state_patch($db, $slugs, $queueIds, ['history' => [$event]]),
    ];
  }
  if ($action === 'cancel_job') {
    sql(
      $db,
      "UPDATE sa1_jobs SET status='cancelled' WHERE id=? AND user_id=? AND status IN ('pending','exported')",
      [(int) ($input['id'] ?? 0), $user],
    );
    return [
      'message' => 'Solicitud retirada de la lista web.',
      'patch' => state_patch($db, [], [(int) ($input['id'] ?? 0)]),
    ];
  }
  if ($action === 'export') {
    $settings = preferences($db, $user);
    $filter = '';
    $args = [$user, $settings['language']];
    if (array_key_exists('job_ids', $input)) {
      $ids = $input['job_ids'];
      if (!is_array($ids) || !$ids || count($ids) > 2000) {
        throw new WebError('Elige entre 1 y 2.000 solicitudes.');
      }
      foreach ($ids as $id) {
        if (!is_int($id) || $id < 1) {
          throw new WebError('Identificador de solicitud inválido.');
        }
      }
      $ids = array_values(array_unique($ids));
      $filter =
        ' AND j.id IN (' . implode(',', array_fill(0, count($ids), '?')) . ')';
      $args = array_merge($args, $ids);
    }
    $jobs = sql(
      $db,
      "SELECT j.id AS web_id,e.slug,e.number,e.url,a.title,a.weekday,a.start_date,COALESCE(v.revision,'') AS request_revision FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id JOIN sa1_anime a ON a.slug=e.slug LEFT JOIN sa1_job_runs v ON v.job_id=j.id WHERE j.user_id=? AND j.language=? AND j.status IN ('pending','exported')" .
        $filter .
        ' ORDER BY a.weekday,a.slug,e.number_value',
      $args,
    )->fetchAll();
    if (!$jobs) {
      throw new WebError('No hay capítulos preparados en el idioma elegido.');
    }
    if (count($jobs) > 2000) {
      throw new WebError(
        'Envía como máximo 2.000 capítulos por lote desde sus fichas.',
      );
    }
    $favorites = [];
    $exclusions = [];
    foreach (
      sql(
        $db,
        'SELECT slug,favorite,excluded FROM sa1_follow WHERE user_id=?',
        [$user],
      )->fetchAll()
      as $f
    ) {
      if ($f['favorite']) {
        $favorites[] = $f['slug'];
      }
      if ($f['excluded']) {
        $exclusions[] = $f['slug'];
      }
    }
    $settings['favorites'] = $favorites;
    $settings['exclusions'] = $exclusions;
    $plan = [
      'format' => 'seasonav1.web-plan/v1',
      'plan_id' => bin2hex(random_bytes(12)),
      'installation' => meta($db, 'installation'),
      'created_at' => date(DATE_ATOM),
      'preferences' => $settings,
      'items' => array_map(
        fn($j) => array_replace($j, [
          'web_id' => (int) $j['web_id'],
          'request_revision'=>(string)$j['request_revision'],
          'weekday' => max(1, (int) $j['weekday']),
          'language' => $settings['language'],
        ]),
        $jobs,
      ),
    ];
    $jobIds = array_column($jobs, 'web_id');
    $marks = implode(',', array_fill(0, count($jobIds), '?'));
    $db->beginTransaction();
    try {
      sql(
        $db,
        "UPDATE sa1_jobs SET status='exported',exported_at=? WHERE user_id=? AND id IN ($marks)",
        array_merge([time(), $user], $jobIds),
      );
      $event = log_event(
        $db,
        $user,
        'Cola exportada: ' . count($jobs) . ' capítulos para tu PC.',
      );
      $db->commit();
    } catch (Throwable $e) {
      $db->rollBack();
      throw $e;
    }
    return [
      'plan' => $plan,
      'message' => 'Cola lista. Impórtala en YomaTV para descargar.',
      'patch' => state_patch($db, [], $jobIds, ['history' => [$event]]),
    ];
  }
  if ($action === 'receipt') {
    $receipt = $input['receipt'] ?? [];
    if (
      ($receipt['format'] ?? '') !== 'seasonav1.web-results/v1' ||
      !is_array($receipt['plans'] ?? null) ||
      count($receipt['plans']) > 100
    ) {
      throw new WebError('El archivo no es un resultado de YomaTV.');
    }
    $changed = 0;
    $changedIds = [];
    $event = null;
    $db->beginTransaction();
    try {
      foreach ($receipt['plans'] as $plan) {
        if (($plan['installation'] ?? '') !== meta($db, 'installation')) {
          continue;
        }
        if (count($plan['items'] ?? []) > 2000) {
          throw new WebError('El resultado excede el tamaño permitido.');
        }
        foreach ($plan['items'] ?? [] as $j) {
          if (($j['status'] ?? '') !== 'completed') {
            continue;
          }
          if (
            !preg_match('/^[a-f0-9]{64}$/', $j['sha256'] ?? '') ||
            (int) ($j['bytes'] ?? 0) < 1024
          ) {
            throw new WebError(
              'El resultado contiene un capítulo sin verificación válida.',
            );
          }
          $old = sql(
            $db,
            "SELECT j.*,e.slug,e.number,COALESCE(v.revision,'') AS request_revision FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id LEFT JOIN sa1_job_runs v ON v.job_id=j.id WHERE j.id=? AND j.user_id=?",
            [(int) ($j['web_id'] ?? 0), $user],
          )->fetch();
          if (
            !$old ||
            $old['slug'] !== ($j['slug'] ?? '') ||
            $old['number'] !== ($j['number'] ?? '') ||
            $old['language'] !== ($j['language'] ?? '') ||
            $old['status'] === 'confirmed' ||
            (string)$old['request_revision'] !== (string)($j['request_revision']??'')
          ) {
            continue;
          }
          sql(
            $db,
            "UPDATE sa1_jobs SET status='confirmed',confirmed_at=?,bytes=?,sha256=? WHERE id=? AND user_id=?",
            [time(), (int) $j['bytes'], $j['sha256'], $old['id'], $user],
          );
          $changed++;
          $changedIds[] = (int) $old['id'];
        }
      }
      if ($changed) {
        $event = log_event(
          $db,
          $user,
          $changed . ' descargas confirmadas por tu PC.',
        );
      }
      $db->commit();
    } catch (Throwable $e) {
      $db->rollBack();
      throw $e;
    }
    return [
      'message' => $changed . ' descargas confirmadas.',
      'patch' => state_patch($db, [], $changedIds, [
        'history' => $event ? [$event] : [],
      ]),
    ];
  }
  return null;
}
