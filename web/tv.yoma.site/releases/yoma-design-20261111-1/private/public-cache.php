<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {http_response_code(404);exit();}

function catalog_invalidate(PDO $db): void
{
  $q="INSERT INTO sa1_meta(name,value) VALUES('catalog_public_revision','1')";
  $q.=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'
    ?" ON DUPLICATE KEY UPDATE value=CAST(value AS UNSIGNED)+1"
    :" ON CONFLICT(name) DO UPDATE SET value=CAST(value AS INTEGER)+1";
  sql($db,$q);
}
function public_cache(PDO $db,string $key,callable $compute): array
{
  $versions=sql($db,"SELECT name,value FROM sa1_meta WHERE name IN ('catalog_public_revision','directory_updated','catalog_source_version')")->fetchAll(PDO::FETCH_KEY_PAIR);
  ksort($versions);$version=hash('sha256',json_encode($versions).':'.(string)(int)(time()/3600).':'.(defined('SEASON_RELEASE_ID')?SEASON_RELEASE_ID:'source'));
  $row=sql($db,'SELECT version,payload FROM sa1_public_cache WHERE cache_key=?',[$key])->fetch();
  if($row&&hash_equals($version,$row['version'])){
    $data=json_decode($row['payload'],true);if(is_array($data))return $data;
  }
  $lock='cache-lock:'.$key;$token=(string)(time()+20);
  upsert($db,'sa1_meta',['name','value'],[['name'=>$lock,'value'=>'0']],['name'],['name']);
  $old=meta($db,$lock,'0');
  $owned=(int)$old<=time()&&sql($db,'UPDATE sa1_meta SET value=? WHERE name=? AND value=?',[$token,$lock,$old])->rowCount()===1;
  if(!$owned&&$row){$stale=json_decode($row['payload'],true);if(is_array($stale))return $stale;}
  if(!$owned)throw new WebError('El catálogo se está preparando. Intenta de nuevo en unos segundos.',503);
  try{$data=$compute();
  $row=['cache_key'=>$key,'version'=>$version,'payload'=>json_encode($data,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE),'created_at'=>time()];
  upsert($db,'sa1_public_cache',array_keys($row),[$row],['cache_key'],['version','payload','created_at']);
  return $data;
  }finally{sql($db,'UPDATE sa1_meta SET value=? WHERE name=? AND value=?',['0',$lock,$token]);}
}
function catalog_public_from(): string
{
  return 'FROM sa1_anime a LEFT JOIN sa1_catalog_source sf ON sf.slug=a.slug LEFT JOIN sa1_catalog_mal cm ON cm.slug=a.slug LEFT JOIN sa1_mal_anime m ON m.mal_id=cm.mal_id';
}
function catalog_facets(PDO $db): array
{
  return public_cache($db,'facets-v1',static function()use($db){
    $from=catalog_public_from();$start=catalog_start_sql();$year=catalog_year_sql();$airing=catalog_airing_sql();
    $coverage=sql($db,"SELECT COUNT(*) AS total,SUM(CASE WHEN sf.slug IS NOT NULL THEN 1 ELSE 0 END) AS source,SUM(CASE WHEN $start<>'' THEN 1 ELSE 0 END) AS dated,SUM(CASE WHEN $year<>'' THEN 1 ELSE 0 END) AS years,SUM(CASE WHEN COALESCE(sf.genres,'[]')<>'[]' THEN 1 ELSE 0 END) AS genres,SUM(CASE WHEN $airing<>'unknown' THEN 1 ELSE 0 END) AS airing ".$from)->fetch();
    return ['years'=>catalog_years($db),'seasons'=>catalog_seasons($db),'genres'=>catalog_genres($db),
      'coverage'=>array_map('intval',$coverage),'categories'=>sql($db,'SELECT DISTINCT category FROM sa1_anime ORDER BY category')->fetchAll(PDO::FETCH_COLUMN)];
  });
}
