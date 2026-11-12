<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function watch_sync_pending(PDO $db): array
{
  if (!uid()) {
    return ['count' => 0, 'next_retry' => 0];
  }
  // A newly connected account or confirmed title can resume its own waiting marks.
  sql(
    $db,
    "UPDATE sa1_watch_sync SET state='pending',next_retry=0 WHERE user_id=? AND state='blocked' AND error_kind IN ('unlinked','not_connected','unconfirmed') AND EXISTS(SELECT 1 FROM sa1_mal_links k WHERE k.user_id=sa1_watch_sync.user_id AND k.slug=sa1_watch_sync.slug AND k.confirmed=1 AND (sa1_watch_sync.mal_id=0 OR sa1_watch_sync.mal_id=k.mal_id) AND NOT EXISTS(SELECT 1 FROM sa1_mal_removed r WHERE r.user_id=k.user_id AND r.mal_account_id=sa1_watch_sync.mal_account_id AND r.mal_id=k.mal_id)) AND EXISTS(SELECT 1 FROM sa1_mal_connections c WHERE c.user_id=sa1_watch_sync.user_id AND c.needs_auth=0 AND (sa1_watch_sync.mal_account_id=0 OR sa1_watch_sync.mal_account_id=c.mal_user_id))",
    [uid()],
  );
  $r = sql(
    $db,
    "SELECT COUNT(*) AS n,MIN(CASE WHEN lock_until>next_retry THEN lock_until ELSE next_retry END) AS retry FROM sa1_watch_sync WHERE user_id=? AND state='pending'",
    [uid()],
  )->fetch();
  return ['count' => (int) $r['n'], 'next_retry' => (int) ($r['retry'] ?? 0)];
}
function watch_sync_result(PDO $db, string $slug): array
{
  $r = sql(
    $db,
    'SELECT state,error_kind,next_retry,lock_until,target FROM sa1_watch_sync WHERE user_id=? AND slug=?',
    [uid(), $slug],
  )->fetch();
  if (!$r) {
    return [
      'state' => 'idle',
      'message' => 'Se marcará al alcanzar el 80 % del video.',
    ];
  }
  $messages = [
      'corrected'=>'Envío cancelado por una corrección o un revisionado. Abre el capítulo de nuevo para retomar el seguimiento.',
    'account_changed' => 'Visto en la web. Este envío pertenece a otra cuenta de MAL y se ha detenido.',
    'identity_unknown' => 'Visto en la web. Este envío antiguo no tiene una cuenta MAL identificada; abre el capítulo de nuevo para autorizar su seguimiento.',
    'removed' => 'Visto en la web. Retiraste este anime de MAL; no se añadirá automáticamente. Puedes volver a añadirlo desde Editar en MAL.',
    'unconfirmed' => 'Visto en la web. Confirma la ficha MAL una vez antes de enviar progreso.',
    'unlinked' =>
      'Visto en la web. Vincula este anime con MAL para sincronizarlo.',
    'not_connected' =>
      'Visto en la web. Conecta MyAnimeList para sincronizarlo.',
    'link_changed' =>
      'El vínculo de MAL cambió. Revisa la ficha antes de sincronizar este capítulo.',
    'invalid_episode' =>
      'Visto en la web. Este capítulo especial no tiene un número compatible con MAL.',
    'outside_total' =>
      'Visto en la web. El número supera los capítulos de la ficha de MAL; revisa el vínculo.',
    'remote' =>
      'Visto en la web. MAL no responde; el cambio está guardado para reintentar.',
  ];
  return [
    'state' => $r['state'],
    'message' =>
      $r['state'] === 'synced'
        ? 'Visto en la web y confirmado en MyAnimeList.'
        : $messages[$r['error_kind']] ??
          'Visto en la web. Sincronización con MAL pendiente.',
    'next_retry' => max((int) $r['next_retry'], (int) $r['lock_until']),
    'target' => (int) $r['target'],
  ];
}
function watch_sync_queue(PDO $db, array $episode): void
{
  $id = (int) sql(
    $db,
    'SELECT mal_id FROM sa1_mal_links WHERE user_id=? AND slug=?',
    [uid(), $episode['slug']],
  )->fetchColumn();
  $number = (float) $episode['number_value'];
  $valid = $number >= 1 && $number <= 100000 && floor($number) === $number;
  $target = $valid ? (int) $number : 0;
  $account = mal_identity_id($db);
  $removed = $id && mal_is_removed($db, $account, $id);
  // Lock the existing row so concurrent tabs cannot replace a higher pending target.
  $db->beginTransaction();
  try {
    $suffix =
      $db->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql' ? ' FOR UPDATE' : '';
    $old = sql(
      $db,
      'SELECT * FROM sa1_watch_sync WHERE user_id=? AND slug=?' . $suffix,
      [uid(), $episode['slug']],
    )->fetch();
    if ($valid && $old &&
      ($old['state'] === 'pending' || ($old['state'] === 'blocked' && in_array($old['error_kind'], ['unlinked','not_connected','unconfirmed'], true))) &&
      ((int)$old['mal_id'] === $id || (int)$old['mal_id'] === 0) &&
      ((int)$old['mal_account_id'] === $account || (int)$old['mal_account_id'] === 0)) {
      $target = max($target, (int) $old['target']);
    }
    upsert(
      $db,
      'sa1_watch_sync',
      [
        'user_id',
        'slug',
        'mal_id',
        'mal_account_id',
        'target',
        'generation',
        'state',
        'attempts',
        'next_retry',
        'lock_until',
        'error_kind',
        'updated_at',
      ],
      [
        [
          'user_id' => uid(),
          'slug' => $episode['slug'],
          'mal_id' => $id,
          'mal_account_id' => $account,
          'target' => $target,
          'generation' => bin2hex(random_bytes(16)),
          'state' => $valid && !$removed ? 'pending' : 'blocked',
          'attempts' => 0,
          'next_retry' => 0,
          'lock_until' => (int) ($old['lock_until'] ?? 0),
          'error_kind' => $removed ? 'removed' : ($valid ? '' : 'invalid_episode'),
          'updated_at' => time(),
        ],
      ],
      ['user_id', 'slug'],
      [
        'mal_id',
        'mal_account_id',
        'target',
        'generation',
        'state',
        'attempts',
        'next_retry',
        'error_kind',
        'updated_at',
      ],
    );
    $db->commit();
  } catch (Throwable $e) {
    $db->rollBack();
    throw $e;
  }
}
function watch_sync_attempt(PDO $db, string $slug): array
{
  $job = sql($db, 'SELECT * FROM sa1_watch_sync WHERE user_id=? AND slug=?', [
    uid(),
    $slug,
  ])->fetch();
  if (
    !$job ||
    $job['state'] !== 'pending' ||
    (int) $job['next_retry'] > time()
  ) {
    return watch_sync_result($db, $slug);
  }
  $lock = sql(
    $db,
    "UPDATE sa1_watch_sync SET lock_until=? WHERE user_id=? AND slug=? AND lock_until<=? AND generation=? AND state='pending'",
    [time() + 90, uid(), $slug, time(), $job['generation']],
  );
  if ($lock->rowCount() !== 1) {
    return watch_sync_result($db, $slug);
  }
  try {
    $account = mal_identity_id($db);
    $id = (int) sql(
      $db,
      'SELECT mal_id FROM sa1_mal_links WHERE user_id=? AND slug=?',
      [uid(), $slug],
    )->fetchColumn();
    $block = (int)$job['mal_account_id'] && (int)$job['mal_account_id'] !== $account
      ? 'account_changed' : (
      $id === 0
        ? 'unlinked'
        : ((int) $job['mal_id'] && (int) $job['mal_id'] !== $id
          ? 'link_changed'
          : ''));
    if (!$block && !(int)sql($db,'SELECT confirmed FROM sa1_mal_links WHERE user_id=? AND slug=? AND mal_id=?',[uid(),$slug,$id])->fetchColumn()) $block='unconfirmed';
    if (!$block && mal_is_removed($db, $account, $id)) $block = 'removed';
    if (!$block && !mal_status($db)['connected']) {
      $block = 'not_connected';
    }
    if ($block) {
      sql(
        $db,
        "UPDATE sa1_watch_sync SET state='blocked',error_kind=? WHERE user_id=? AND slug=? AND generation=?",
        [$block, uid(), $slug, $job['generation']],
      );
      return watch_sync_result($db, $slug);
    }
    // Read MAL now; never overwrite an already higher progress or the user's score.
    $node = mal_read($db, 'anime:' . $id, [
      'fields' => 'my_list_status,num_episodes',
    ], 'GET', $account);
    if ((int) ($node['id'] ?? 0) !== $id) {
      throw new MalRemoteError(502);
    }
    $remote = $node['my_list_status'] ?? null;
    $current = (int) ($remote['num_episodes_watched'] ?? 0);
    $target = max($current, (int) $job['target']);
    $total = (int) ($node['num_episodes'] ?? 0);
    if ($total > 0 && (int) $job['target'] > $total) {
      sql(
        $db,
        "UPDATE sa1_watch_sync SET state='blocked',error_kind='outside_total' WHERE user_id=? AND slug=? AND generation=?",
        [uid(), $slug, $job['generation']],
      );
      return watch_sync_result($db, $slug);
    }
    $status = $remote['status'] ?? 'watching';
    if (in_array($status, ['plan_to_watch', 'on_hold', 'dropped'], true)) {
      $status = 'watching';
    }
    if ($total > 0 && $target >= $total) {
      $status = 'completed';
    }
    if (
      (int) sql(
        $db,
        'SELECT mal_id FROM sa1_mal_links WHERE user_id=? AND slug=?',
        [uid(), $slug],
      )->fetchColumn() !== $id || !(int)sql($db,'SELECT confirmed FROM sa1_mal_links WHERE user_id=? AND slug=? AND mal_id=?',[uid(),$slug,$id])->fetchColumn()
    ) {
      sql(
        $db,
        "UPDATE sa1_watch_sync SET state='blocked',error_kind='link_changed' WHERE user_id=? AND slug=? AND generation=?",
        [uid(), $slug, $job['generation']],
      );
      return watch_sync_result($db, $slug);
    }
    if (!$remote || $target > $current || $status !== $remote['status']) {
      $currentJob = sql($db, 'SELECT generation,state FROM sa1_watch_sync WHERE user_id=? AND slug=?', [uid(), $slug])->fetch();
      if (!$currentJob || $currentJob['generation'] !== $job['generation'] || $currentJob['state'] !== 'pending' || mal_is_removed($db, $account, $id))
        return watch_sync_result($db, $slug);
      $remote = mal_read(
        $db,
        'list-status:' . $id,
        ['num_watched_episodes' => $target, 'status' => $status],
        'PATCH',
        $account,
      );
    }
    mal_assert_account($db, $account);
    if (
      !isset(
        $remote['num_episodes_watched'],
        $remote['status'],
        $remote['score'],
      ) ||
      (int) $remote['num_episodes_watched'] < $target
    ) {
      throw new MalRemoteError(502);
    }
    mal_cache_list($db, $node, $remote, 'api', 'edit');
    mal_copy_follow($db, $slug, $id);
    sql(
      $db,
      "UPDATE sa1_watch_sync SET mal_id=?,state=CASE WHEN target<=? THEN 'synced' ELSE 'pending' END,error_kind='',attempts=0,next_retry=0,updated_at=? WHERE user_id=? AND slug=? AND generation=?",
      [
        $id,
        (int) $remote['num_episodes_watched'],
        time(),
        uid(),
        $slug,
        $job['generation'],
      ],
    );
    log_event(
      $db,
      uid(),
      'Capítulo visto sincronizado con MAL: ' .
        $node['title'] .
        ' · ' .
        $job['target'] .
        '.',
    );
  } catch (MalRemoteError | WebError $e) {
    $attempts = (int) $job['attempts'] + 1;
    $wait = min(900, 30 * 2 ** min(5, $attempts - 1));
    sql(
      $db,
      "UPDATE sa1_watch_sync SET state='pending',attempts=?,next_retry=?,error_kind='remote' WHERE user_id=? AND slug=? AND generation=?",
      [$attempts, time() + $wait, uid(), $slug, $job['generation']],
    );
  } finally {
    sql(
      $db,
      'UPDATE sa1_watch_sync SET lock_until=0 WHERE user_id=? AND slug=? AND generation=?',
      [uid(), $slug, $job['generation']],
    );
  }
  return watch_sync_result($db, $slug);
}
function dispatch_watch_sync(PDO $db, string $action, array $input): ?array
{
  if (!in_array($action, ['watch_scrobble', 'watch_manual', 'watch_retry'], true)) {
    return null;
  }
  member();
  rate($db, 'watch-sync:' . uid(), 120, 3600);
  if ($action !== 'watch_retry') {
    $manual=$action==='watch_manual';
    if (!$manual) {
    $position = filter_var($input['position'] ?? null, FILTER_VALIDATE_FLOAT);
    $duration = filter_var($input['duration'] ?? null, FILTER_VALIDATE_FLOAT);
    if (
      $position === false ||
      $duration === false ||
      !is_finite($position) ||
      !is_finite($duration) ||
      $duration <= 0 ||
      $duration > 43200 ||
      $position < 0 ||
      $position > $duration + 1 ||
      $position / $duration < 0.8
    ) {
      throw new WebError(
        'El capítulo todavía no alcanzó el 80 % de su duración.',
      );
    }
    }
    $ep = sql($db, 'SELECT * FROM sa1_episodes WHERE id=?', [
      (int) ($input['episode_id'] ?? 0),
    ])->fetch();
    if (!$ep) {
      throw new WebError('Capítulo no encontrado.', 404);
    }
    $policy=watch_mode($db,$ep['slug']);
    if ((isset($input['progress_revision']) && $input['progress_revision']!==$policy['revision']) || (!isset($input['progress_revision']) && (int)$policy['changed_at']>0)) throw new WebError('El progreso o modo cambió. Reabre el reproductor antes de marcar este capítulo.',409);
    if($manual){
      if(($input['progress_revision']??null)!==$policy['revision'])throw new WebError('Reabre el capítulo antes de marcarlo en MyAnimeList.',409);
      $account=mal_identity_id($db);
      if(!$account)throw new WebError('Conecta tu cuenta de MyAnimeList antes de usar el ojo.');
      if(!is_int($input['mal_account_id']??null)||$input['mal_account_id']!==$account)throw new WebError('La cuenta de MyAnimeList cambió. Reabre el capítulo.',409);
      if(!sql($db,'SELECT mal_id FROM sa1_mal_links WHERE user_id=? AND slug=?',[uid(),$ep['slug']])->fetchColumn())throw new WebError('Vincula este anime con su ficha de MyAnimeList antes de marcarlo.');
      $number=(float)$ep['number_value'];
      if($number<1||$number>100000||floor($number)!==$number)throw new WebError('Este capítulo especial no tiene un número compatible con MyAnimeList.');
    }
    if($policy['mode']==='rewatch'&&!$manual){
      upsert($db,'sa1_rewatched',['user_id','episode_id','run_id','watched_at'],[['user_id'=>uid(),'episode_id'=>$ep['id'],'run_id'=>$policy['revision'],'watched_at'=>time()]],['user_id','episode_id','run_id'],['watched_at']);
      return ['watch_sync'=>['state'=>'rewatched','message'=>'Visto en este revisionado. El progreso original y MAL se conservan.']];
    }
    dispatch_library($db, 'watched', [
      'episode_id' => $ep['id'],
      'watched' => true,
      'automatic' => true,
    ]);
    // The eye is an explicit update of the original MAL progress, even in a rewatch.
    if($manual&&$policy['mode']==='rewatch')upsert($db,'sa1_watched',['user_id','episode_id','watched_at'],[['user_id'=>uid(),'episode_id'=>$ep['id'],'watched_at'=>time()]],['user_id','episode_id'],['watched_at']);
    if (array_key_exists('mal_account_id', $input) &&
      (!is_int($input['mal_account_id']) || $input['mal_account_id'] !== mal_identity_id($db))) {
      return ['watch_sync'=>['state'=>'blocked','message'=>'Visto en la web. La cuenta MAL cambió; reabre el reproductor para sincronizar con la cuenta actual.'],
        'home'=>home_data($db),'patch'=>state_patch($db,[$ep['slug']])];
    }
    $number = (float) $ep['number_value'];
    if ($number < 1 || $number > 100000 || floor($number) !== $number) {
      return [
        'watch_sync' => [
          'state' => 'blocked',
          'message' =>
            'Visto en la web. Este capítulo especial no tiene un número compatible con MAL.',
        ],
        'home' => home_data($db),
        'patch' => state_patch($db, [$ep['slug']]),
      ];
    }
    watch_sync_queue($db, $ep);
    $slug = $ep['slug'];
  } else {
    watch_sync_pending($db);
    $slug = (string) sql(
      $db,
      "SELECT slug FROM sa1_watch_sync WHERE user_id=? AND state='pending' AND next_retry<=? AND lock_until<=? ORDER BY updated_at LIMIT 1",
      [uid(), time(), time()],
    )->fetchColumn();
    if (!$slug) {
      return [
        'watch_sync' => [
          'state' => 'idle',
          'message' => 'No hay cambios pendientes para enviar.',
        ],
        'home' => home_data($db),
      ];
    }
  }
  $result = watch_sync_attempt($db, $slug);
  return [
    'watch_sync' => $result + ['slug' => $slug],
    'home' => home_data($db),
    'patch' => state_patch($db, [$slug], [], ['refresh_anime' => true]),
  ];
}
