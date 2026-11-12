<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function state(PDO $db, bool $legacy = false): array
{
  $user = uid()
    ? sql($db, 'SELECT id,name,email FROM sa1_users WHERE id=?', [
      uid(),
    ])->fetch()
    : null;
  if (!$user) {
    unset($_SESSION['user_id']);
    $user = null;
  } else {
    $user['id'] = (int) $user['id'];
    $user['is_admin'] = administrator($db);
  }
  $anime = decorate_anime(
    $db,
    sql(
      $db,
      'SELECT a.* FROM sa1_anime a WHERE a.active=1 OR EXISTS(SELECT 1 FROM sa1_follow f WHERE f.slug=a.slug AND f.user_id=?) OR EXISTS(SELECT 1 FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id WHERE e.slug=a.slug AND j.user_id=?) ORDER BY active DESC,weekday,title',
      [uid(), uid()],
    )->fetchAll(),
  );
  $jobs = sql(
    $db,
    "SELECT j.*,e.slug,e.number,a.title,a.cover FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id JOIN sa1_anime a ON a.slug=e.slug WHERE j.user_id=? AND j.status IN ('pending','exported') ORDER BY j.added_at DESC,j.id DESC LIMIT 80",
    [uid()],
  )->fetchAll();
  $jobs = array_merge($jobs, sql($db, "SELECT j.*,e.slug,e.number,a.title,a.cover FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id JOIN sa1_anime a ON a.slug=e.slug WHERE j.user_id=? AND j.status NOT IN ('pending','exported') ORDER BY j.added_at DESC,j.id DESC LIMIT 80", [uid()])->fetchAll());
  if ($legacy) $jobs = sql($db, 'SELECT j.*,e.slug,e.number,a.title,a.cover FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id JOIN sa1_anime a ON a.slug=e.slug WHERE j.user_id=? ORDER BY j.added_at DESC,j.id DESC', [uid()])->fetchAll();
  $history = sql(
    $db,
    'SELECT id,level,message,created_at FROM sa1_history WHERE user_id=? ORDER BY id DESC LIMIT 80',
    [uid()],
  )->fetchAll();
  return [
    'revision' => microtime(true),
    'csrf' => $_SESSION['csrf'],
    'user' => $user,
    'anime' => $anime,
    'jobs' => $jobs,
    'queue_summary' => queue_summary($db),
    'queue_totals' => queue_totals($db),
    'history' => $history,
    'settings' => preferences($db, uid()),
    'preferences_saved' => (bool) sql(
      $db,
      'SELECT user_id FROM sa1_preferences WHERE user_id=?',
      [uid()],
    )->fetchColumn(),
    'updated_at' => (int) meta($db, 'catalog_updated', '0'),
    'today' => (int) date('N'),
    'season' => season_name(),
    'installation' => meta($db, 'installation'),
  ];
}

function state_patch(
  PDO $db,
  array $slugs = [],
  array $jobIds = [],
  array $options = [],
): array {
  $patch = [
    'revision' => microtime(true),
    'user_id' => uid(),
    'csrf' => $_SESSION['csrf'],
    'anime' => [],
    'jobs' => [],
    'history' => [],
    'removed_anime' => [],
  ];
  $jobIds = array_values(array_unique(array_map('intval', $jobIds)));
  $queueSlugs = [];
  foreach (array_chunk($jobIds, 100) as $batch) {
    $marks = implode(',', array_fill(0, count($batch), '?'));
    $rows = sql(
      $db,
      "SELECT j.*,e.slug,e.number,a.title,a.cover FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id JOIN sa1_anime a ON a.slug=e.slug WHERE j.user_id=? AND j.id IN ($marks)",
      array_merge([uid()], $batch),
    )->fetchAll();
    foreach ($rows as $row) {
      $row['id'] = (int) $row['id'];
      $patch['jobs'][] = $row;
      $slugs[] = $row['slug'];
      $queueSlugs[] = $row['slug'];
    }
  }
  if ($jobIds) {
    $patch['queue_summary'] = queue_summary($db, array_values(array_unique($queueSlugs)));
    $patch['queue_totals'] = queue_totals($db);
  }
  if (!empty($options['refresh_anime'])) {
    $rows = sql(
      $db,
      'SELECT a.* FROM sa1_anime a WHERE a.active=1 OR EXISTS(SELECT 1 FROM sa1_follow f WHERE f.slug=a.slug AND f.user_id=?) OR EXISTS(SELECT 1 FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id WHERE e.slug=a.slug AND j.user_id=?)',
      [uid(), uid()],
    )->fetchAll();
    $patch['anime'] = decorate_anime($db, $rows);
    $patch['replace_anime'] = true;
  } else {
    foreach (array_chunk(array_values(array_unique($slugs)), 100) as $batch) {
      $marks = implode(',', array_fill(0, count($batch), '?'));
      $rows = decorate_anime(
        $db,
        sql(
          $db,
          "SELECT * FROM sa1_anime WHERE slug IN ($marks)",
          $batch,
        )->fetchAll(),
      );
      foreach ($rows as $row) {
        $hasJobs = sql(
          $db,
          'SELECT j.id FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id WHERE j.user_id=? AND e.slug=? LIMIT 1',
          [uid(), $row['slug']],
        )->fetchColumn();
        if ($row['active'] || $row['status'] !== 'none' || $hasJobs) {
          $patch['anime'][] = $row;
        } else {
          $patch['removed_anime'][] = $row['slug'];
          $patch['personal_updates'][] = $row;
        }
      }
    }
  }
  foreach (array_chunk($options['history'] ?? [], 100) as $batch) {
    if (!$batch) {
      continue;
    }
    $marks = implode(',', array_fill(0, count($batch), '?'));
    array_push(
      $patch['history'],
      ...sql(
        $db,
        "SELECT id,level,message,created_at FROM sa1_history WHERE user_id=? AND id IN ($marks)",
        array_merge([uid()], $batch),
      )->fetchAll(),
    );
  }
  if (!empty($options['settings'])) {
    $patch['settings'] = preferences($db, uid());
    $patch['preferences_saved'] = true;
  }
  if (!empty($options['catalog'])) {
    $patch['updated_at'] = (int) meta($db, 'catalog_updated', '0');
  }
  return $patch;
}
