<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function dispatch_sync(PDO $db, string $action, array $input): ?array
{
  if ($action === 'sync') {
    $user = admin_member($db);
    rate($db, 'schedule-sync', 1, 120);
    $count = sync_schedule($db);
    $event = log_event(
      $db,
      $user,
      'Horario actualizado: ' . $count . ' animes.',
    );
    return [
      'message' => 'Horario actualizado desde AnimeAV1.',
      'patch' => state_patch(
        $db,
        [],
        [],
        ['refresh_anime' => true, 'catalog' => true, 'history' => [$event]],
      ),
    ];
  }
  if ($action === 'sync_catalog') {
    admin_member($db);
    rate($db, 'directory-sync', 1, 2);
    $page = max(1, min(9999, (int) ($input['page'] ?? 1)));
    $progress = sync_directory_page($db, $page);
    return [
      'progress' => $progress,
      'catalog' => catalog($db, []),
      'message' => 'Página del catálogo actualizada.',
    ];
  }
  if ($action === 'sync_anime') {
    admin_member($db);
    $slug = (string) ($input['slug'] ?? '');
    find_anime($db, $slug);
    rate($db, 'anime:' . $slug, 1, 60);
    sync_anime($db, $slug);
    return [
      'message' => 'Capítulos actualizados.',
      'detail' => detail($db, $slug),
      'patch' => state_patch($db, [$slug]),
    ];
  }
  if ($action === 'mirrors') {
    member();
    $episode = sql($db, 'SELECT * FROM sa1_episodes WHERE id=?', [
      (int) ($input['episode_id'] ?? 0),
    ])->fetch();
    if (!$episode) {
      throw new WebError('Capítulo no encontrado.', 404);
    }
    if ((int) $episode['mirrors_at'] <= time() - 1800) {
      admin_member($db);
    }
    rate($db, 'mirrors:' . $episode['id'], 5, 60);
    return ['mirrors' => episode_mirrors($db, $episode), 'episode' => $episode];
  }
  return null;
}
