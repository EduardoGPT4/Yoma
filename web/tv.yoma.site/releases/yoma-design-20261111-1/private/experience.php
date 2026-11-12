<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {http_response_code(404);exit();}
function watch_mode(PDO $db,string $slug): array
{
  $r=sql($db,'SELECT mode,revision,changed_at FROM sa1_watch_modes WHERE user_id=? AND slug=?',[uid(),$slug])->fetch();
  if(!$r){$r=['mode'=>'first','revision'=>bin2hex(random_bytes(16)),'changed_at'=>0];upsert($db,'sa1_watch_modes',['user_id','slug','mode','revision','changed_at'],[['user_id'=>uid(),'slug'=>$slug]+$r],['user_id','slug'],['slug']);$r=sql($db,'SELECT mode,revision,changed_at FROM sa1_watch_modes WHERE user_id=? AND slug=?',[uid(),$slug])->fetch();}
  return $r;
}
function player_preferences(PDO $db,string $slug): array
{
  $settings=preferences($db,uid());
  $global=json_decode(sql($db,'SELECT settings FROM sa1_player_preferences WHERE user_id=?',[uid()])->fetchColumn()?:'{}',true)?:[];
  return ['volume'=>0.8,'muted'=>false,'rate'=>1,'server'=>$settings['server'],'language'=>$settings['language'],...$global,'autoplay_next'=>true,'anime_override'=>false];
}
function playback_open(PDO $db,array $episode): array
{
  $mode=watch_mode($db,$episode['slug']);$key=bin2hex(random_bytes(16));
  $old=sql($db,'SELECT position,duration,updated_at FROM sa1_playback WHERE user_id=? AND episode_id=? AND mode=?',[uid(),$episode['id'],$mode['mode']])->fetch()?:['position'=>0,'duration'=>0,'updated_at'=>0];
  $row=['user_id'=>uid(),'episode_id'=>$episode['id'],'mode'=>$mode['mode'],'session_key'=>$key,'sequence_no'=>0]+$old;
  upsert($db,'sa1_playback',array_keys($row),[$row],['user_id','episode_id','mode'],['session_key','sequence_no']);
  return ['mode'=>$mode['mode'],'revision'=>$mode['revision'],'session_key'=>$key,'sequence'=>0,'position'=>(float)$old['position'],'duration'=>(float)$old['duration'],'preferences'=>player_preferences($db,$episode['slug'])];
}
function progress_fence(PDO $db,string $slug): void
{
  upsert($db,'sa1_watch_modes',['user_id','slug','mode','revision','changed_at'],[['user_id'=>uid(),'slug'=>$slug,'mode'=>'first','revision'=>bin2hex(random_bytes(16)),'changed_at'=>time()]],['user_id','slug'],['revision','mode','changed_at']);
}
function progress_reconcile_local(PDO $db,string $slug,int $target): void
{
  sql($db,'DELETE FROM sa1_watched WHERE user_id=? AND episode_id IN (SELECT id FROM sa1_episodes WHERE slug=? AND number_value>?)',[uid(),$slug,$target]);
  $rows=[];foreach(sql($db,'SELECT id,number_value FROM sa1_episodes WHERE slug=? AND number_value<=? AND number_value>=1',[$slug,$target])->fetchAll() as $ep)if((float)$ep['number_value']===(float)(int)$ep['number_value'])$rows[]=['user_id'=>uid(),'episode_id'=>$ep['id'],'watched_at'=>time()];
  upsert($db,'sa1_watched',['user_id','episode_id','watched_at'],$rows,['user_id','episode_id'],['watched_at']);
  sql($db,"DELETE FROM sa1_playback WHERE user_id=? AND mode='first' AND episode_id IN (SELECT id FROM sa1_episodes WHERE slug=? AND number_value>?)",[uid(),$slug,$target]);
}
function queue_preview(PDO $db,array $input): array
{
  member();$slugs=$input['slugs']??[];$mode=$input['mode']??'selected';$ids=$input['episode_ids']??[];
  if(!is_array($slugs)||!$slugs||count($slugs)>100||!is_array($ids)||count($ids)>2000||!in_array($mode,['all','selected'],true))throw new WebError('Selección inválida.');
  $settings=preferences($db,uid());$eligible=[];$counts=['requested'=>0,'eligible'=>0,'queued'=>0,'downloaded'=>0,'excluded'=>0];$sample=[];
  foreach(array_unique($slugs) as $slug){$a=find_anime($db,(string)$slug);if($mode==='all'&&!$a['catalog_complete'])throw new WebError('Solicita el listado completo antes de preparar todos.');
    $excluded=(bool)sql($db,'SELECT excluded FROM sa1_follow WHERE user_id=? AND slug=?',[uid(),$slug])->fetchColumn();
    foreach(sql($db,'SELECT e.id,e.number,j.status FROM sa1_episodes e LEFT JOIN sa1_jobs j ON j.episode_id=e.id AND j.user_id=? AND j.language=? WHERE e.slug=? ORDER BY e.number_value',[uid(),$settings['language'],$slug])->fetchAll() as $ep){
      if($mode==='selected'&&!in_array((int)$ep['id'],array_map('intval',$ids),true))continue;
      $counts['requested']++;if($excluded){$counts['excluded']++;continue;}
      if($ep['status']==='confirmed'){$counts['downloaded']++;continue;}if(in_array($ep['status'],['pending','exported'],true)){$counts['queued']++;continue;}
      $eligible[]=(int)$ep['id'];if(count($sample)<10)$sample[]=['title'=>$a['title'],'number'=>$ep['number']];
    }
  }
  if(count($eligible)>2000)throw new WebError('Prepara hasta 2.000 capítulos por lote.');$counts['eligible']=count($eligible);
  return ['preview'=>$counts+['episode_ids'=>$eligible,'sample'=>$sample,'language'=>$settings['language'],'server'=>$settings['server'],'height'=>$settings['height']]];
}
function dispatch_experience(PDO $db,string $action,array $input): ?array
{
  if($action==='queue_preview')return queue_preview($db,$input);
  if($action==='presence'){
    $slug=(string)($input['slug']??'');find_anime($db,$slug);$user=member();
    return ['presence_user_id'=>$user,'file_presence'=>sql($db,'SELECT p.* FROM sa1_job_presence p JOIN sa1_jobs j ON j.id=p.job_id JOIN sa1_episodes e ON e.id=j.episode_id WHERE p.user_id=? AND e.slug=?',[$user,$slug])->fetchAll()];
  }
  if($action==='player_save'){
    $user=member();$id=(int)($input['episode_id']??0);$mode=(string)($input['mode']??'');$position=$input['position']??null;$duration=$input['duration']??null;$seq=$input['sequence']??null;
    if(!is_numeric($position)||!is_numeric($duration)||!is_finite((float)$position)||!is_finite((float)$duration)||$duration<=0||$duration>43200||$position<0||$position>$duration+1||!is_int($seq)||$seq<1||!in_array($mode,['first','rewatch'],true)||!preg_match('/^[a-f0-9]{32}$/D',(string)($input['session_key']??'')))throw new WebError('Posición inválida.');
    $ep=sql($db,'SELECT slug FROM sa1_episodes WHERE id=?',[$id])->fetch();if(!$ep)throw new WebError('Capítulo no encontrado.',404);
    $policy=watch_mode($db,$ep['slug']);if(($input['revision']??'')!==$policy['revision']||$policy['mode']!==$mode)throw new WebError('La sesión de reproducción cambió. Reabre el capítulo.',409);
    $n=sql($db,'UPDATE sa1_playback SET position=?,duration=?,sequence_no=?,updated_at=? WHERE user_id=? AND episode_id=? AND mode=? AND session_key=? AND sequence_no<?',[(float)$position,(float)$duration,$seq,time(),$user,$id,$mode,$input['session_key'],$seq])->rowCount();
    return ['position_saved'=>(bool)$n];
  }
  if($action==='player_settings'){
    member();$slug=(string)($input['slug']??'');find_anime($db,$slug);$values=$input['settings']??null;
    if(!is_array($values)||array_diff(array_keys($values),['volume','muted','rate','autoplay_next','server','language']))throw new WebError('Preferencias inválidas.');
    foreach($values as $key=>$value){if(($key==='volume'&&(!is_numeric($value)||$value<0||$value>1))||($key==='rate'&&(!in_array($value,[0.5,0.75,1,1.25,1.5,1.75,2],true)))||(in_array($key,['muted','autoplay_next'],true)&&!is_bool($value))||($key==='server'&&!in_array($value,['MP4Upload','Voe'],true))||($key==='language'&&!in_array($value,['SUB','LAT','DUB'],true)))throw new WebError('Preferencia de reproducción inválida.');}
    // Older clients may still send both removed options; normalize them to the new policy.
    $values['autoplay_next']=true;
    $local=false;$table='sa1_player_preferences';$args=[uid()];$where='user_id=?';
    $old=json_decode(sql($db,"SELECT settings FROM $table WHERE $where",$args)->fetchColumn()?:'{}',true)?:[];
    $row=['user_id'=>uid()]+($local?['slug'=>$slug]:[])+['settings'=>json_encode(array_merge($old,$values))];upsert($db,$table,array_keys($row),[$row],$local?['user_id','slug']:['user_id'],['settings']);
    if(!$local)sql($db,'DELETE FROM sa1_player_anime WHERE user_id=? AND slug=?',[uid(),$slug]);
    return ['player_preferences'=>player_preferences($db,$slug)];
  }
  if($action==='watch_mode'){
    member();$slug=(string)($input['slug']??'');find_anime($db,$slug);$mode=(string)($input['mode']??'');if(!in_array($mode,['first','rewatch'],true))throw new WebError('Modo inválido.');
    if($mode==='rewatch')mal_cancel_progress($db,$slug);
    upsert($db,'sa1_watch_modes',['user_id','slug','mode','revision','changed_at'],[['user_id'=>uid(),'slug'=>$slug,'mode'=>$mode,'revision'=>bin2hex(random_bytes(16)),'changed_at'=>time()]],['user_id','slug'],['mode','revision','changed_at']);
    if($mode==='rewatch')sql($db,"DELETE FROM sa1_playback WHERE user_id=? AND mode='rewatch' AND episode_id IN (SELECT id FROM sa1_episodes WHERE slug=?)",[uid(),$slug]);
    return ['message'=>$mode==='rewatch'?'Revisionado iniciado. El progreso original y MAL se conservan.':'Seguimiento original restaurado.'];
  }
  if($action==='file_presence'){
    member();$device=(string)($input['device_id']??'');$items=$input['items']??null;
    if(!preg_match('/^[a-f0-9]{32,64}$/D',$device)||!is_array($items)||count($items)>2000)throw new WebError('Comprobación inválida.');
    $rows=[];foreach($items as $item){if(!is_array($item)||!is_int($item['web_id']??null)||(!is_bool($item['present']??null)&&(!array_key_exists('present',$item)||$item['present']!==null)))throw new WebError('Archivo inválido.');
      if(!sql($db,"SELECT id FROM sa1_jobs WHERE user_id=? AND id=? AND status='confirmed'",[uid(),$item['web_id']])->fetchColumn())continue;
      if($item['present']===null&&($item['known']??null)!==false)continue;
      $rows[]=['user_id'=>uid(),'job_id'=>$item['web_id'],'device_id'=>$device,'present'=>$item['present']===null?-1:(int)$item['present'],'checked_at'=>time()];
    }upsert($db,'sa1_job_presence',['user_id','job_id','device_id','present','checked_at'],$rows,['user_id','job_id','device_id'],['present','checked_at']);
    return ['presence_user_id'=>uid(),'file_presence'=>$rows];
  }
  if($action==='queue_redownload'){
    member();$id=(int)($input['job_id']??0);$device=(string)($input['device_id']??'');
    $p=sql($db,"SELECT p.present FROM sa1_job_presence p JOIN sa1_jobs j ON j.id=p.job_id WHERE p.user_id=? AND p.job_id=? AND p.device_id=? AND p.checked_at>? AND j.status='confirmed'",[uid(),$id,$device,time()-600])->fetch();
    if(!$p||(int)$p['present']===1||($input['confirmation']??'')!==((int)$p['present']===-1?'OTRO_EQUIPO':'REDESCARGAR'))throw new WebError('Primero comprueba el archivo en esta PC y confirma la descarga.',409);
    upsert($db,'sa1_job_runs',['job_id','revision'],[['job_id'=>$id,'revision'=>bin2hex(random_bytes(16))]],['job_id'],['revision']);
    sql($db,"UPDATE sa1_jobs SET status='pending',confirmed_at=NULL WHERE user_id=? AND id=? AND status='confirmed'",[uid(),$id]);
    $slug=(string)sql($db,'SELECT e.slug FROM sa1_jobs j JOIN sa1_episodes e ON e.id=j.episode_id WHERE j.id=? AND j.user_id=?',[$id,uid()])->fetchColumn();
    $patch=state_patch($db,[$slug],[$id]);$patch['reset_jobs']=[$id];
    return ['patch'=>$patch,'message'=>'Redescarga autorizada para esta PC.'];
  }
  return null;
}
function mal_cancel_progress(PDO $db,string $slug): void
{
  $db->beginTransaction();
  try {
    $lock=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'?' FOR UPDATE':'';
    $row=sql($db,'SELECT lock_until FROM sa1_watch_sync WHERE user_id=? AND slug=?'.$lock,[uid(),$slug])->fetch();
    if($row && (int)$row['lock_until']>time())throw new WebError('Hay una actualización de MAL en curso. Intenta de nuevo al terminar.',409);
    sql($db,"UPDATE sa1_watch_sync SET state='blocked',error_kind='corrected',generation=?,lock_until=0 WHERE user_id=? AND slug=?",[bin2hex(random_bytes(16)),uid(),$slug]);
    $db->commit();
  }catch(Throwable $error){if($db->inTransaction())$db->rollBack();throw $error;}
}
