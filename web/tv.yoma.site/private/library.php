<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function dispatch_library(PDO $db, string $action, array $input): ?array
{
  if (!in_array($action, ['follow', 'unfollow', 'watched', 'settings'], true)) {
    return null;
  }
  $user = member();
  if ($action === 'follow') {
    $slug = (string) ($input['slug'] ?? '');
    find_anime($db, $slug);
    $f = sql($db, 'SELECT * FROM sa1_follow WHERE user_id=? AND slug=?', [
      $user,
      $slug,
    ])->fetch() ?: [
      'user_id' => $user,
      'slug' => $slug,
      'status' => 'watching',
      'favorite' => 0,
      'excluded' => 0,
      'score' => 0,
      'notes' => '',
    ];
    foreach (['status', 'favorite', 'excluded', 'score', 'notes'] as $key) {
      if (array_key_exists($key, $input)) {
        $f[$key] = $input[$key];
      }
    }
    if (
      !in_array(
        $f['status'],
        ['watching', 'planned', 'completed', 'paused', 'dropped'],
        true,
      ) ||
      (int) $f['score'] < 0 ||
      (int) $f['score'] > 10 ||
      mb_strlen((string) $f['notes']) > 2000
    ) {
      throw new WebError('Revisa el estado, la nota y los comentarios.');
    }
    $f['favorite'] = (int) (bool) $f['favorite'];
    $f['excluded'] = (int) (bool) $f['excluded'];
    $f['score'] = (int) $f['score'];
    upsert(
      $db,
      'sa1_follow',
      array_keys($f),
      [$f],
      ['user_id', 'slug'],
      ['status', 'favorite', 'excluded', 'score', 'notes'],
    );
    calendar_refresh_feeds($db,$user);
    return [
      'message' => 'Biblioteca actualizada.',
      'patch' => state_patch($db, [$slug]),
    ];
  }
  if ($action === 'unfollow') {
    sql($db, 'DELETE FROM sa1_follow WHERE user_id=? AND slug=?', [
      $user,
      (string) ($input['slug'] ?? ''),
    ]);
    calendar_refresh_feeds($db,$user);
    return [
      'message' => 'Anime retirado de tu biblioteca.',
      'patch' => state_patch($db, [(string) ($input['slug'] ?? '')]),
    ];
  }
  if ($action === 'watched') {
    $id = (int) ($input['episode_id'] ?? 0);
    $ep = sql($db, 'SELECT * FROM sa1_episodes WHERE id=?', [$id])->fetch();
    if (!$ep) {
      throw new WebError('Capítulo no encontrado.', 404);
    }
    $policy=watch_mode($db,$ep['slug']);
    if(isset($input['progress_revision'])&&$input['progress_revision']!==$policy['revision'])throw new WebError('El modo cambió. Reabre la ficha.',409);
    if($policy['mode']==='rewatch'){
      if(!empty($input['watched']))upsert($db,'sa1_rewatched',['user_id','episode_id','run_id','watched_at'],[['user_id'=>$user,'episode_id'=>$id,'run_id'=>$policy['revision'],'watched_at'=>time()]],['user_id','episode_id','run_id'],['watched_at']);
      else sql($db,'DELETE FROM sa1_rewatched WHERE user_id=? AND episode_id=? AND run_id=?',[$user,$id,$policy['revision']]);
      return ['message'=>'Revisionado actualizado; el progreso original y MAL se conservan.','patch'=>state_patch($db,[$ep['slug']]),'detail'=>detail($db,$ep['slug'])];
    }
    if (!empty($input['watched'])) {
      upsert(
        $db,
        'sa1_watched',
        ['user_id', 'episode_id', 'watched_at'],
        [['user_id' => $user, 'episode_id' => $id, 'watched_at' => time()]],
        ['user_id', 'episode_id'],
        ['watched_at'],
      );
      $f = sql($db, 'SELECT slug FROM sa1_follow WHERE user_id=? AND slug=?', [
        $user,
        $ep['slug'],
      ])->fetch();
      if (!$f) {
        upsert(
          $db,
          'sa1_follow',
          [
            'user_id',
            'slug',
            'status',
            'favorite',
            'excluded',
            'score',
            'notes',
          ],
          [
            [
              'user_id' => $user,
              'slug' => $ep['slug'],
              'status' => 'watching',
              'favorite' => 0,
              'excluded' => 0,
              'score' => 0,
              'notes' => '',
            ],
          ],
          ['user_id', 'slug'],
          ['status'],
        );
      }
    } else {
      sql($db, 'DELETE FROM sa1_watched WHERE user_id=? AND episode_id=?', [
        $user,
        $id,
      ]);
    }
    return [
      'patch' => state_patch($db, [$ep['slug']]),
      'detail' => detail($db, $ep['slug']),
    ];
  }
  if ($action === 'settings') {
    $p = valid_preferences($input);
    upsert(
      $db,
      'sa1_preferences',
      ['user_id', 'settings'],
      [['user_id' => $user, 'settings' => json_encode($p)]],
      ['user_id'],
      ['settings'],
    );
    $event = log_event(
      $db,
      $user,
      'Preferencias guardadas para sincronizar con AnimeAV1 Plus.',
    );
    return [
      'message' => 'Preferencias guardadas.',
      'patch' => state_patch(
        $db,
        [],
        [],
        ['settings' => true, 'refresh_anime' => true, 'history' => [$event]],
      ),
    ];
  }
  return null;
}
