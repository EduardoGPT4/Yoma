<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit(); }

// Dates describe independently verified facts, never a successful unrelated request.
function catalog_touch(PDO $db, string $slug, array $fields, ?int $at = null): void
{
  catalog_invalidate($db);
  $allowed = ['episodes_at','genres_at','airing_at','directory_at','relations_at'];
  $row = ['slug'=>$slug];
  foreach ($fields as $field) if (in_array($field,$allowed,true)) $row[$field] = $at ?? time();
  if (count($row)>1) upsert($db,'sa1_catalog_freshness',array_keys($row),[$row],['slug'],array_slice(array_keys($row),1));
}
function catalog_freshness(PDO $db, string $slug): array
{
  $r = sql($db,'SELECT * FROM sa1_catalog_freshness WHERE slug=?',[$slug])->fetch() ?: [];
  $source = sql($db,'SELECT updated_at,airing_status FROM sa1_catalog_source WHERE slug=?',[$slug])->fetch() ?: [];
  $episodes = sql($db,'SELECT COUNT(*) AS total,SUM(CASE WHEN mirrors_at>0 THEN 1 ELSE 0 END) AS checked,MIN(CASE WHEN mirrors_at>0 THEN mirrors_at END) AS oldest,MAX(mirrors_at) AS newest FROM sa1_episodes WHERE slug=?',[$slug])->fetch();
  return ['episodes_at'=>(int)($r['episodes_at']??0), 'genres_at'=>max((int)($r['genres_at']??0),(int)($source['updated_at']??0)),
    'airing_at'=>max((int)($r['airing_at']??0),!empty($source['airing_status'])?(int)$source['updated_at']:0),'directory_at'=>(int)($r['directory_at']??meta($db,'directory_updated','0')),
    'relations_at'=>(int)($r['relations_at']??0),'servers_checked'=>(int)$episodes['checked'],
    'episodes_known'=>(int)$episodes['total'],'servers_oldest'=>(int)$episodes['oldest'],'servers_newest'=>(int)$episodes['newest']];
}
function catalog_coverage(PDO $db): array
{
  return public_cache($db,'coverage-v1',static fn()=>catalog_compute_coverage($db));
}
function catalog_compute_coverage(PDO $db): array
{
  $total = (int)sql($db,'SELECT COUNT(*) FROM sa1_anime')->fetchColumn();
  $out = ['total'=>$total];
  foreach (['episodes','genres','airing','directory'] as $kind) {
    $column = $kind.'_at';
    $r = sql($db,"SELECT COUNT(*) AS checked,MIN($column) AS oldest,MAX($column) AS newest FROM sa1_catalog_freshness WHERE $column>0")->fetch();
    if (in_array($kind,['genres','airing'],true)) {
      $r = sql($db,'SELECT COUNT(*) AS checked,MIN(updated_at) AS oldest,MAX(updated_at) AS newest FROM sa1_catalog_source'.($kind==='airing'?" WHERE airing_status<>''":''))->fetch();
    }
    $out[$kind] = array_map('intval',$r);
  }
  $out['servers'] = array_map('intval',sql($db,'SELECT COUNT(*) AS total,SUM(CASE WHEN mirrors_at>0 THEN 1 ELSE 0 END) AS checked,MIN(CASE WHEN mirrors_at>0 THEN mirrors_at END) AS oldest,MAX(mirrors_at) AS newest FROM sa1_episodes')->fetch());
  return $out;
}
function catalog_task_key(string $kind, string $target): string { return hash('sha256',$kind.':'.$target); }
function catalog_enqueue(PDO $db, string $kind, string $target, array $payload = [], int $priority = 10): void
{
  $key = catalog_task_key($kind,$target);
  $old = sql($db,'SELECT * FROM sa1_catalog_tasks WHERE task_key=?',[$key])->fetch();
  if ($old && in_array($old['state'],['pending','running'],true)) return;
  if ($old && $old['state']==='failed') return; // Explicit administrator retry only after quarantine.
  $row = ['task_key'=>$key,'kind'=>$kind,'target'=>$target,'payload'=>json_encode($payload),'state'=>'pending','priority'=>$priority,
    'attempts'=>0,'next_retry'=>0,'lock_until'=>0,'error'=>'','created_at'=>time(),'updated_at'=>time()];
  upsert($db,'sa1_catalog_tasks',array_keys($row),[$row],['task_key'],array_slice(array_keys($row),1));
}
function catalog_task_status(PDO $db, string $kind, string $target): ?array
{
  $row = sql($db,'SELECT state,attempts,next_retry,updated_at FROM sa1_catalog_tasks WHERE task_key=?',[catalog_task_key($kind,$target)])->fetch();
  return $row ?: null;
}
function catalog_request(PDO $db, array $input): array
{
  $user = member(); $slug = (string)($input['slug']??''); find_anime($db,$slug);
  $kind = isset($input['episode_id']) ? 'mirrors' : 'detail'; $target = $slug;
  if ($kind==='mirrors') {
    $ep = sql($db,'SELECT * FROM sa1_episodes WHERE id=? AND slug=?',[(int)$input['episode_id'],$slug])->fetch();
    if (!$ep) throw new WebError('Capítulo no encontrado.',404);
    $target = (string)$ep['id']; $fresh = (int)$ep['mirrors_at'] > time()-1800;
  } else $fresh = catalog_freshness($db,$slug)['episodes_at'] > time()-3600;
  $old = catalog_task_status($db,$kind,$target);
  if (!$fresh && (!$old || $old['state']==='done')) {
    rate($db,'catalog-request-user:'.$user,8,3600);
    rate($db,'catalog-request-global',60,3600);
    if ((int)sql($db,"SELECT COUNT(*) FROM sa1_catalog_tasks WHERE priority>=10 AND state IN ('pending','running')")->fetchColumn()>=100)
      throw new WebError('La cola de actualización está llena. Intenta más tarde.',429);
    catalog_enqueue($db,$kind,$target,[],10);
  }
  return ['task'=>$fresh ? ['state'=>'done'] : catalog_task_status($db,$kind,$target),
    'message'=>$fresh?'Los datos ya están actualizados.':catalog_request_message(catalog_task_status($db,$kind,$target)),
    'detail'=>detail($db,$slug)];
}
function catalog_prepare_cycle(PDO $db): void
{
  if ((int)meta($db,'directory_next_cycle','0')>time()) return;
  if (sql($db,"SELECT task_key FROM sa1_catalog_tasks WHERE kind IN ('directory','latest') AND state<>'done' LIMIT 1")->fetchColumn()) return;
  // Recursive year partitions bypass the source's 1,000-result ceiling without
  // assuming that a title belongs to the currently signed-in user's MAL list.
  catalog_enqueue($db,'directory','1900:2199:1',['low'=>1900,'high'=>2199,'page'=>1],5);
  // The unfiltered recent pages also discover new titles without a premiere year.
  catalog_enqueue($db,'latest','page:1',['page'=>1],5);
  set_meta($db,'directory_cycle_started',(string)time());
  set_meta($db,'directory_next_cycle',(string)(time()+604800));
}
function catalog_jobs_status(PDO $db): array
{
  $counts = ['pending'=>0,'running'=>0,'failed'=>0];
  foreach(sql($db,'SELECT state,COUNT(*) AS n FROM sa1_catalog_tasks GROUP BY state')->fetchAll() as $r) if(isset($counts[$r['state']])) $counts[$r['state']] = (int)$r['n'];
  return $counts + ['cycle_started'=>(int)meta($db,'directory_cycle_started','0'),'cycle_completed'=>(int)meta($db,'directory_cycle_completed','0')];
}
function catalog_restart_partition(PDO $db,array $job,array $payload): array
{
  if ($job['kind']==='directory') {
    $target=$payload['low'].':'.$payload['high'].':1';$payload=['low'=>$payload['low'],'high'=>$payload['high'],'page'=>1];
  } else {$target='page:1';$payload=['page'=>1];}
  catalog_enqueue($db,$job['kind'],$target,$payload,5);
  sql($db,"UPDATE sa1_catalog_tasks SET state='done',lock_until=0,updated_at=? WHERE task_key=?",[time(),$job['task_key']]);
  return ['skipped'=>false,'restarted'=>true,'remaining'=>catalog_jobs_status($db)['pending'],'reason'=>'El origen cambió durante la lectura. Se reinició solo la partición afectada.'];
}
function catalog_jobs_step(PDO $db, bool $interactiveOnly=false): array
{
  if($interactiveOnly)member();
  elseif (!(defined('SEASON_SYSTEM_REFRESH') && SEASON_SYSTEM_REFRESH)) admin_member($db);
  if(!$interactiveOnly)catalog_prepare_cycle($db);
  // Share a global lease with all central catalog jobs, including stale-lease recovery.
  upsert($db,'sa1_meta',['name','value'],[['name'=>'catalog_job_lock','value'=>'0']],['name'],['name']);
  $old = meta($db,'catalog_job_lock','0'); $lease = (string)(time()+45);
  if ((int)$old>time() || sql($db,'UPDATE sa1_meta SET value=? WHERE name=? AND value=?',[$lease,'catalog_job_lock',$old])->rowCount()!==1)
    return ['skipped'=>true,'reason'=>'Hay otra actualización en curso.','remaining'=>1];
  $job = null;
  try {
    sql($db,"UPDATE sa1_catalog_tasks SET state='pending' WHERE state='running' AND lock_until<?",[time()]);
    $tick = (int)meta($db,'catalog_job_tick','0')+1; set_meta($db,'catalog_job_tick',(string)$tick);
    // One oldest detail every fifth step prevents user requests or discovery starving metadata renewal.
    if (!$interactiveOnly && ($tick%5===0 || !(int)sql($db,"SELECT COUNT(*) FROM sa1_catalog_tasks WHERE state='pending' AND next_retry<=?",[time()])->fetchColumn())) {
      $a = sql($db,"SELECT a.slug FROM sa1_anime a LEFT JOIN sa1_catalog_freshness f ON f.slug=a.slug WHERE COALESCE(f.episodes_at,0)<CAST(? AS SIGNED) AND NOT EXISTS(SELECT 1 FROM sa1_catalog_tasks t WHERE t.kind='detail' AND t.target=a.slug AND t.state IN ('pending','running','failed')) ORDER BY COALESCE(f.episodes_at,0),a.active DESC,a.slug LIMIT 1",[time()-2592000])->fetch();
      if ($a) catalog_enqueue($db,'detail',$a['slug'],[],0);
    }
    $order = $tick%5===0 ? 'priority ASC,created_at,task_key' : 'priority DESC,created_at,task_key';
    $filter=$interactiveOnly?" AND priority>=10 AND kind IN ('mirrors','detail')":'';
    if($interactiveOnly)$order="CASE WHEN kind='mirrors' THEN 0 ELSE 1 END,created_at,task_key";
    $job = sql($db,"SELECT * FROM sa1_catalog_tasks WHERE state='pending' AND next_retry<=?$filter ORDER BY $order LIMIT 1",[time()])->fetch();
    if (!$job) return ['skipped'=>true,'remaining'=>catalog_jobs_status($db)['pending'],'reason'=>'Los trabajos restantes esperan su reintento.'];
    sql($db,"UPDATE sa1_catalog_tasks SET state='running',lock_until=?,updated_at=? WHERE task_key=?",[time()+40,time(),$job['task_key']]);
    if(in_array($job['kind'],['detail','mirrors'],true)){
      $target=$job['kind']==='mirrors'?sql($db,'SELECT slug,number FROM sa1_episodes WHERE id=?',[(int)$job['target']])->fetch():['slug'=>$job['target']];
      if(!$target)throw new RuntimeException('Capítulo inexistente.');
      $GLOBALS['season_scrape_task']=['path'=>'/media/'.$target['slug'].($job['kind']==='mirrors'?'/'.$target['number']:''),'interactive'=>$job['kind']==='mirrors'];
    }
    release_remote_session();
    usleep(2100000);
    if ($job['kind']==='detail') sync_anime($db,$job['target']);
    elseif ($job['kind']==='mirrors') {
      $ep = sql($db,'SELECT * FROM sa1_episodes WHERE id=?',[(int)$job['target']])->fetch();
      if ($ep) episode_mirrors($db,$ep);
    } elseif ($job['kind']==='latest') {
      $p=json_decode($job['payload'],true,16,JSON_THROW_ON_ERROR);
      $progress=sync_directory_page($db,(int)$p['page']);
      if (isset($p['total']) && $p['total']!==$progress['total']) return catalog_restart_partition($db,$job,$p);
      if ($p['page']<$progress['pages']) {
        $next=$p['page']+1;catalog_enqueue($db,'latest','page:'.$next,['page'=>$next,'total'=>$progress['total']],5);
      }
    } elseif ($job['kind']==='directory') {
      $p = json_decode($job['payload'],true,16,JSON_THROW_ON_ERROR);
      $progress = sync_directory_partition($db,(int)$p['low'],(int)$p['high'],(int)$p['page']);
      if (isset($p['total']) && $p['total']!==$progress['total']) return catalog_restart_partition($db,$job,$p);
      if ($progress['total']>=1000) {
        if ($p['low']===$p['high']) throw new ScraperError('Una partición anual supera el límite del origen. Requiere revisión.');
        $mid = intdiv($p['low']+$p['high'],2);
        foreach([[$p['low'],$mid],[$mid+1,$p['high']]] as [$low,$high]) catalog_enqueue($db,'directory',"$low:$high:1",['low'=>$low,'high'=>$high,'page'=>1],5);
      } elseif ($p['page']<$progress['pages']) {
        $next = $p['page']+1;
        catalog_enqueue($db,'directory',"{$p['low']}:{$p['high']}:$next",['low'=>$p['low'],'high'=>$p['high'],'page'=>$next,'total'=>$progress['total']],5);
      }
    } else throw new RuntimeException('Tipo de trabajo no permitido.');
    sql($db,"UPDATE sa1_catalog_tasks SET state='done',error='',lock_until=0,updated_at=? WHERE task_key=?",[time(),$job['task_key']]);
    if (!(int)sql($db,"SELECT COUNT(*) FROM sa1_catalog_tasks WHERE kind IN ('directory','latest') AND state<>'done'")->fetchColumn()) set_meta($db,'directory_cycle_completed',(string)time());
    calendar_refresh_feeds($db);
    return ['skipped'=>false,'updated_slug'=>$job['kind']==='detail'?$job['target']:null,'updated_kind'=>$job['kind'],'remaining'=>max(1,catalog_jobs_status($db)['pending'])];
  } catch (Throwable $error) {
    if (!$job) throw $error;
    if ($error instanceof WebError && $error->status===429) {
      sql($db,"UPDATE sa1_catalog_tasks SET state='pending',next_retry=?,lock_until=0,updated_at=? WHERE task_key=?",[time()+300,time(),$job['task_key']]);
      return ['skipped'=>true,'remaining'=>catalog_jobs_status($db)['pending'],'reason'=>'Se alcanzó el límite de peticiones. El catálogo continuará después de una pausa.'];
    }
    $attempts = (int)$job['attempts']+1;
    sql($db,'UPDATE sa1_catalog_tasks SET state=?,attempts=?,next_retry=?,lock_until=0,error=?,updated_at=? WHERE task_key=?',
      [$attempts>=5?'failed':'pending',$attempts,time()+min(3600,60*2**min(6,$attempts-1)),mb_substr($error->getMessage(),0,500),time(),$job['task_key']]);
    record_scraper_failure($db,'Actualización del catálogo: '.$error->getMessage());
    return ['skipped'=>false,'failed_slug'=>$job['target'],'remaining'=>catalog_jobs_status($db)['pending']];
  } finally { unset($GLOBALS['season_scrape_task']); sql($db,'UPDATE sa1_meta SET value=? WHERE name=? AND value=?',['0','catalog_job_lock',$lease]); }
}
function saved_filters(PDO $db): array
{
  $rows = sql($db,'SELECT id,name,filters,updated_at FROM sa1_saved_filters WHERE user_id=? ORDER BY name',[member()])->fetchAll();
  foreach($rows as &$r) { $r['id']=(int)$r['id']; $r['filters']=json_decode($r['filters'],true); }
  return $rows;
}
function dispatch_catalog_updates(PDO $db, string $action, array $input): ?array
{
  if ($action==='catalog_request') return catalog_request($db,$input);
  if ($action==='saved_filters') return ['saved_filters'=>saved_filters($db)];
  if ($action==='save_filter') {
    $user = member(); $name = trim((string)($input['name']??'')); $filters = $input['filters']??null;
    if (!$name || mb_strlen($name)>60 || !is_array($filters) || strlen(json_encode($filters))>12000) throw new WebError('Revisa el nombre y los filtros.');
    $allowed = ['search','category','scope','order','year','airing','season','letter','library','download','language','unwatched','include_genres','exclude_genres','genre_mode'];
    $filters = array_intersect_key($filters,array_flip($allowed));
    foreach($filters as $k=>$v) if ($k==='include_genres'||$k==='exclude_genres') catalog_genre_values($v); elseif(!is_string($v) || mb_strlen($v)>120) throw new WebError('Filtro inválido.');
    catalog($db,$filters); // Validate against the same rules used to query, including personal scopes.
    if ((int)sql($db,'SELECT COUNT(*) FROM sa1_saved_filters WHERE user_id=?',[uid()])->fetchColumn()>=30 && !sql($db,'SELECT id FROM sa1_saved_filters WHERE user_id=? AND name=?',[uid(),$name])->fetchColumn()) throw new WebError('Puedes guardar hasta 30 búsquedas.');
    upsert($db,'sa1_saved_filters',['user_id','name','filters','updated_at'],[['user_id'=>$user,'name'=>$name,'filters'=>json_encode($filters),'updated_at'=>time()]],['user_id','name'],['filters','updated_at']);
    return ['saved_filters'=>saved_filters($db),'message'=>'Búsqueda guardada.'];
  }
  if ($action==='delete_filter') {
    sql($db,'DELETE FROM sa1_saved_filters WHERE user_id=? AND id=?',[member(),(int)($input['id']??0)]);
    return ['saved_filters'=>saved_filters($db)];
  }
  if ($action==='catalog_retry') {
    admin_member($db); rate($db,'catalog-retry',1,60);
    sql($db,"UPDATE sa1_catalog_tasks SET state='pending',attempts=0,next_retry=0,lock_until=0 WHERE state='failed'");
    return ['home'=>home_data($db),'message'=>'Trabajos fallidos listos para reintentar.'];
  }
  return null;
}
