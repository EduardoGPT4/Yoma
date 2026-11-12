<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {http_response_code(404);exit();}

function observe_query(string $query,float $ms): void
{
  if(empty($GLOBALS['season_observation'])||!empty($GLOBALS['season_observing']))return;
  $r=&$GLOBALS['season_observation'];$r['queries']++;$r['query_ms']+=$ms;if($ms>=100)$r['slow_queries']++;
}
function observation_start(string $action): void
{
  $GLOBALS['season_observation']=['action'=>preg_match('/^[a-z_]{1,40}$/D',$action)?$action:'unknown','start'=>hrtime(true),'queries'=>0,'query_ms'=>0.0,'slow_queries'=>0];
}
function observation_finish(PDO $db,?Throwable $error=null): void
{
  $r=$GLOBALS['season_observation']??null;if(!$r)return;
  $GLOBALS['season_observing']=true;
  try{
    $ms=(hrtime(true)-$r['start'])/1e6;$now=time();$bucket=(int)(floor($now/3600)*3600);$failed=$error?1:0;
    $values=[$bucket,$r['action'],1,$failed,$ms,$ms,$r['queries'],$r['query_ms'],$r['slow_queries'],$now];
    $q='INSERT INTO sa1_runtime_metrics(bucket,action,requests,failures,total_ms,max_ms,queries,query_ms,slow_queries,last_at) VALUES(?,?,?,?,?,?,?,?,?,?)';
    $q.=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'
      ?' ON DUPLICATE KEY UPDATE requests=requests+1,failures=failures+VALUES(failures),total_ms=total_ms+VALUES(total_ms),max_ms=GREATEST(max_ms,VALUES(max_ms)),queries=queries+VALUES(queries),query_ms=query_ms+VALUES(query_ms),slow_queries=slow_queries+VALUES(slow_queries),last_at=VALUES(last_at)'
      :' ON CONFLICT(bucket,action) DO UPDATE SET requests=requests+1,failures=failures+excluded.failures,total_ms=total_ms+excluded.total_ms,max_ms=MAX(max_ms,excluded.max_ms),queries=queries+excluded.queries,query_ms=query_ms+excluded.query_ms,slow_queries=slow_queries+excluded.slow_queries,last_at=excluded.last_at';
    sql($db,$q,$values);
    if($error){
      $kind=get_class($error).':'.(string)($error instanceof WebError?$error->status:$error->getCode());$fingerprint=hash('sha256',$r['action'].':'.$kind);
      $q='INSERT INTO sa1_runtime_errors(fingerprint,action,kind,occurrences,last_at) VALUES(?,?,?,1,?)';
      $q.=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'?' ON DUPLICATE KEY UPDATE occurrences=occurrences+1,last_at=VALUES(last_at)':' ON CONFLICT(fingerprint) DO UPDATE SET occurrences=occurrences+1,last_at=excluded.last_at';
      sql($db,$q,[$fingerprint,$r['action'],$kind,$now]);
    }
  }catch(Throwable $ignored){error_log('YomaTVWeb: observability unavailable');}
  finally{$GLOBALS['season_observing']=false;unset($GLOBALS['season_observation']);}
}
function release_remote_session(): void
{
  // PHP keeps this request's actor in memory. No session data is changed after I/O.
  if(session_status()===PHP_SESSION_ACTIVE)session_write_close();
}
function guard_remote_actor(PDO $db,int $user,int $version): void
{
  $current=sql($db,'SELECT auth_version FROM sa1_users WHERE id=?',[$user])->fetchColumn();
  if($current===false||(int)$current!==$version)throw new WebError('La cuenta cambió durante la operación.',401);
}
function application_root(): string{return defined('SEASON_APP_ROOT')?SEASON_APP_ROOT:dirname(__DIR__);}
function public_asset(string $path): string
{
  return defined('SEASON_RELEASE_ID')?'releases/'.SEASON_RELEASE_ID.'/'.$path:$path;
}
function consume_limit(PDO $db,string $key,int $maximum,int $seconds,?int $at=null): bool
{
  $now=$at??time();$reset=$now+$seconds;
  $q='INSERT INTO sa1_limits(name,hits,reset_at) VALUES(?,1,?)';
  if($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'){
    // assignments are deliberately ordered: expiry is evaluated before reset_at changes.
    $q.=' ON DUPLICATE KEY UPDATE hits=IF(reset_at<=?,1,LEAST(hits+1,2147483647)),reset_at=IF(reset_at<=?,VALUES(reset_at),reset_at)';
  }else $q.=' ON CONFLICT(name) DO UPDATE SET hits=CASE WHEN reset_at<=? THEN 1 ELSE MIN(hits+1,2147483647) END,reset_at=CASE WHEN reset_at<=? THEN excluded.reset_at ELSE reset_at END';
  $own=!$db->inTransaction();if($own)$db->beginTransaction();
  try{
    sql($db,$q,[$key,$reset,$now,$now]);
    $row=sql($db,'SELECT hits FROM sa1_limits WHERE name=?'.($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'?' FOR UPDATE':''),[$key])->fetch();
    $allowed=(int)$row['hits']<=$maximum;if($own)$db->commit();return $allowed;
  }catch(Throwable $error){if($own&&$db->inTransaction())$db->rollBack();throw $error;}
}
function request_limits(PDO $db,string $action): void
{
  if(in_array($action,['login','register','account_recover'],true))return;
  $ip=hash('sha256',$_SERVER['REMOTE_ADDR']??'local');
  $read=in_array($action,['state','detail','catalog','home','radio','queue_history','notifications','player','presence','queue_page','personal','sync_inbox','player_state','catalog_task','mobile_session','offline_plan'],true);
  $window=$read?60:300;$max=$read?300:180;
  rate($db,($read?'read-ip:':'write-ip:').$ip,$max*3,$window);
  if(uid())rate($db,($read?'read-user:':'write-user:').uid(),$max,$window);
}
