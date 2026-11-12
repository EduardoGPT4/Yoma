<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function next_airing(array $anime): ?int
{
  if (empty($anime['active']) || empty($anime['published'])) {
    return null;
  }
  try {
    $date = new DateTimeImmutable($anime['published']);
  } catch (Throwable $e) {
    return null;
  }
  $next = $date->modify('+7 days');
  if ($next->getTimestamp() <= time()) return null;
  return $next->getTimestamp();
}
function local_watch_counts(PDO $db): array
{
  if (!uid()) {
    return [];
  }
  $counts = [];
  foreach (
    sql(
      $db,
      'SELECT e.slug,COUNT(*) AS n,SUM(CASE WHEN COALESCE(l.watched,0)=0 OR e.number_value>l.watched THEN 1 ELSE 0 END) AS beyond FROM sa1_watched w JOIN sa1_episodes e ON e.id=w.episode_id LEFT JOIN sa1_mal_links k ON k.user_id=w.user_id AND k.slug=e.slug LEFT JOIN sa1_mal_list l ON l.user_id=k.user_id AND l.mal_id=k.mal_id WHERE w.user_id=? GROUP BY e.slug',
      [uid()],
    )->fetchAll()
    as $r
  ) {
    $counts[$r['slug']] = [
      'n' => (int) $r['n'],
      'beyond' => (int) $r['beyond'],
    ];
  }
  return $counts;
}
function feature_decorate(PDO $db, array &$anime): void
{
  if (!$anime) return;
  ensure_catalog_metadata($db);
  $localCounts = local_watch_counts($db);
  $public = [];
  $slugs = array_column($anime,'slug');
  $marks = implode(',',array_fill(0,count($slugs),'?'));
  $source = [];
  foreach (sql($db,"SELECT * FROM sa1_catalog_source WHERE slug IN ($marks)",$slugs)->fetchAll() as $row) $source[$row['slug']] = $row;
  foreach (sql($db,"SELECT cm.slug,cm.extra,m.mal_id,m.start_date,m.airing_status,m.genres FROM sa1_catalog_mal cm JOIN sa1_mal_anime m ON m.mal_id=cm.mal_id WHERE cm.slug IN ($marks)",$slugs)->fetchAll() as $row) $public[$row['slug']] = $row;
  $links = [];
  foreach (
    sql(
      $db,
      'SELECT k.slug,k.mal_id,k.confirmed,m.aliases,m.start_date,m.airing_status,m.genres,m.duration_seconds,l.status,l.watched,l.score FROM sa1_mal_links k JOIN sa1_mal_anime m ON m.mal_id=k.mal_id LEFT JOIN sa1_mal_list l ON l.mal_id=k.mal_id AND l.user_id=k.user_id WHERE k.user_id=?',
      [uid()],
    )->fetchAll()
    as $r
  ) {
    $links[$r['slug']] = $r;
  }
  $languageChecks=[];foreach(sql($db,"SELECT slug,MAX(mirrors_at) AS checked FROM sa1_episodes WHERE slug IN ($marks) GROUP BY slug",$slugs)->fetchAll() as $r)$languageChecks[$r['slug']]=(int)$r['checked'];
  foreach ($anime as &$a) {
    $m = $links[$a['slug']] ?? null;
    $metadata = $public[$a['slug']] ?? [];
    $origin = $source[$a['slug']] ?? [];
    $a['mal'] = $m
      ? [
        'id' => (int) $m['mal_id'],
        'status' => $m['status'],
        'watched' => (int) ($m['watched'] ?? 0),
        'score' => (int) ($m['score'] ?? 0),
        'confirmed' => (bool) $m['confirmed'],
      ]
      : null;
    $a['next_airing'] = next_airing($a);
    $a['airing_confidence'] = $a['next_airing'] ? 'estimated' : 'unknown';
    $a['languages_checked_at']=$languageChecks[$a['slug']]??0;
    $a['airing_status'] = ($origin['airing_status'] ?? '') ?: (!empty($metadata['airing_status']) ? $metadata['airing_status'] : ($a['active'] ? 'currently_airing' : 'unknown'));
    $a['genres'] = json_decode($origin['genres'] ?? '[]',true) ?: [];
    $a['start_date'] = $a['start_date'] ?: ($metadata['start_date'] ?? '');
    $a['year'] = (string)($origin['premiere_year'] ?? substr($a['start_date'],0,4));
    $a['season'] = catalog_season($a);
    $shared = $public[$a['slug']] ?? [];
    $extra = $shared && (!$m || (int)$m['mal_id']===(int)$shared['mal_id']) ? (json_decode($shared['extra'],true) ?: []) : [];
    $a['mal_mean'] = $extra['mean'] ?? null;
    $a['studios'] = $extra['studios'] ?? [];
    $a['metadata_source'] = $origin ? 'AnimeAV1' : ($metadata ? 'MyAnimeList' : null);
    $a['watch_progress'] = $m
      ? (int) ($m['watched'] ?? 0) + ($localCounts[$a['slug']]['beyond'] ?? 0)
      : (int) $a['watched'];
  }
}
function home_data(PDO $db): array
{
  $mal = uid()
    ? mal_status($db)
    : ['configured' => mal_ready(), 'connected' => false, 'profile' => null];
  $counts = [];
  foreach (
    sql(
      $db,
      'SELECT status,COUNT(*) AS n FROM sa1_mal_list WHERE user_id=? GROUP BY status',
      [uid()],
    )->fetchAll()
    as $r
  ) {
    $counts[$r['status']] = (int) $r['n'];
  }
  $watching = uid() ? mal_library_rows($db, 'watching', 12) : [];
  $planned = uid() ? mal_library_rows($db, 'plan_to_watch', 12) : [];
  $continue = uid()
    ? sql(
      $db,
      "SELECT a.slug,a.title,a.cover,e.id AS episode_id,e.number FROM sa1_follow f JOIN sa1_anime a ON a.slug=f.slug JOIN sa1_episodes e ON e.id=(SELECT ne.id FROM sa1_episodes ne WHERE ne.slug=a.slug AND ne.number_value>COALESCE((SELECT l.watched FROM sa1_mal_links k JOIN sa1_mal_list l ON l.mal_id=k.mal_id AND l.user_id=k.user_id WHERE k.user_id=? AND k.slug=a.slug),0) AND NOT EXISTS(SELECT 1 FROM sa1_watched w WHERE w.episode_id=ne.id AND w.user_id=?) ORDER BY ne.number_value LIMIT 1) WHERE f.user_id=? AND f.status='watching' ORDER BY a.title LIMIT 12",
      [uid(), uid(), uid()],
    )->fetchAll()
    : [];
  if(uid()) {
    $recent=sql($db,"SELECT a.slug,a.title,a.cover,e.id AS episode_id,e.number,p.position,p.duration,p.updated_at FROM sa1_playback p JOIN sa1_episodes e ON e.id=p.episode_id JOIN sa1_anime a ON a.slug=e.slug WHERE p.user_id=? AND p.position>5 AND p.duration>0 AND p.position<p.duration-10 ORDER BY p.updated_at DESC LIMIT 100",[uid()])->fetchAll();
    $unique=[];foreach(array_merge($recent,$continue) as $row)if(!isset($unique[$row['slug']]))$unique[$row['slug']]=$row;
    $continue=array_slice(array_values($unique),0,12);
  }
  foreach ($continue as &$entry) {
    $entry['episode_id'] = (int) $entry['episode_id'];
  }
  unset($entry);
  $notice = uid()
    ? (int) sql(
      $db,
      'SELECT COUNT(DISTINCT slug) FROM sa1_notifications WHERE user_id=? AND read_at IS NULL',
      [uid()],
    )->fetchColumn()
    : 0;
  return [
    'user_id' => uid(),
    'revision' => microtime(true),
    'mal' => $mal,
    'watching' => array_slice($watching, 0, 12),
    'planned' => array_slice($planned, 0, 12),
    'watching_count' => $counts['watching'] ?? 0,
    'planned_count' => $counts['plan_to_watch'] ?? 0,
    'total' => array_sum($counts),
    'unmatched' => (int) sql(
      $db,
      'SELECT COUNT(*) FROM sa1_mal_list l WHERE l.user_id=? AND NOT EXISTS(SELECT 1 FROM sa1_mal_links k WHERE k.user_id=l.user_id AND k.mal_id=l.mal_id)',
      [uid()],
    )->fetchColumn(),
    'continue' => $continue,
    'notifications' => $notice,
    'notifications_revision' => uid()?(int)sql($db,'SELECT MAX(id) FROM sa1_notifications WHERE user_id=?',[uid()])->fetchColumn():0,
    'watch_pending' => function_exists('watch_sync_pending')
      ? watch_sync_pending($db)
      : ['count' => 0, 'next_retry' => 0],
    'mal_synced_at' =>
      (int) (sql($db, 'SELECT finished_at FROM sa1_mal_sync WHERE user_id=?', [
        uid(),
      ])->fetchColumn() ?:
      0),
    'maintenance' => administrator($db) ? maintenance_status($db) : null,
  ];
}
function mal_import_xml(PDO $db, string $xml, bool $commit): array
{
  member();
  if (
    strlen($xml) > 10 * 1024 * 1024 ||
    preg_match('/<!\s*(DOCTYPE|ENTITY)/i', $xml)
  ) {
    throw new WebError(
      'XML no permitido. Usa la exportación original de MAL, sin entidades externas.',
    );
  }
  $previous = libxml_use_internal_errors(true);
  try {
    $root = simplexml_load_string($xml, SimpleXMLElement::class, LIBXML_NONET);
  } finally {
    libxml_clear_errors();
    libxml_use_internal_errors($previous);
  }
  if (
    !$root ||
    $root->getName() !== 'myanimelist' ||
    count($root->anime) > 5000
  ) {
    throw new WebError(
      'Usa un XML de exportación de MyAnimeList, con hasta 5.000 animes.',
    );
  }
  $statuses = [
    'Watching' => 'watching',
    'Completed' => 'completed',
    'On-Hold' => 'on_hold',
    'Dropped' => 'dropped',
    'Plan to Watch' => 'plan_to_watch',
  ];
  $entries = [];
  $ids = [];
  foreach ($root->anime as $a) {
    $id = filter_var((string) $a->series_animedb_id, FILTER_VALIDATE_INT);
    $status = $statuses[(string) $a->my_status] ?? null;
    $watched = filter_var(
      (string) $a->my_watched_episodes,
      FILTER_VALIDATE_INT,
    );
    $score = filter_var((string) $a->my_score, FILTER_VALIDATE_INT);
    $name = trim((string) $a->series_title);
    if (
      !$id ||
      $id < 1 ||
      !$status ||
      $watched === false ||
      $watched < 0 ||
      $watched > 100000 ||
      $score === false ||
      $score < 0 ||
      $score > 10 ||
      $name === '' ||
      mb_strlen($name) > 400 ||
      isset($ids[$id])
    ) {
      throw new WebError(
        'El XML contiene una ficha inválida o duplicada. No se importó ningún cambio.',
      );
    }
    $ids[$id] = true;
    $entries[] = [
      'node' => [
        'id' => $id,
        'title' => $name,
        'media_type' =>
          [
            1 => 'tv',
            2 => 'ova',
            3 => 'movie',
            4 => 'special',
            5 => 'ona',
            6 => 'music',
          ][(int) $a->series_type] ?? '',
        'num_episodes' => (int) $a->series_episodes,
      ],
      'status' => [
        'status' => $status,
        'num_episodes_watched' => $watched,
        'score' => $score,
        'comments' => mb_substr(
          (string) $a->my_comments ?: (string) $a->my_tags,
          0,
          2000,
        ),
      ],
    ];
  }
  if (!$commit) {
    return [
      'preview' => [
        'count' => count($entries),
        'sample' => array_slice(
          array_map(
            fn($e) => [
              'title' => $e['node']['title'],
              'status' => $e['status']['status'],
              'watched' => $e['status']['num_episodes_watched'],
              'score' => $e['status']['score'],
            ],
            $entries,
          ),
          0,
          12,
        ),
      ],
    ];
  }
  $index = mal_catalog_index($db);
  $db->beginTransaction();
  try {
    foreach ($entries as $e) {
      $m = mal_cache_list($db, $e['node'], $e['status'], 'xml', 'xml');
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
    $event = log_event(
      $db,
      uid(),
      'XML de MAL importado: ' .
        count($entries) .
        ' animes. No se hicieron cambios en MAL.',
    );
    $db->commit();
  } catch (Throwable $error) {
    $db->rollBack();
    throw $error;
  }
  return [
    'message' =>
      'XML importado. Las coincidencias dudosas quedan pendientes de vincular.',
    'home' => home_data($db),
    'patch' => state_patch(
      $db,
      [],
      [],
      ['refresh_anime' => true, 'history' => [$event]],
    ),
  ];
}
function notify_new_episode(PDO $db, string $slug, string $number): void
{
  foreach (
    sql(
      $db,
      'SELECT user_id FROM sa1_follow WHERE slug=? AND excluded=0 AND (status IN (?,?) OR favorite=1)',
      [$slug, 'watching', 'planned'],
    )->fetchAll()
    as $f
  ) {
    if (
      sql(
        $db,
        'SELECT id FROM sa1_notifications WHERE user_id=? AND slug=? AND number=?',
        [$f['user_id'], $slug, $number],
      )->fetchColumn()
    ) {
      continue;
    }
    sql(
      $db,
      'INSERT INTO sa1_notifications(user_id,slug,number,created_at) VALUES(?,?,?,?)',
      [$f['user_id'], $slug, $number, time()],
    );
  }
}
function notify_episode_gap(PDO $db,string $slug,string $oldLatest,array $numbers): void
{
  if ($oldLatest!=='') {
    $baseline=sql($db,'SELECT number_value FROM sa1_notice_baseline WHERE slug=?',[$slug])->fetchColumn();
    $threshold=$baseline===false?(float)$oldLatest:min((float)$oldLatest,(float)$baseline);
    foreach($numbers as $number) if((float)$number>$threshold) notify_new_episode($db,$slug,(string)$number);
  }
  sql($db,'DELETE FROM sa1_notice_baseline WHERE slug=?',[$slug]);
}
function player_recommendations(PDO $db,array $anime): array
{
  $slug=$anime['slug'];$saga=[];$seen=[$slug=>true];$labels=relation_types();
  foreach(sql($db,"SELECT a.slug,a.title,a.cover,a.category,r.relation FROM sa1_relations r JOIN sa1_anime a ON a.slug=r.target WHERE r.slug=? AND r.state='approved' ORDER BY a.start_date,a.title LIMIT 12",[$slug])->fetchAll() as $row){
    $row['reason']=$labels[$row['relation']]??'Relacionado';$row['confirmed']=true;$saga[]=$row;$seen[$row['slug']]=true;
  }
  ensure_search_index($db);
  $words=explode(' ',title_key($anime['title']));$stem=$words[0]??'';
  if(mb_strlen($stem)<3)$stem=implode(' ',array_slice($words,0,2));
  if(mb_strlen($stem)>=3){
    $prefix=str_replace(['!','%','_'],['!!','!%','!_'],$stem).'%';
    foreach(sql($db,"SELECT a.slug,a.title,a.cover,a.category FROM sa1_anime a JOIN sa1_anime_search s ON s.slug=a.slug WHERE s.search_key LIKE ? ESCAPE '!' AND a.slug<>? ORDER BY a.start_date,a.title LIMIT 40",[$prefix,$slug])->fetchAll() as $row){
      if(isset($seen[$row['slug']]))continue;
      $row['reason']='Nombre parecido';$row['confirmed']=false;$saga[]=$row;$seen[$row['slug']]=true;
      if(count($saga)>=12)break;
    }
  }
  $genres=json_decode(sql($db,'SELECT genres FROM sa1_catalog_source WHERE slug=?',[$slug])->fetchColumn()?:'[]',true)?:[];
  $matches=[];$parts=[];$args=[];
  foreach(array_slice($genres,0,10) as $genre){$parts[]="CASE WHEN sf.genres LIKE ? ESCAPE '!' THEN 1 ELSE 0 END";$args[]='%'.str_replace(['!','%','_'],['!!','!%','!_'],json_encode($genre,JSON_UNESCAPED_UNICODE)).'%';}
  if($parts){
    $args[]=$slug;
    foreach(sql($db,'SELECT a.slug,a.title,a.cover,a.category,sf.genres,('.implode('+',$parts).') AS shared_count FROM sa1_anime a JOIN sa1_catalog_source sf ON sf.slug=a.slug WHERE a.slug<>? ORDER BY shared_count DESC,a.source_id DESC,a.slug LIMIT 12',$args)->fetchAll() as $row){
      if(!(int)$row['shared_count'])continue;
      $shared=array_values(array_intersect($genres,json_decode($row['genres'],true)?:[]));
      $row['shared_count']=(int)$row['shared_count'];$row['reason']=implode(' · ',array_slice($shared,0,2));$row['shared_genres']=$shared;unset($row['genres']);$matches[]=$row;
    }
  }
  return ['saga'=>$saga,'genres'=>$matches,'source_genres'=>$genres,'watch_order'=>saga_watch_path($db,$anime)];
}
function player_servers_data(PDO $db, array $episode, bool $refresh = false): array
{
  $canRefresh = administrator($db);
  $refreshState = 'fresh'; $retryAt = 0; $message = '';
  $stale = (int)$episode['mirrors_at'] <= time()-1800;
  if ($refresh && $canRefresh && $stale) {
    try {
      $GLOBALS['season_scrape_interactive']=true;
      episode_mirrors($db,$episode);
      $episode = sql($db,'SELECT * FROM sa1_episodes WHERE id=?',[$episode['id']])->fetch();
    } catch (WebError $error) {
      if ($error->status !== 429) throw $error;
      $refreshState = 'waiting';
      $retryAt = time()+3;
      foreach (['scraper-global'=>120,'scraper-user:'.uid()=>120,'scraper-spacing'=>1] as $key=>$maximum) {
        $limit = sql($db,'SELECT hits,reset_at FROM sa1_limits WHERE name=?',[$key])->fetch();
        if ($limit && (int)$limit['hits'] >= $maximum) $retryAt=max($retryAt,(int)$limit['reset_at']);
      }
      $message = 'Los servidores esperan su turno de actualización. Se reintentará automáticamente; puedes seguir usando los guardados.';
    } catch (ScraperError $error) {
      record_scraper_failure($db,$error->getMessage());
      $refreshState = 'error';
      $message = 'No se pudo actualizar AnimeAV1. Los servidores guardados se conservan; puedes volver a intentarlo.';
    }
    finally {unset($GLOBALS['season_scrape_interactive']);}
  } elseif ($stale) {
    $refreshState = 'stale';
  }
  $mirrors = json_decode($episode['mirrors'] ?? '[]', true) ?: [];
  $servers = [];
  foreach ($mirrors as $m) {
    $parts = parse_url($m['url'] ?? '');
    $host = strtolower($parts['host'] ?? '');
    if (
      ($parts['scheme'] ?? '') !== 'https' ||
      isset($parts['user']) ||
      isset($parts['port'])
    ) {
      continue;
    }
    if (
      in_array($host, ['www.mp4upload.com', 'mp4upload.com'], true) &&
      preg_match(
        '~^/(?:embed-)?([a-zA-Z0-9]{5,40})(?:\.html)?/?$~',
        $parts['path'] ?? '',
        $match,
      )
    ) {
      $url = 'https://www.mp4upload.com/embed-' . $match[1] . '.html';
    } elseif (
      in_array($host, ['voe.sx', 'www.voe.sx'], true) &&
      preg_match(
        '~^/(?:e/)?([a-zA-Z0-9]{5,40})/?$~',
        $parts['path'] ?? '',
        $match,
      )
    ) {
      $url = 'https://voe.sx/e/' . $match[1];
    } else {
      continue;
    }
    $servers[] = [
      'server' => $m['server'],
      'language' => $m['language'],
      'url' => $url,
    ];
  }
  if (player_preview_url()) {
    foreach ($servers as &$previewServer) {
      if ($previewServer['server'] === 'MP4Upload') $previewServer['url'] = player_preview_url();
    }
    unset($previewServer);
  }
  $task = catalog_task_status($db,'mirrors',(string)$episode['id']);
  if (!$message && !$servers) $message = $canRefresh ? 'Consulta los servidores de este capítulo.' : 'Solicita una actualización para obtener los servidores de este capítulo.';
  return ['servers'=>$servers,'servers_checked_at'=>(int)$episode['mirrors_at'],'update_task'=>$task,
    'server_refresh'=>['state'=>$refreshState,'retry_at'=>$retryAt,'can_refresh'=>$canRefresh,'message'=>$message]];
}
function player_servers(PDO $db,array $input): array
{
  member();
  $episode = sql($db,'SELECT * FROM sa1_episodes WHERE id=?',[(int)($input['episode_id']??0)])->fetch();
  if (!$episode) throw new WebError('Capítulo no encontrado.',404);
  admin_member($db);
  return ['player_servers'=>player_servers_data($db,$episode,true)];
}
function player_data(PDO $db, array $input): array
{
  member();
  $episode = sql($db,'SELECT * FROM sa1_episodes WHERE id=?',[(int)($input['episode_id']??0)])->fetch();
  if (!$episode) throw new WebError('Capítulo no encontrado.',404);
  $serverData = player_servers_data($db,$episode);
  $servers = $serverData['servers'];
  $a = find_anime($db, $episode['slug']);
  $serverTask = catalog_task_status($db,'mirrors',(string)$episode['id']);
  $malAccount=mal_identity_id($db);
  $malLink=sql($db,'SELECT k.mal_id,k.confirmed,l.watched FROM sa1_mal_links k LEFT JOIN sa1_mal_list l ON l.user_id=k.user_id AND l.mal_id=k.mal_id WHERE k.user_id=? AND k.slug=?',[uid(),$episode['slug']])->fetch();
  $chapters=sql($db,'SELECT e.id,e.number,w.watched_at FROM sa1_episodes e LEFT JOIN sa1_watched w ON w.episode_id=e.id AND w.user_id=? WHERE e.slug=? ORDER BY e.number_value',[uid(),$episode['slug']])->fetchAll();
  foreach($chapters as &$chapter){$chapter['id']=(int)$chapter['id'];$chapter['watched']=(bool)$chapter['watched_at'];unset($chapter['watched_at']);}unset($chapter);
  episode_marks_apply($db,$chapters);
  return [
    'player' => [
      'related'=>player_recommendations($db,$a),
      'anime'=>['title'=>$a['title'],'cover'=>$a['cover'],'description'=>$a['synopsis']??'','category'=>$a['category'],'season'=>$a['season']??'','start_date'=>$a['start_date']??''],
      'episode' => [
        'id' => (int) $episode['id'],
        'number' => $episode['number'],
        'slug' => $episode['slug'],
        'title' => $a['title'],
      ],
      'playback' => playback_open($db,$episode),
      'personal' => personal_player($db,$episode),
      'servers' => $servers,
      'servers_checked_at' => $serverData['servers_checked_at'],
      'server_refresh' => $serverData['server_refresh'],
      'update_task' => $serverTask,
      'mal_account_id' => $malAccount,
      'mal'=>['connected'=>mal_status($db)['connected'],'linked'=>(bool)$malLink,'confirmed'=>(bool)($malLink['confirmed']??false),'id'=>(int)($malLink['mal_id']??0),'watched'=>(int)($malLink['watched']??0)],
      'watch_sync' => function_exists('watch_sync_result')
        ? watch_sync_result($db, $episode['slug'])
        : ['state' => 'idle'],
      'chapters' => $chapters,
      'warning' => $servers
        ? 'El video se reproduce desde el servidor elegido. Su disponibilidad depende de ese servidor.'
        : 'No hay un reproductor compatible guardado. Puedes solicitar o consultar los servidores desde esta página.',
    ],
  ];
}
function library_stats(PDO $db): array
{
  member();
  $mal = mal_library_rows($db);
  $watched = 0;
  $seconds = 0;
  $seasonScores = [];
  $linked = [];
  $localCounts = local_watch_counts($db);
  foreach ($mal as $m) {
    $count = $m['watched'];
    if ($m['slug']) {
      $linked[$m['slug']] = true;
      $count += $localCounts[$m['slug']]['beyond'] ?? 0;
    }
    $watched += $count;
    $seconds += $count * ($m['duration_seconds'] ?: 1440);
    if ($m['score']) {
      $season = preg_match('/^\d{4}-\d{2}/', $m['start_date'])
        ? season_name($m['start_date'])
        : 'Sin fecha';
      $seasonScores[$season][] = $m['score'];
    }
  }
  foreach (
    sql(
      $db,
      'SELECT a.slug,a.season,f.score,COUNT(w.episode_id) AS watched FROM sa1_follow f JOIN sa1_anime a ON a.slug=f.slug LEFT JOIN sa1_episodes e ON e.slug=a.slug LEFT JOIN sa1_watched w ON w.episode_id=e.id AND w.user_id=f.user_id WHERE f.user_id=? GROUP BY a.slug,a.season,f.score',
      [uid()],
    )->fetchAll()
    as $r
  ) {
    if (isset($linked[$r['slug']])) {
      continue;
    }
    $watched += (int) $r['watched'];
    $seconds += (int) $r['watched'] * 1440;
    if ((int) $r['score']) {
      $seasonScores[$r['season'] ?: 'Sin fecha'][] = (int) $r['score'];
    }
  }
  $averages = [];
  foreach ($seasonScores as $season => $scores) {
    $averages[] = [
      'season' => $season,
      'average' => round(array_sum($scores) / count($scores), 2),
      'rated' => count($scores),
    ];
  }
  return [
    'watched' => $watched,
    'estimated_hours' => round($seconds / 3600, 1),
    'download_bytes' => (int) sql(
      $db,
      "SELECT COALESCE(SUM(bytes),0) FROM sa1_jobs WHERE user_id=? AND status='confirmed'",
      [uid()],
    )->fetchColumn(),
    'downloaded' => (int) sql(
      $db,
      "SELECT COUNT(*) FROM sa1_jobs WHERE user_id=? AND status='confirmed'",
      [uid()],
    )->fetchColumn(),
    'season_scores' => $averages,
  ];
}
function dispatch_features(PDO $db, string $action, array $input): ?array
{
  if ($action === 'stats') {
    return ['stats' => library_stats($db)];
  }
  if ($action === 'notifications') {
    $user=member();
    $upTo=(int)sql($db,'SELECT MAX(id) FROM sa1_notifications WHERE user_id=?',[$user])->fetchColumn();
    return [
      'notifications' => sql(
        $db,
        "SELECT MAX(n.id) AS id,n.slug,MIN(CAST(n.number AS DECIMAL(12,4))) AS first_number,MAX(CAST(n.number AS DECIMAL(12,4))) AS number,COUNT(*) AS episode_count,SUM(CASE WHEN n.read_at IS NULL THEN 1 ELSE 0 END) AS unread,MAX(n.created_at) AS created_at,MIN(n.read_at) AS read_at,a.title,a.cover FROM sa1_notifications n JOIN sa1_anime a ON a.slug=n.slug WHERE n.user_id=? AND n.id<=? GROUP BY n.slug,a.title,a.cover HAVING MAX(n.id)<CAST(? AS SIGNED) ORDER BY MAX(n.id) DESC LIMIT 50",
        [$user,$upTo,max(1,(int)($input['before']??PHP_INT_MAX))],
      )->fetchAll(),
      'notifications_up_to'=>$upTo,
    ];
  }
  if ($action === 'notifications_read') {
    member();
    $upTo = max(0, (int) ($input['up_to'] ?? 0));
    sql(
      $db,
      'UPDATE sa1_notifications SET read_at=? WHERE user_id=? AND id<=? AND read_at IS NULL',
      [time(), uid(), $upTo],
    );
    return [
      'home' => home_data($db),
      'message' => 'Notificaciones marcadas como leídas.',
    ];
  }
  return null;
}
