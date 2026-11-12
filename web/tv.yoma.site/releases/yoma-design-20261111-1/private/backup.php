<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {http_response_code(404);exit();}

// No SQL or configuration is accepted from a backup. Only the installed schema is restored.
function backup_tables(PDO $db): array
{
  $mysql=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql';
  $names=$mysql?$db->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN):$db->query("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'sa1_%' ORDER BY rowid")->fetchAll(PDO::FETCH_COLUMN);
  $names=array_values(array_filter($names,static fn($v)=>preg_match('/^sa1_[a-z_]+$/D',$v)));
  $out=[];$remaining=array_fill_keys($names,true);
  while($remaining){
    $progress=false;
    foreach(array_keys($remaining) as $table){
      $parents=$mysql?sql($db,'SELECT REFERENCED_TABLE_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND REFERENCED_TABLE_NAME IS NOT NULL',[$table])->fetchAll(PDO::FETCH_COLUMN):array_column($db->query('PRAGMA foreign_key_list('.$table.')')->fetchAll(),'table');
      if(array_filter($parents,static fn($parent)=>$parent!==$table&&isset($remaining[$parent])))continue;
      $out[]=$table;unset($remaining[$table]);$progress=true;
    }
    if(!$progress)throw new RuntimeException('El esquema contiene referencias circulares.');
  }
  return $out;
}
function backup_key(string $password,string $salt): string
{
  if(strlen($password)<16||strlen($password)>256)throw new WebError('Usa una clave de respaldo de 16 a 256 caracteres.');
  return hash_pbkdf2('sha256',$password,$salt,210000,32,true);
}
function backup_sequences(PDO $db): array
{
  $out=[];
  if($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'){
    foreach(sql($db,'SELECT TABLE_NAME,AUTO_INCREMENT FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND AUTO_INCREMENT IS NOT NULL')->fetchAll() as $row)
      if(preg_match('/^sa1_[a-z_]+$/D',$row['TABLE_NAME']))$out[$row['TABLE_NAME']]=(int)$row['AUTO_INCREMENT'];
  }else{
    foreach($db->query('SELECT name,seq FROM sqlite_sequence')->fetchAll(PDO::FETCH_ASSOC) as $row)
      if(preg_match('/^sa1_[a-z_]+$/D',$row['name']))$out[$row['name']]=(int)$row['seq']+1;
  }
  return $out;
}
function backup_write(PDO $db,$stream,string $password): array
{
  $salt=random_bytes(32);$key=backup_key($password,$salt);$index=0;$rows=0;$digest=hash_init('sha256');
  $header=['format'=>'seasonav1.db-backup/v1','salt'=>base64_encode($salt),'iterations'=>210000,'schema'=>SEASON_SCHEMA_VERSION];
  fwrite($stream,json_encode($header)."\n");
  $write=static function(array $record)use($stream,$key,&$index,$digest){
    $plain=json_encode($record,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE);$nonce=random_bytes(12);$tag='';
    $cipher=openssl_encrypt($plain,'aes-256-gcm',$key,OPENSSL_RAW_DATA,$nonce,$tag,'seasonav1.db-backup/v1:'.$index,16);
    if($cipher===false)throw new RuntimeException('No se pudo cifrar el respaldo.');
    $line=json_encode(['i'=>$index++,'n'=>base64_encode($nonce),'t'=>base64_encode($tag),'c'=>base64_encode($cipher)])."\n";
    if(fwrite($stream,$line)!==strlen($line))throw new RuntimeException('No se pudo escribir el respaldo.');
    if($record['type']!=='end')hash_update($digest,$plain);
  };
  $tables=backup_tables($db);$sequences=backup_sequences($db);$mysql=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql';$statement=null;
  if($mysql)$db->exec('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
  $db->beginTransaction();
  $buffered=$mysql?$db->getAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY):true;
  if($mysql)$db->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY,false);
  try{
    $write(['type'=>'start','tables'=>$tables,'schema'=>SEASON_SCHEMA_VERSION,'sequences'=>$sequences]);
    foreach($tables as $table){
      $statement=$db->query('SELECT * FROM '.$table);$chunk=[];
      while($row=$statement->fetch(PDO::FETCH_ASSOC)){
        $chunk[]=$row;$rows++;
        if(count($chunk)===250){$write(['type'=>'rows','table'=>$table,'rows'=>$chunk]);$chunk=[];}
      }
      if($chunk)$write(['type'=>'rows','table'=>$table,'rows'=>$chunk]);
      $statement->closeCursor();$statement=null;
    }
    $write(['type'=>'end','rows'=>$rows,'digest'=>hash_final($digest)]);$db->commit();
  }catch(Throwable $e){$statement?->closeCursor();if($db->inTransaction())$db->rollBack();throw $e;}
  finally{if($mysql)$db->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY,$buffered);}
  return ['at'=>time(),'tables'=>count($tables),'rows'=>$rows,'format'=>$header['format']];
}
function backup_read($stream,string $password,callable $consume): array
{
  rewind($stream);$header=json_decode((string)fgets($stream),true,16,JSON_THROW_ON_ERROR);
  if(($header['format']??'')!=='seasonav1.db-backup/v1'||($header['iterations']??0)!==210000||!in_array($header['schema']??'',['20261018.4',SEASON_SCHEMA_VERSION],true))throw new RuntimeException('Formato o versión de respaldo incompatible.');
  $salt=base64_decode($header['salt']??'',true);if($salt===false||strlen($salt)!==32)throw new RuntimeException('Respaldo inválido.');
  $key=backup_key($password,$salt);$index=0;$rows=0;$digest=hash_init('sha256');$finished=false;$tables=[];$sequences=[];
  while(($line=fgets($stream,32*1024*1024))!==false){
    if($finished||!str_ends_with($line,"\n"))throw new RuntimeException('Respaldo truncado o con contenido sobrante.');
    $r=json_decode($line,true,32,JSON_THROW_ON_ERROR);
    if(($r['i']??-1)!==$index++)throw new RuntimeException('Orden inválido en el respaldo.');
    $n=base64_decode($r['n']??'',true);$t=base64_decode($r['t']??'',true);$c=base64_decode($r['c']??'',true);
    if($n===false||strlen($n)!==12||$t===false||strlen($t)!==16||$c===false)throw new RuntimeException('Registro cifrado inválido.');
    $plain=openssl_decrypt($c,'aes-256-gcm',$key,OPENSSL_RAW_DATA,$n,$t,'seasonav1.db-backup/v1:'.($index-1));
    if($plain===false)throw new RuntimeException('Clave incorrecta o respaldo alterado.');
    $r=json_decode($plain,true,64,JSON_THROW_ON_ERROR);
    if($index===1){if(($r['type']??'')!=='start')throw new RuntimeException('Falta la cabecera cifrada.');$tables=$r['tables'];$sequences=$r['sequences']??[];}
    elseif(($r['type']??'')==='rows'){$rows+=count($r['rows']);$consume($r,$tables);}
    elseif(($r['type']??'')==='end'){
      if($rows!==$r['rows']||!hash_equals(hash_final($digest),$r['digest']))throw new RuntimeException('Respaldo incompleto.');
      $finished=true;continue;
    }else throw new RuntimeException('Registro desconocido.');
    hash_update($digest,$plain);
  }
  if(!$finished)throw new RuntimeException('Falta el cierre del respaldo.');
  return ['tables'=>count($tables),'rows'=>$rows,'sequences'=>$sequences];
}
function backup_restore(PDO $db,$stream,string $password): array
{
  $allowed=backup_tables($db);
  foreach($allowed as $table){
    $where=$table==='sa1_meta'?" WHERE name NOT IN ('schema_version','schema_migrated_at','security_schema','reliability_schema')":'';
    if((int)$db->query('SELECT COUNT(*) FROM '.$table.$where)->fetchColumn())throw new RuntimeException('La restauración exige una base vacía; no reemplaza datos existentes.');
  }
  // Authenticate every chunk before touching the empty destination.
  $verified=backup_read($stream,$password,static function($r,$tables)use($allowed){
    if(array_diff($tables,$allowed)||!in_array($r['table'],$allowed,true))throw new RuntimeException('El respaldo no coincide con el esquema instalado.');
  });
  $sequences=$verified['sequences'];$mysql=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql';
  foreach($sequences as $table=>$next){
    if(!in_array($table,$allowed,true)||!is_int($next)||$next<1||$next>=PHP_INT_MAX)throw new RuntimeException('Secuencia inválida.');
    if($mysql){
      $columns=$db->query('SHOW COLUMNS FROM '.$table)->fetchAll();
      if(!array_filter($columns,static fn($column)=>str_contains($column['Extra'],'auto_increment')))throw new RuntimeException('La tabla no tiene secuencia.');
      // DDL runs only on the authenticated, empty target, before the data transaction.
      $db->exec('ALTER TABLE '.$table.' AUTO_INCREMENT='.$next);
    }
  }
  $db->beginTransaction();
  try{
    $db->exec('DELETE FROM sa1_meta');
    $result=backup_read($stream,$password,static function($r)use($db,$allowed){
      if(!in_array($r['table'],$allowed,true))throw new RuntimeException('Tabla ajena al esquema instalado.');
      foreach($r['rows'] as $row){
        $columns=array_keys($row);
        foreach($columns as $column)if(!preg_match('/^[a-z_][a-z_0-9]*$/D',$column))throw new RuntimeException('Columna inválida.');
        sql($db,'INSERT INTO '.$r['table'].' ('.implode(',',$columns).') VALUES ('.implode(',',array_fill(0,count($columns),'?')).')',array_values($row));
      }
    });
    if(!$mysql)foreach($sequences as $table=>$next){
      $row=sql($db,'SELECT seq FROM sqlite_sequence WHERE name=?',[$table])->fetch();
      if($row)sql($db,'UPDATE sqlite_sequence SET seq=? WHERE name=?',[max((int)$row['seq'],$next-1),$table]);
      else sql($db,'INSERT INTO sqlite_sequence(name,seq) VALUES(?,?)',[$table,$next-1]);
    }
    $db->commit();return $result;
  }catch(Throwable $e){if($db->inTransaction())$db->rollBack();throw $e;}
}
