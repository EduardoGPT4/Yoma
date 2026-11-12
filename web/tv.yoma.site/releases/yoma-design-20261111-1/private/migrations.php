<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {http_response_code(404);exit();}
require_once __DIR__.'/schema.php';
const SEASON_SCHEMA_VERSION='20261023.1';

function stored_schema_version(PDO $db): ?string
{
  try {return meta($db,'schema_version');}
  catch(PDOException $error){
    $missing=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'
      ?$error->getCode()==='42S02'&&(int)($error->errorInfo[1]??0)===1146
      :str_contains($error->getMessage(),'no such table: sa1_meta');
    if(!$missing)throw $error;
    return null;
  }
}
function migrate(PDO $db): void
{
  $version=stored_schema_version($db);
  if($version===SEASON_SCHEMA_VERSION)return;
  $mysql=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql';$file=null;$lock=null;
  if($mysql){
    $name='season-schema-'.substr(hash('sha256',(string)$db->query('SELECT DATABASE()')->fetchColumn()),0,40);
    if((int)sql($db,'SELECT GET_LOCK(?,8)',[$name])->fetchColumn()!==1)throw new RuntimeException('Otra actualización del esquema sigue en curso.');
    $lock=$name;
  }else{
    $path=$db->query('PRAGMA database_list')->fetch()['file'];
    $file=fopen(sys_get_temp_dir().'/season-schema-'.hash('sha256',$path).'.lock','c');
    if(!$file||!flock($file,LOCK_EX))throw new RuntimeException('No se pudo bloquear la migración.');
  }
  try{
    if(stored_schema_version($db)===SEASON_SCHEMA_VERSION)return;
    migrate_schema_legacy($db);
    $tail=$mysql?' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci':'';
    foreach([
      'sa1_public_cache (cache_key VARCHAR(80) PRIMARY KEY,version VARCHAR(64) NOT NULL,payload MEDIUMTEXT NOT NULL,created_at BIGINT NOT NULL)',
      'sa1_runtime_metrics (bucket BIGINT NOT NULL,action VARCHAR(40) NOT NULL,requests INTEGER NOT NULL,failures INTEGER NOT NULL,total_ms DOUBLE NOT NULL,max_ms DOUBLE NOT NULL,queries INTEGER NOT NULL,query_ms DOUBLE NOT NULL,slow_queries INTEGER NOT NULL,last_at BIGINT NOT NULL,PRIMARY KEY(bucket,action))',
      'sa1_runtime_errors (fingerprint VARCHAR(64) PRIMARY KEY,action VARCHAR(40) NOT NULL,kind VARCHAR(80) NOT NULL,occurrences INTEGER NOT NULL,last_at BIGINT NOT NULL)',
      'sa1_oauth_attempts (user_id INTEGER PRIMARY KEY,state_hash VARCHAR(64) NOT NULL,created_at BIGINT NOT NULL,FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
      'sa1_user_notices (user_id INTEGER PRIMARY KEY,notice VARCHAR(40) NOT NULL,created_at BIGINT NOT NULL,FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
      'sa1_personal_data (user_id INTEGER NOT NULL,kind VARCHAR(32) NOT NULL,item_key VARCHAR(240) NOT NULL,payload MEDIUMTEXT NOT NULL,updated_at BIGINT NOT NULL,PRIMARY KEY(user_id,kind,item_key),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
      'sa1_job_events (user_id INTEGER NOT NULL,job_id INTEGER NOT NULL,device_id VARCHAR(64) NOT NULL,state VARCHAR(24) NOT NULL,attempts INTEGER NOT NULL,error_kind VARCHAR(32) NOT NULL,updated_at BIGINT NOT NULL,PRIMARY KEY(user_id,job_id,device_id),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(job_id) REFERENCES sa1_jobs(id) ON DELETE CASCADE)',
    ] as $definition)$db->exec('CREATE TABLE IF NOT EXISTS '.$definition.$tail);
    $indexes=[
      ['sa1_jobs','sa1_jobs_user_status_id','user_id,status,id'],
      ['sa1_jobs','sa1_jobs_user_added','user_id,added_at,id'],
      ['sa1_job_events','sa1_events_job_latest','user_id,job_id,updated_at'],
      ['sa1_playback','sa1_playback_recent','user_id,updated_at'],
      ['sa1_history','sa1_history_user_id','user_id,id'],
      ['sa1_history','sa1_history_created','created_at,id'],
      ['sa1_notifications','sa1_notices_user_read_slug','user_id,read_at,slug'],
      ['sa1_watch_sync','sa1_watch_due','user_id,state,next_retry,lock_until'],
      ['sa1_catalog_tasks','sa1_tasks_due','state,next_retry,priority,updated_at'],
      ['sa1_episodes','sa1_episodes_slug_number','slug,number_value'],
      ['sa1_limits','sa1_limits_expiry','reset_at'],
      ['sa1_follow','sa1_follow_user_status_slug','user_id,status,slug'],
    ];
    foreach($indexes as [$table,$name,$columns]){
      $existing=$mysql?$db->query('SHOW INDEX FROM '.$table)->fetchAll():$db->query('PRAGMA index_list('.$table.')')->fetchAll();
      if(!in_array($name,array_column($existing,$mysql?'Key_name':'name'),true))$db->exec("CREATE INDEX $name ON $table($columns)");
    }
    set_meta($db,'schema_version',SEASON_SCHEMA_VERSION);
    set_meta($db,'schema_migrated_at',(string)time());
  }finally{
    if($lock!==null)sql($db,'SELECT RELEASE_LOCK(?)',[$lock]);
    if(is_resource($file)){flock($file,LOCK_UN);fclose($file);}
  }
}
