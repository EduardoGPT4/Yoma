<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function find_anime(PDO $db, string $slug): array
{
  $a = sql($db, 'SELECT * FROM sa1_anime WHERE slug=?', [$slug])->fetch();
  if (!$a) {
    throw new WebError('No se encontró ese anime.', 404);
  }
  return $a;
}

function detail(PDO $db, string $slug): array
{
  $a = find_anime($db, $slug);
  $warning = '';
  if (!$a['catalog_complete']) {
    $warning =
      'El listado completo está pendiente de actualización por el administrador.';
  }
  $episodes = sql(
    $db,
    'SELECT e.*,w.watched_at,j.id AS download_job_id,j.status AS download_status FROM sa1_episodes e LEFT JOIN sa1_watched w ON w.episode_id=e.id AND w.user_id=? LEFT JOIN sa1_jobs j ON j.episode_id=e.id AND j.user_id=? AND j.language=? WHERE e.slug=? ORDER BY e.number_value',
    [uid(), uid(), preferences($db, uid())['language'], $slug],
  )->fetchAll();
  $mode=uid()?watch_mode($db,$slug):null;$rewatched=[];
  if($mode&&$mode['mode']==='rewatch')$rewatched=array_flip(array_column(sql($db,'SELECT episode_id FROM sa1_rewatched WHERE user_id=? AND run_id=?',[uid(),$mode['revision']])->fetchAll(),'episode_id'));
  foreach ($episodes as &$e) {
    $e['id'] = (int) $e['id'];
    $e['download_job_id'] =
      $e['download_job_id'] === null ? null : (int) $e['download_job_id'];
    $e['watched'] = (bool) $e['watched_at'];
    $e['rewatched']=isset($rewatched[$e['id']]);
    unset($e['mirrors']);
  }
  return [
    'anime' => decorate_anime($db, [$a])[0],
    'episodes' => $episodes,
    'warning' => $warning,
    'freshness' => catalog_freshness($db,$slug),
    'update_task' => catalog_task_status($db,'detail',$slug),
    'relations' => catalog_relations($db,$slug),
    'watch_mode' => $mode,
  ];
}

function decorate_anime(PDO $db, array $anime): array
{
  if (!$anime) {
    return [];
  }
  $slugs = array_column($anime, 'slug');
  $marks = implode(',', array_fill(0, count($slugs), '?'));
  $follows = [];
  foreach (
    sql(
      $db,
      "SELECT * FROM sa1_follow WHERE user_id=? AND slug IN ($marks)",
      array_merge([uid()], $slugs),
    )->fetchAll()
    as $f
  ) {
    $follows[$f['slug']] = $f;
  }
  $seen = [];
  foreach (
    sql(
      $db,
      "SELECT e.slug,COUNT(*) AS n FROM sa1_watched w JOIN sa1_episodes e ON e.id=w.episode_id WHERE w.user_id=? AND e.slug IN ($marks) GROUP BY e.slug",
      array_merge([uid()], $slugs),
    )->fetchAll()
    as $r
  ) {
    $seen[$r['slug']] = (int) $r['n'];
  }
  $known = [];
  foreach (
    sql(
      $db,
      "SELECT slug,COUNT(*) AS n FROM sa1_episodes WHERE slug IN ($marks) GROUP BY slug",
      $slugs,
    )->fetchAll()
    as $r
  ) {
    $known[$r['slug']] = (int) $r['n'];
  }
  $downloaded = [];
  foreach (
    sql(
      $db,
      "SELECT e.slug,COUNT(*) AS n FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id WHERE j.user_id=? AND j.status='confirmed' AND e.slug IN ($marks) GROUP BY e.slug",
      array_merge([uid()], $slugs),
    )->fetchAll()
    as $r
  ) {
    $downloaded[$r['slug']] = (int) $r['n'];
  }
  $latestJobs = [];
  foreach (
    sql(
      $db,
      "SELECT j.id,j.status,j.language,e.slug,e.number FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id JOIN sa1_anime a ON a.slug=e.slug WHERE j.user_id=? AND j.language=? AND e.slug IN ($marks) AND e.number=a.latest",
      array_merge([uid(), preferences($db, uid())['language']], $slugs),
    )->fetchAll()
    as $job
  ) {
    $job['id'] = (int) $job['id'];
    $latestJobs[$job['slug']] = $job;
  }
  foreach ($anime as &$a) {
    $f = $follows[$a['slug']] ?? [];
    $a['weekday'] = (int) $a['weekday'];
    $a['active'] = (bool) $a['active'];
    $a['catalog_complete'] = (bool) $a['catalog_complete'];
    $a['status'] = $f['status'] ?? 'none';
    $a['favorite'] = (bool) ($f['favorite'] ?? 0);
    $a['excluded'] = (bool) ($f['excluded'] ?? 0);
    $a['score'] = (int) ($f['score'] ?? 0);
    $a['notes'] = $f['notes'] ?? '';
    $a['latest_job'] = $latestJobs[$a['slug']] ?? null;
    $a['watched'] = $seen[$a['slug']] ?? 0;
    $a['episodes'] = $known[$a['slug']] ?? 0;
    $a['downloaded'] = $downloaded[$a['slug']] ?? 0;
  }
  feature_decorate($db, $anime);
  return $anime;
}

function catalog(PDO $db, array $input): array
{
  ensure_search_index($db);
  ensure_catalog_metadata($db);
  ensure_catalog_languages($db);
  $search = trim(mb_substr((string)($input['search'] ?? ''),0,120));
  $category = (string)($input['category'] ?? '');
  $order = (string)($input['order'] ?? 'recent');
  $user = uid();
  $from = catalog_from_sql();
  $start = catalog_start_sql();
  $yearSql = catalog_year_sql();
  $airing = catalog_airing_sql();
  $where = []; $args = [];
  if ($search !== '') {
    $needle = title_key($search);
    if (str_contains($search,'%') || str_contains($search,'_')) {
      $where[] = "a.title LIKE ? ESCAPE '!'";
      $args[] = '%'.str_replace(['!','%','_'],['!!','!%','!_'],$search).'%';
    } elseif ($needle === '') $where[] = '1=0';
    else {
      $where[] = '(EXISTS(SELECT 1 FROM sa1_anime_search s WHERE s.slug=a.slug AND s.search_key LIKE ?) OR m.search_key LIKE ?)';
      array_push($args,'%'.$needle.'%','%'.$needle.'%');
    }
  }
  if ($category !== '') { $where[] = 'a.category=?'; $args[] = $category; }
  if (($input['scope'] ?? '') === 'season') $where[] = 'a.active=1';
  $year = (string)($input['year'] ?? '');
  if ($year === 'unknown') $where[] = "$yearSql=''";
  elseif ($year !== '') {
    if (!preg_match('/^(?:19|20|21)\d{2}$/D',$year)) throw new WebError('Año inválido.');
    $where[] = "$yearSql=?"; $args[] = $year;
  }
  $emission = (string)($input['airing'] ?? '');
  if ($emission !== '') {
    if (!in_array($emission,['currently_airing','finished_airing','not_yet_aired','unknown'],true)) throw new WebError('Emisión inválida.');
    $where[] = "$airing=?"; $args[] = $emission;
  }
  $season = (string)($input['season'] ?? '');
  if ($season !== '') {
    if ($season === 'unknown') $where[] = "($start='' AND a.season='')";
    else {
      if (!preg_match('/^(invierno|primavera|verano|otoño)((?:19|20|21)\d{2})$/uD',$season,$match)) throw new WebError('Temporada inválida.');
      $months = ['invierno'=>['01','03'],'primavera'=>['04','06'],'verano'=>['07','09'],'otoño'=>['10','12']][$match[1]];
      $where[] = "(($start LIKE ? AND SUBSTR($start,6,2) BETWEEN ? AND ?) OR ($start='' AND a.season=?))";
      array_push($args,$match[2].'%',$months[0],$months[1],$season);
    }
  }
  $letter = (string)($input['letter'] ?? '');
  if ($letter !== '') {
    if (!preg_match('/^[A-Z#]$/D',$letter)) throw new WebError('Letra inválida.');
    if ($letter === '#') $where[] = "EXISTS(SELECT 1 FROM sa1_anime_search s WHERE s.slug=a.slug AND UPPER(SUBSTR(s.search_key,1,1)) NOT BETWEEN 'A' AND 'Z')";
    else { $where[] = 'EXISTS(SELECT 1 FROM sa1_anime_search s WHERE s.slug=a.slug AND s.search_key LIKE ?)'; $args[] = strtolower($letter).'%'; }
  }
  $library = (string)($input['library'] ?? '');
  $download = (string)($input['download'] ?? '');
  if (($library !== '' || $download !== '' || !empty($input['unwatched']) || $order === 'score') && !$user) throw new WebError('Inicia sesión para filtrar tus datos.',401);
  if ($library === 'none') $where[] = 'f.slug IS NULL';
  elseif ($library === 'followed') $where[] = 'f.slug IS NOT NULL';
  elseif ($library === 'favorites') $where[] = 'f.favorite=1';
  elseif ($library !== '') {
    if (!in_array($library,['watching','planned','completed','paused','dropped'],true)) throw new WebError('Estado de biblioteca inválido.');
    $where[] = 'f.status=?'; $args[] = $library;
  }
  $jobs = "SELECT 1 FROM sa1_jobs j JOIN sa1_episodes je ON je.id=j.episode_id WHERE j.user_id=$user AND je.slug=a.slug";
  if ($download === 'downloaded') $where[] = "EXISTS($jobs AND j.status='confirmed')";
  elseif ($download === 'queued') $where[] = "EXISTS($jobs AND j.status IN ('pending','exported'))";
  elseif ($download === 'unprepared') $where[] = "NOT EXISTS($jobs AND j.status<>'cancelled')";
  elseif ($download !== '') throw new WebError('Estado de descarga inválido.');
  if (!empty($input['unwatched'])) {
    $where[] = "EXISTS(SELECT 1 FROM sa1_episodes ep WHERE ep.slug=a.slug AND NOT EXISTS(SELECT 1 FROM sa1_watched w WHERE w.user_id=$user AND w.episode_id=ep.id) AND ep.number_value>COALESCE((SELECT l.watched FROM sa1_mal_list l WHERE l.user_id=$user AND l.mal_id=k.mal_id),0))";
  }
  $include = catalog_genre_values($input['include_genres'] ?? []);
  $exclude = catalog_genre_values($input['exclude_genres'] ?? []);
  $legacyGenre = mb_substr((string)($input['genre'] ?? ''),0,80);
  if ($legacyGenre !== '') $include[] = $legacyGenre;
  $mode = (string)($input['genre_mode']??'all');
  if (!in_array($mode,['all','any'],true)) throw new WebError('Modo de géneros inválido.');
  $include = catalog_source_genres($include);
  $exclude = catalog_source_genres($exclude);
  if ($include || $exclude) $where[] = 'sf.slug IS NOT NULL';
  foreach ([[$include,false],[$exclude,true]] as [$genres,$negative]) {
    $clauses=[];
    foreach (array_unique($genres) as $genre) {
      $clauses[] = $negative ? "COALESCE(sf.genres,'[]') NOT LIKE ? ESCAPE '!'" : "COALESCE(sf.genres,'[]') LIKE ? ESCAPE '!'";
      $args[] = '%'.str_replace(['!','%','_'],['!!','!%','!_'],json_encode($genre,JSON_UNESCAPED_UNICODE)).'%';
    }
    if ($clauses) $where[]='('.implode(!$negative && $mode==='any'?' OR ':' AND ',$clauses).')';
  }
  $language = (string)($input['language'] ?? '');
  if ($language !== '') {
    $languages = 'SELECT 1 FROM sa1_episode_languages el JOIN sa1_episodes le ON le.id=el.episode_id WHERE le.slug=a.slug';
    if ($language === 'unknown') $where[] = "NOT EXISTS($languages)";
    elseif (in_array($language,['SUB','LAT','DUB'],true)) { $where[] = "EXISTS($languages AND el.language=?)"; $args[] = $language; }
    else throw new WebError('Idioma inválido.');
  }
  $sorts = [
    'recent'=>'a.source_id DESC,a.slug',
    'title'=>'a.title,a.slug',
    'title_desc'=>'a.title DESC,a.slug',
    'score'=>'COALESCE(f.score,0) DESC,a.title,a.slug',
    'episodes'=>'(SELECT COUNT(*) FROM sa1_episodes ce WHERE ce.slug=a.slug) DESC,a.title,a.slug',
    'premiere'=>"CASE WHEN $yearSql='' THEN 1 ELSE 0 END,$yearSql DESC,$start DESC,a.title,a.slug",
    'updated'=>'a.updated_at DESC,a.title,a.slug',
  ];
  if (!isset($sorts[$order])) throw new WebError('Orden inválido.');
  $clause = $where ? ' WHERE '.implode(' AND ',$where) : '';
  $total = (int)sql($db,'SELECT COUNT(*) '.$from.$clause,$args)->fetchColumn();
  $size = 24; $pages = max(1,(int)ceil($total/$size));
  $page = max(1,min($pages,(int)($input['page'] ?? 1))); $offset = ($page-1)*$size;
  $rows = sql($db,'SELECT a.* '.$from.$clause.' ORDER BY '.$sorts[$order].' LIMIT '.$size.' OFFSET '.$offset,$args)->fetchAll();
  $coverage = sql($db,"SELECT COUNT(*) AS total,SUM(CASE WHEN sf.slug IS NOT NULL THEN 1 ELSE 0 END) AS source,SUM(CASE WHEN $start<>'' THEN 1 ELSE 0 END) AS dated,SUM(CASE WHEN $yearSql<>'' THEN 1 ELSE 0 END) AS years,SUM(CASE WHEN COALESCE(sf.genres,'[]')<>'[]' THEN 1 ELSE 0 END) AS genres,SUM(CASE WHEN $airing<>'unknown' THEN 1 ELSE 0 END) AS airing ".$from)->fetch();
  return [
    'items'=>decorate_anime($db,$rows),'page'=>$page,'pages'=>$pages,'total'=>$total,
    'all_total'=>(int)$coverage['total'],'size'=>$size,
    'years'=>catalog_years($db),'seasons'=>catalog_seasons($db),'genres'=>catalog_genres($db),
    'coverage'=>array_map('intval',$coverage),
    'selected_genres'=>['include'=>$include,'exclude'=>$exclude,'mode'=>$mode],
    'freshness'=>catalog_coverage($db),
    'metadata_source'=>'AnimeAV1',
    'categories'=>$db->query('SELECT DISTINCT category FROM sa1_anime ORDER BY category')->fetchAll(PDO::FETCH_COLUMN),
    'updated_at'=>max((int)meta($db,'directory_updated','0'),(int)meta($db,'catalog_source_updated','0')),
  ];
}
