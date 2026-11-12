<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {http_response_code(404);exit();}

function retention_cleanup(PDO $db,bool $force=false): array
{
  if(!$force&&!consume_limit($db,'retention-hour',1,3600))return [];
  $now=time();$removed=[];
  foreach([
    ['sa1_limits','name','reset_at<?',[$now-86400]],
    ['sa1_runtime_metrics','bucket','bucket<?',[$now-14*86400]],
    ['sa1_runtime_errors','fingerprint','last_at<?',[$now-14*86400]],
    ['sa1_catalog_tasks','task_key',"state='done' AND updated_at<?",[$now-30*86400]],
    ['sa1_user_notices','user_id','created_at<?',[$now-86400]],
    ['sa1_oauth_attempts','user_id','created_at<?',[$now-3600]],
  ] as [$table,$key,$where,$args]){
    // Bounded batches avoid long locks. A metrics bucket may have several actions.
    $ids=sql($db,"SELECT DISTINCT $key FROM $table WHERE $where LIMIT 250",$args)->fetchAll(PDO::FETCH_COLUMN);
    $removed[$table]=$ids?sql($db,"DELETE FROM $table WHERE $key IN (".implode(',',array_fill(0,count($ids),'?')).')',$ids)->rowCount():0;
  }
  $ids=sql($db,'SELECT h.id FROM sa1_history h WHERE h.created_at<? AND EXISTS(SELECT 1 FROM sa1_history newer WHERE newer.user_id=h.user_id AND newer.id>h.id LIMIT 1 OFFSET 79) ORDER BY h.created_at,h.id LIMIT 250',[$now-90*86400])->fetchAll(PDO::FETCH_COLUMN);
  $removed['sa1_history']=$ids?sql($db,'DELETE FROM sa1_history WHERE id IN ('.implode(',',array_fill(0,count($ids),'?')).')',$ids)->rowCount():0;
  set_meta($db,'retention_last',json_encode(['at'=>$now,'removed'=>$removed]));
  return $removed;
}
function query_plans(PDO $db): array
{
  $queries=[
    'active_queue'=>["SELECT id FROM sa1_jobs WHERE user_id=? AND status IN ('pending','exported') ORDER BY added_at DESC,id DESC LIMIT 100",[uid()]],
    'history'=>['SELECT id FROM sa1_history WHERE user_id=? ORDER BY id DESC LIMIT 80',[uid()]],
    'episodes'=>['SELECT id FROM sa1_episodes WHERE slug=? ORDER BY number_value',['naruto']],
    'expired_limits'=>['SELECT name FROM sa1_limits WHERE reset_at<? LIMIT 250',[time()-86400]],
  ];
  $out=[];$mysql=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql';
  foreach($queries as $name=>[$query,$args])$out[$name]=sql($db,($mysql?'EXPLAIN ':'EXPLAIN QUERY PLAN ').$query,$args)->fetchAll();
  return $out;
}
function system_health(PDO $db): array
{
  retention_cleanup($db);
  $metrics=sql($db,'SELECT action,SUM(requests) AS requests,SUM(failures) AS failures,SUM(total_ms)/SUM(requests) AS average_ms,MAX(max_ms) AS max_ms,SUM(queries)/SUM(requests) AS queries_per_request,SUM(query_ms)/SUM(requests) AS query_ms,SUM(slow_queries) AS slow_queries FROM sa1_runtime_metrics WHERE bucket>=? GROUP BY action ORDER BY SUM(total_ms) DESC LIMIT 25',[time()-86400])->fetchAll();
  return ['schema'=>meta($db,'schema_version'),'release'=>defined('SEASON_RELEASE_ID')?SEASON_RELEASE_ID:'development',
    'database'=>$db->getAttribute(PDO::ATTR_DRIVER_NAME),'at'=>time(),'metrics'=>$metrics,
    'errors'=>sql($db,'SELECT action,kind,occurrences,last_at FROM sa1_runtime_errors ORDER BY last_at DESC LIMIT 15')->fetchAll(),
    'pending'=>sql($db,"SELECT state,COUNT(*) AS total,MIN(created_at) AS oldest FROM sa1_catalog_tasks WHERE state<>'done' GROUP BY state")->fetchAll(),
    'freshness'=>catalog_coverage($db),'retention'=>json_decode(meta($db,'retention_last','{}'),true),
    'backup'=>json_decode(meta($db,'backup_last','{}'),true),'plans'=>query_plans($db)];
}
function dispatch_system_health(PDO $db,string $action,array $input): ?array
{
  if($action!=='system_health')return null;
  admin_member($db);return ['system_health'=>system_health($db)];
}
