<?php
declare(strict_types=1);
if(!defined('SEASON_BOOTSTRAPPED')){http_response_code(404);exit();}

function personal_rows(PDO $db,string $kind): array
{
  $out=[];foreach(sql($db,'SELECT item_key,payload,updated_at FROM sa1_personal_data WHERE user_id=? AND kind=? ORDER BY updated_at DESC',[member(),$kind])->fetchAll() as $r){
    $data=json_decode($r['payload'],true);if(is_array($data))$out[]=['key'=>$r['item_key'],'data'=>$data,'updated_at'=>(int)$r['updated_at']];
  }return $out;
}
function personal_get(PDO $db,string $kind,string $key): array
{
  return json_decode(sql($db,'SELECT payload FROM sa1_personal_data WHERE user_id=? AND kind=? AND item_key=?',[member(),$kind,$key])->fetchColumn()?:'{}',true)?:[];
}
function personal_validate(PDO $db,string $kind,string $key,mixed $data): array
{
  if(!is_array($data)||strlen(json_encode($data))>150000)throw new WebError('Datos personales inválidos.');
  if($kind==='intro'){
    find_anime($db,$key);$start=$data['start']??null;$end=$data['end']??null;
    if(!is_numeric($start)||!is_numeric($end)||!is_finite((float)$start)||!is_finite((float)$end)||$start<0||$end<=$start||$end>3600||$end-$start>600)throw new WebError('La intro debe tener inicio y final válidos (hasta diez minutos).');
    return ['start'=>(float)$start,'end'=>(float)$end];
  }
  if($kind==='collection'){
    if(!preg_match('/^[a-f0-9]{16}$/D',$key)||!is_string($data['name']??null)||!trim($data['name'])||mb_strlen($data['name'])>60||!is_array($data['slugs']??null)||count($data['slugs'])>1000)throw new WebError('Colección inválida.');
    $slugs=[];foreach($data['slugs'] as $slug){if(!is_string($slug))throw new WebError('Anime inválido.');find_anime($db,$slug);$slugs[]=$slug;}
    return ['name'=>trim($data['name']),'slugs'=>array_values(array_unique($slugs))];
  }
  if($kind==='bookmark'){
    if(!preg_match('/^[a-f0-9]{32}$/D',$key)||!is_string($data['slug']??null)||!is_string($data['number']??null)||!is_numeric($data['position']??null)||!is_finite((float)$data['position'])||$data['position']<0||$data['position']>43200||!is_string($data['note']??null)||mb_strlen($data['note'])>500)throw new WebError('Marcador inválido.');
    if(!sql($db,'SELECT id FROM sa1_episodes WHERE slug=? AND number=?',[$data['slug'],$data['number']])->fetchColumn())throw new WebError('El capítulo del marcador no está disponible.');
    return ['slug'=>$data['slug'],'number'=>$data['number'],'position'=>(float)$data['position'],'note'=>$data['note']];
  }
  if($kind==='radio'&&$key==='library'){
    $tracks=json_decode(file_get_contents(dirname(__DIR__).'/data/radio.json'),true);
    // Invalid/unavailable entries remain importable as saved IDs, but are never played automatically.
    $ids=function($values){if(!is_array($values)||count($values)>300)throw new WebError('Lista musical inválida.');foreach($values as $id)if(!is_string($id)||!preg_match('/^[\w-]{11}$/D',$id))throw new WebError('Canción inválida.');return array_values(array_unique($values));};
    if(!is_array($data['lists']??null)||count($data['lists'])>20)throw new WebError('Puedes guardar hasta veinte listas musicales.');
    $lists=[];foreach($data['lists'] as $l){if(!is_array($l)||!preg_match('/^[a-f0-9]{16}$/D',(string)($l['id']??''))||!is_string($l['name']??null)||!trim($l['name'])||mb_strlen($l['name'])>60)throw new WebError('Lista musical inválida.');$lists[$l['id']]=['id'=>$l['id'],'name'=>trim($l['name']),'ids'=>$ids($l['ids']??null)];}
    return ['favorites'=>$ids($data['favorites']??null),'lists'=>array_values($lists)];
  }
  if($kind==='options'&&$key==='account')return ['shared'=>(bool)($data['shared']??false),'forget_pc'=>(bool)($data['forget_pc']??false),'onboarding_done'=>(bool)($data['onboarding_done']??false)];
  throw new WebError('Tipo de dato personal inválido.');
}
function personal_store(PDO $db,string $kind,string $key,array $data,?string $expected=null): array
{
  $data=personal_validate($db,$kind,$key,$data);
  $current=personal_get($db,$kind,$key);
  $limit=['collection'=>30,'bookmark'=>1000,'intro'=>5000,'radio'=>1,'options'=>1][$kind];
  if(!$current&&(int)sql($db,'SELECT COUNT(*) FROM sa1_personal_data WHERE user_id=? AND kind=?',[uid(),$kind])->fetchColumn()>=$limit)throw new WebError('Se alcanzó el límite de elementos guardados.');
  $data['revision']=bin2hex(random_bytes(16));$payload=json_encode($data,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE);
  if($expected!==null&&$current){
    if(!hash_equals((string)($current['revision']??''),$expected))throw new WebError('Estos datos cambiaron en otro dispositivo. Recarga antes de guardar.',409);
    $old=json_encode($current,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE);
    if(sql($db,'UPDATE sa1_personal_data SET payload=?,updated_at=? WHERE user_id=? AND kind=? AND item_key=? AND payload=?',[$payload,time(),uid(),$kind,$key,$old])->rowCount()!==1)throw new WebError('Otro dispositivo guardó cambios. Recarga antes de continuar.',409);
  }else{
    if($expected!==null&&$expected!=='')throw new WebError('Estos datos ya no existen. Recarga antes de continuar.',409);
    if($expected===''){
      try{sql($db,'INSERT INTO sa1_personal_data(user_id,kind,item_key,payload,updated_at) VALUES(?,?,?,?,?)',[uid(),$kind,$key,$payload,time()]);}
      catch(PDOException $e){if(personal_get($db,$kind,$key))throw new WebError('Otra pestaña creó la biblioteca musical. Recarga para combinar tus cambios.',409);throw $e;}
    }else upsert($db,'sa1_personal_data',['user_id','kind','item_key','payload','updated_at'],[['user_id'=>uid(),'kind'=>$kind,'item_key'=>$key,'payload'=>$payload,'updated_at'=>time()]],['user_id','kind','item_key'],['payload','updated_at']);
  }return $data;
}
function personal_player(PDO $db,array $episode): array
{
  $bookmarks=array_values(array_filter(personal_rows($db,'bookmark'),fn($r)=>$r['data']['slug']===$episode['slug']&&$r['data']['number']===$episode['number']));
  return ['intro'=>personal_get($db,'intro',$episode['slug']),'bookmarks'=>$bookmarks];
}
function player_read_state(PDO $db,array $input): array
{
  member();$id=(int)($input['episode_id']??0);
  return ['player_state'=>sql($db,'SELECT mode,position,duration,updated_at FROM sa1_playback WHERE user_id=? AND episode_id=? ORDER BY updated_at DESC LIMIT 1',[uid(),$id])->fetch()?:null];
}
function catalog_request_message(?array $task): string
{
  return match($task['state']??'pending'){
    'failed'=>'La actualización falló tras varios intentos. El administrador debe revisarla antes de reintentarlo.',
    'running'=>'Esta actualización ya se está procesando.',
    'done'=>'La actualización terminó. Los datos están disponibles.',
    default=>!empty($task['attempts'])?'La actualización espera su próximo reintento.':'Solicitud pendiente en la cola central. Se procesará en una visita activa a la web.',
  };
}
function sync_inbox(PDO $db): array
{
  $rows=sql($db,'SELECT s.slug,a.title,s.state,s.target,s.error_kind,s.attempts,s.next_retry,s.updated_at,k.mal_id,k.confirmed FROM sa1_watch_sync s JOIN sa1_anime a ON a.slug=s.slug LEFT JOIN sa1_mal_links k ON k.user_id=s.user_id AND k.slug=s.slug WHERE s.user_id=? ORDER BY s.updated_at DESC LIMIT 200',[member()])->fetchAll();
  foreach($rows as &$r)$r['message']=watch_sync_result($db,$r['slug'])['message'];
  return $rows;
}
function saga_watch_path(PDO $db,array $anime): array
{
  $rows=sql($db,"SELECT a.slug,a.title,a.start_date,r.relation FROM sa1_relations r JOIN sa1_anime a ON a.slug=r.target WHERE r.slug=? AND r.state='approved' AND r.relation IN ('prequel','sequel','season','movie','special') ORDER BY a.start_date,a.title LIMIT 30",[$anime['slug']])->fetchAll();
  if(!$rows)return [];
  $prior=[];$after=[];foreach($rows as $r){if($r['relation']==='prequel')$prior[]=$r;else $after[]=$r;}
  $out=array_merge($prior,[['slug'=>$anime['slug'],'title'=>$anime['title'],'relation'=>'current']],$after);
  $slugs=array_column($out,'slug');$marks=implode(',',array_fill(0,count($slugs),'?'));$progress=[];
  foreach(sql($db,"SELECT a.slug,(SELECT COUNT(*) FROM sa1_episodes e WHERE e.slug=a.slug) AS total,(SELECT COUNT(*) FROM sa1_watched w JOIN sa1_episodes e ON e.id=w.episode_id WHERE w.user_id=? AND e.slug=a.slug) AS local_count,(SELECT l.watched FROM sa1_mal_links k JOIN sa1_mal_list l ON l.user_id=k.user_id AND l.mal_id=k.mal_id WHERE k.user_id=? AND k.slug=a.slug) AS mal_count FROM sa1_anime a WHERE a.slug IN ($marks)",array_merge([uid(),uid()],$slugs))->fetchAll() as $r)$progress[$r['slug']]=$r;
  foreach($out as &$r){$p=$progress[$r['slug']];$r['total']=(int)$p['total'];$r['watched']=max((int)$p['local_count'],(int)$p['mal_count']);}

  return $out;
}
function personal_export(PDO $db): array
{
  $data=[];foreach(['intro','bookmark','collection','radio','options'] as $kind)$data[$kind]=personal_rows($db,$kind);
  $data['positions']=sql($db,"SELECT e.slug,e.number,p.position,p.duration FROM sa1_playback p JOIN sa1_episodes e ON e.id=p.episode_id WHERE p.user_id=? AND p.mode='first' ORDER BY p.updated_at DESC LIMIT 10000",[member()])->fetchAll();
  $data['filters']=saved_filters($db);$data['player_preferences']=player_preferences($db,'');return $data;
}
function personal_import_validate(PDO $db,array $extra): array
{
  if(strlen(json_encode($extra))>8*1024*1024||array_diff(array_keys($extra),['intro','bookmark','collection','radio','options','positions','filters','player_preferences']))throw new WebError('Datos extra inválidos.');
  $out=[];foreach(['intro','bookmark','collection','radio','options'] as $kind){$rows=$extra[$kind]??[];if(!is_array($rows)||count($rows)>(['intro'=>5000,'bookmark'=>1000,'collection'=>30,'radio'=>1,'options'=>1][$kind]))throw new WebError('Demasiados elementos en la copia.');foreach($rows as $r){if(!is_array($r)||!is_string($r['key']??null))throw new WebError('Elemento inválido en la copia.');$out[$kind][]=['key'=>$r['key'],'data'=>personal_validate($db,$kind,$r['key'],$r['data']??null)];}}
  $out['positions']=[];$positions=$extra['positions']??[];if(!is_array($positions)||count($positions)>10000)throw new WebError('Posiciones inválidas.');
  foreach($positions as $p){if(!is_array($p)||!is_string($p['slug']??null)||!is_string($p['number']??null)||!is_numeric($p['position']??null)||!is_numeric($p['duration']??null)||!is_finite((float)$p['position'])||!is_finite((float)$p['duration'])||$p['position']<0||$p['duration']<=0||$p['duration']>43200||$p['position']>$p['duration'])throw new WebError('Una posición es inválida.');$id=sql($db,'SELECT id FROM sa1_episodes WHERE slug=? AND number=?',[$p['slug'],$p['number']])->fetchColumn();if($id)$out['positions'][]=['episode_id'=>(int)$id,'position'=>(float)$p['position'],'duration'=>(float)$p['duration']];}
  $filters=$extra['filters']??[];if(!is_array($filters)||count($filters)>30)throw new WebError('Filtros inválidos.');
  foreach($filters as $f){if(!is_array($f)||!is_string($f['name']??null)||!trim($f['name'])||mb_strlen($f['name'])>60||!is_array($f['filters']??null)||strlen(json_encode($f['filters']))>12000)throw new WebError('Filtro inválido.');catalog($db,$f['filters']);$out['filters'][]=['name'=>trim($f['name']),'filters'=>$f['filters']];}
  $p=$extra['player_preferences']??[];if(!is_array($p))throw new WebError('Preferencias inválidas.');
  $out['player_preferences']=[];foreach(['volume','muted','rate','server','language'] as $k)if(array_key_exists($k,$p)){
    $v=$p[$k];if(($k==='volume'&&(!is_numeric($v)||$v<0||$v>1))||($k==='muted'&&!is_bool($v))||($k==='rate'&&!in_array($v,[0.5,0.75,1,1.25,1.5,1.75,2],true))||($k==='server'&&!in_array($v,['MP4Upload','Voe'],true))||($k==='language'&&!in_array($v,['SUB','LAT','DUB'],true)))throw new WebError('Preferencia inválida.');$out['player_preferences'][$k]=$v;
  }return $out;
}
function personal_import_apply(PDO $db,array $data): void
{
  foreach(['intro','bookmark','collection','radio','options'] as $kind)foreach($data[$kind]??[] as $r)personal_store($db,$kind,$r['key'],$r['data']);
  foreach($data['positions']??[] as $p){$row=['user_id'=>uid(),'mode'=>'first','session_key'=>bin2hex(random_bytes(16)),'sequence_no'=>0,'updated_at'=>time()]+$p;upsert($db,'sa1_playback',array_keys($row),[$row],['user_id','episode_id','mode'],['position','duration','session_key','sequence_no','updated_at']);}
  foreach($data['filters']??[] as $f){if((int)sql($db,'SELECT COUNT(*) FROM sa1_saved_filters WHERE user_id=?',[uid()])->fetchColumn()>=30&&!sql($db,'SELECT id FROM sa1_saved_filters WHERE user_id=? AND name=?',[uid(),$f['name']])->fetchColumn())continue;$r=['user_id'=>uid(),'name'=>$f['name'],'filters'=>json_encode($f['filters']),'updated_at'=>time()];upsert($db,'sa1_saved_filters',array_keys($r),[$r],['user_id','name'],['filters','updated_at']);}
  if($data['player_preferences']??[]){$r=['user_id'=>uid(),'settings'=>json_encode($data['player_preferences'])];upsert($db,'sa1_player_preferences',array_keys($r),[$r],['user_id'],['settings']);}
}
function dispatch_personal(PDO $db,string $action,array $input): ?array
{
  if($action==='queue_page'){
    member();$slug=(string)($input['slug']??'');find_anime($db,$slug);$phase=(string)($input['phase']??'all');
    if(!in_array($phase,['all','queued','confirmed','cancelled','downloading','verifying','paused','failed'],true))throw new WebError('Estado inválido.');
    $args=[uid(),$slug];$where='j.user_id=? AND e.slug=?';
    if($phase==='queued')$where.=" AND j.status IN ('pending','exported')";
    elseif(in_array($phase,['confirmed','cancelled'],true)){$where.=' AND j.status=?';$args[]=$phase;}
    elseif($phase!=='all'){$where.=" AND j.status IN ('pending','exported') AND EXISTS(SELECT 1 FROM sa1_job_events ev WHERE ev.user_id=j.user_id AND ev.job_id=j.id AND ev.state=? AND ev.updated_at=(SELECT MAX(ev2.updated_at) FROM sa1_job_events ev2 WHERE ev2.user_id=j.user_id AND ev2.job_id=j.id))";$args[]=$phase;}
    $from=' FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id JOIN sa1_anime a ON a.slug=e.slug WHERE '.$where;
    $total=(int)sql($db,'SELECT COUNT(*)'.$from,$args)->fetchColumn();$pages=max(1,(int)ceil($total/36));$page=max(1,min($pages,(int)($input['page']??1)));
    $rows=sql($db,'SELECT j.*,e.slug,e.number,a.title,a.cover'.$from.' ORDER BY e.number_value,j.language,j.id LIMIT 36 OFFSET '.(($page-1)*36),$args)->fetchAll();
    $ids=array_column($rows,'id');$events=[];if($ids)$events=sql($db,'SELECT * FROM sa1_job_events WHERE user_id=? AND job_id IN ('.implode(',',array_fill(0,count($ids),'?')).') ORDER BY updated_at DESC',array_merge([uid()],$ids))->fetchAll();
    foreach($rows as &$row){foreach($events as $event)if((int)$event['job_id']===(int)$row['id']){$row['last_pc_state']=$event;break;}}unset($row);
    return ['queue_page'=>['slug'=>$slug,'page'=>$page,'pages'=>$pages,'total'=>$total,'items'=>$rows,'events'=>$events]];
  }
  if($action==='personal'){
    $collections=personal_rows($db,'collection');$slugs=[];foreach($collections as $c)foreach($c['data']['slugs'] as $slug)$slugs[$slug]=true;$titles=[];
    foreach(array_chunk(array_keys($slugs),100) as $batch)foreach(sql($db,'SELECT slug,title FROM sa1_anime WHERE slug IN ('.implode(',',array_fill(0,count($batch),'?')).')',$batch)->fetchAll() as $a)$titles[$a['slug']]=$a['title'];
    return ['personal'=>['user_id'=>member(),'collections'=>$collections,'collection_titles'=>$titles,'radio'=>personal_get($db,'radio','library'),'options'=>personal_get($db,'options','account')]];
  }
  if($action==='sync_inbox')return ['sync_inbox'=>sync_inbox($db)];
  if(in_array($action,['player_notes','player_cached_servers'],true)){
    member();$episode=sql($db,'SELECT * FROM sa1_episodes WHERE id=?',[(int)($input['episode_id']??0)])->fetch();if(!$episode)throw new WebError('Capítulo no encontrado.',404);
    return $action==='player_notes'?['personal'=>personal_player($db,$episode)]:['player_servers'=>player_servers_data($db,$episode)];
  }
  if(in_array($action,['personal_save','personal_delete'],true)){
    member();rate($db,'personal-write:'.uid(),120,3600);$kind=(string)($input['kind']??'');$key=(string)($input['key']??'');
    if($action==='personal_delete'){
      if(!in_array($kind,['intro','bookmark','collection'],true)||strlen($key)>240)throw new WebError('Elemento inválido.');
      sql($db,'DELETE FROM sa1_personal_data WHERE user_id=? AND kind=? AND item_key=?',[uid(),$kind,$key]);return ['message'=>'Elemento eliminado.'];
    }
    $expected=$input['expected_revision']??null;if($expected!==null&&(!is_string($expected)||($expected!==''&&!preg_match('/^[a-f0-9]{32}$/D',$expected))))throw new WebError('Revisión inválida.');
    return ['saved'=>personal_store($db,$kind,$key,$input['data']??[],$expected),'message'=>'Guardado en tu cuenta.'];
  }
  if($action==='mal_confirm'){
    member();$slug=(string)($input['slug']??'');$id=(int)($input['mal_id']??0);$account=mal_identity_id($db);
    if(!$account||($input['mal_account_id']??null)!==$account||($input['confirmation']??'')!=='CONFIRMAR')throw new WebError('La cuenta cambió o falta confirmar la ficha.',409);
    if(!sql($db,'SELECT mal_id FROM sa1_mal_links WHERE user_id=? AND slug=? AND mal_id=?',[uid(),$slug,$id])->fetchColumn())throw new WebError('El vínculo cambió. Reabre la ficha.',409);
    sql($db,'UPDATE sa1_mal_links SET confirmed=1 WHERE user_id=? AND slug=? AND mal_id=?',[uid(),$slug,$id]);watch_sync_pending($db);
    return ['message'=>'Ficha MAL confirmada. Los vistos pendientes podrán sincronizarse.','patch'=>state_patch($db,[$slug]),'home'=>home_data($db)];
  }
  if($action==='catalog_pulse'){
    member();rate($db,'catalog-pulse-user:'.uid(),12,3600);rate($db,'catalog-pulse-global',60,3600);
    return ['catalog_worker'=>catalog_jobs_step($db,true)];
  }
  if($action==='catalog_task'){
    member();$slug=(string)($input['slug']??'');find_anime($db,$slug);$kind='detail';$target=$slug;
    if(isset($input['episode_id'])){$ep=sql($db,'SELECT id FROM sa1_episodes WHERE id=? AND slug=?',[(int)$input['episode_id'],$slug])->fetchColumn();if(!$ep)throw new WebError('Capítulo no encontrado.',404);$kind='mirrors';$target=(string)$ep;}
    $task=catalog_task_status($db,$kind,$target);return ['task'=>$task,'message'=>catalog_request_message($task)];
  }
  if($action==='player_prefetch'){
    member();$ep=sql($db,'SELECT * FROM sa1_episodes WHERE id=?',[(int)($input['episode_id']??0)])->fetch();if(!$ep)throw new WebError('Capítulo no encontrado.',404);
    rate($db,'player-prefetch:'.uid(),30,3600);$next=sql($db,'SELECT * FROM sa1_episodes WHERE slug=? AND number_value>? ORDER BY number_value LIMIT 1',[$ep['slug'],$ep['number_value']])->fetch();
    if(!$next)return ['prefetch'=>null];
    if((int)$next['mirrors_at']<time()-1800){rate($db,'catalog-request-user:'.uid(),8,3600);rate($db,'catalog-request-global',60,3600);catalog_enqueue($db,'mirrors',(string)$next['id'],[],10);}
    return ['prefetch'=>['episode_id'=>(int)$next['id'],'servers'=>player_servers_data($db,$next)['servers']]];
  }
  if($action==='download_events'){
    member();$device=(string)($input['device_id']??'');$items=$input['items']??[];
    if(!preg_match('/^[a-f0-9]{32,64}$/D',$device)||!is_array($items)||count($items)>200||($input['installation']??'')!==meta($db,'installation'))throw new WebError('Estado de PC inválido.');
    $candidates=[];
    foreach($items as $item){
      if(!is_array($item))throw new WebError('Estado de descarga inválido.');
      $id=filter_var($item['id']??null,FILTER_VALIDATE_INT);$phase=$item['state']??'';$attempts=$item['attempts']??0;
      if($id===false||$id<1||!in_array($phase,['queued','downloading','verifying','paused','failed','completed'],true)||!is_int($attempts)||$attempts<0||$attempts>10000)throw new WebError('Estado de descarga inválido.');
      $error=in_array($item['error_kind']??'',['connection','server','disk','verification','unknown'],true)?$item['error_kind']:'';
      $candidates[$id]=['user_id'=>uid(),'job_id'=>$id,'device_id'=>$device,'state'=>$phase,'attempts'=>$attempts,'error_kind'=>$phase==='failed'?($error?:'unknown'):'','updated_at'=>time()];
    }
    $rows=[];
    if($candidates){
      $ids=array_keys($candidates);$valid=sql($db,"SELECT id FROM sa1_jobs WHERE user_id=? AND status IN ('pending','exported') AND id IN (".implode(',',array_fill(0,count($ids),'?')).')',array_merge([uid()],$ids))->fetchAll(PDO::FETCH_COLUMN);
      foreach($valid as $id)$rows[]=$candidates[(int)$id];
    }
    upsert($db,'sa1_job_events',['user_id','job_id','device_id','state','attempts','error_kind','updated_at'],$rows,['user_id','job_id','device_id'],['state','attempts','error_kind','updated_at']);
    return ['message'=>'Estados informados por la PC guardados.','patch'=>state_patch($db,[],array_column($items,'id'))];
  }
  if($action==='radio_report'){
    member();rate($db,'radio-report:'.uid(),5,3600);$id=(string)($input['track']??'');$reason=(string)($input['reason']??'');
    if(!preg_match('/^[\w-]{11}$/D',$id)||!in_array($reason,['association','unavailable','other'],true))throw new WebError('Reporte inválido.');
    $r=['user_id'=>uid(),'kind'=>'radio-report','item_key'=>$id,'payload'=>json_encode(['reason'=>$reason]),'updated_at'=>time()];upsert($db,'sa1_personal_data',array_keys($r),[$r],['user_id','kind','item_key'],['payload','updated_at']);
    return ['message'=>'Reporte enviado al panel de administración. Gracias.'];
  }
  if($action==='support_report'){
    admin_member($db);return ['report'=>['schema'=>SEASON_SCHEMA_VERSION,'release'=>defined('SEASON_RELEASE_ID')?SEASON_RELEASE_ID:'source','catalog'=>catalog_jobs_status($db),'radio_reports'=>sql($db,"SELECT item_key,payload,updated_at FROM sa1_personal_data WHERE kind='radio-report' ORDER BY updated_at DESC LIMIT 100")->fetchAll(),'errors'=>sql($db,'SELECT action,kind,occurrences,last_at FROM sa1_runtime_errors ORDER BY last_at DESC LIMIT 50')->fetchAll(),'generated_at'=>date(DATE_ATOM)]];
  }return null;
}
