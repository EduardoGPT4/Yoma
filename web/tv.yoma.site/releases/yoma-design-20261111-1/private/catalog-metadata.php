<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}
function ensure_search_index(PDO $db): void
{
  $version = (string) meta($db, 'directory_updated', '0');
  if (meta($db, 'search_version') === $version) {
    return;
  }
  $rows = [];
  foreach (sql($db, 'SELECT slug,title FROM sa1_anime')->fetchAll() as $a) {
    $rows[] = ['slug' => $a['slug'], 'search_key' => title_key($a['title'])];
  }
  upsert(
    $db,
    'sa1_anime_search',
    ['slug', 'search_key'],
    $rows,
    ['slug'],
    ['search_key'],
  );
  set_meta($db, 'search_version', $version);
}
function catalog_years(PDO $db): array
{
  $years = [];
  foreach (
    sql(
      $db,
      'SELECT ' . catalog_year_sql() . ' AS year ' . catalog_public_from(),
    )->fetchAll()
    as $r
  ) {
    if (preg_match('/^(\d{4})/', $r['year'], $m)) {
      $years[$m[1]] = true;
    }
  }
  $out = array_keys($years);
  rsort($out);
  return array_map('strval', $out);
}
function catalog_genres(PDO $db): array
{
  $genres = array_fill_keys(array_column(catalog_source_taxonomy(),'name'),true);
  foreach (
    sql(
      $db,
      'SELECT DISTINCT sf.genres ' . catalog_public_from() . " WHERE sf.genres IS NOT NULL AND sf.genres<>'[]'",
    )->fetchAll()
    as $r
  ) {
    foreach (json_decode($r['genres'], true) ?: [] as $g) {
      $genres[$g] = true;
    };
  }
  $out = array_keys($genres);
  sort($out);
  return $out;
}

function catalog_from_sql(): string
{
  // Personal links are used for progress only, never for general catalog metadata.
  $user = uid();
  return "FROM sa1_anime a LEFT JOIN sa1_catalog_source sf ON sf.slug=a.slug LEFT JOIN sa1_catalog_mal cm ON cm.slug=a.slug LEFT JOIN sa1_mal_links k ON k.slug=a.slug AND k.user_id=$user LEFT JOIN sa1_mal_anime m ON m.mal_id=cm.mal_id LEFT JOIN sa1_follow f ON f.slug=a.slug AND f.user_id=$user";
}

function catalog_year_sql(): string
{
  // Resolve column collations before converting the numeric source year to text.
  return "CAST(COALESCE(sf.premiere_year,NULLIF(SUBSTR(a.start_date,1,4),''),NULLIF(SUBSTR(m.start_date,1,4),''),'') AS CHAR)";
}

function catalog_start_sql(): string
{
  return "COALESCE(NULLIF(a.start_date,''),NULLIF(m.start_date,''),'')";
}

function catalog_airing_sql(): string
{
  return "COALESCE(NULLIF(sf.airing_status,''),NULLIF(m.airing_status,''),CASE WHEN a.active=1 THEN 'currently_airing' ELSE 'unknown' END)";
}

function catalog_season(array $anime): string
{
  return preg_match('/^\d{4}-(0[1-9]|1[0-2])/', (string) ($anime['start_date'] ?? ''))
    ? season_name($anime['start_date']) : (string) ($anime['season'] ?? '');
}

function catalog_seasons(PDO $db): array
{
  $values = [];
  foreach (sql($db, 'SELECT a.season,' . catalog_start_sql() . ' AS start_date ' . catalog_public_from())->fetchAll() as $a) {
    $season = catalog_season($a);
    if (preg_match('/^(invierno|primavera|verano|otoño)\d{4}$/uD', $season)) $values[$season] = true;
  }
  $out = array_keys($values);
  $ranks = ['invierno'=>1,'primavera'=>2,'verano'=>3,'otoño'=>4];
  usort($out, static function($a,$b) use ($ranks) {
    preg_match('/^(.*?)(\d{4})$/u', $a, $left); preg_match('/^(.*?)(\d{4})$/u', $b, $right);
    return ((int)$right[2] <=> (int)$left[2]) ?: ($ranks[$right[1]] <=> $ranks[$left[1]]);
  });
  return $out;
}

function catalog_index_languages(PDO $db, int $id, array $mirrors): void
{
  sql($db, 'DELETE FROM sa1_episode_languages WHERE episode_id=?', [$id]);
  $rows = [];
  foreach ($mirrors as $mirror) {
    $language = strtoupper((string)($mirror['language'] ?? ''));
    if (in_array($language, ['SUB','LAT','DUB'], true)) $rows[$language] = ['episode_id'=>$id,'language'=>$language];
  }
  upsert($db,'sa1_episode_languages',['episode_id','language'],array_values($rows),['episode_id','language'],['language']);
}

function ensure_catalog_languages(PDO $db): void
{
  if (meta($db,'catalog_languages_version') === '1') return;
  foreach (sql($db,"SELECT id,mirrors FROM sa1_episodes WHERE mirrors IS NOT NULL AND mirrors_at>0")->fetchAll() as $ep) {
    catalog_index_languages($db,(int)$ep['id'],json_decode($ep['mirrors'],true) ?: []);
  }
  set_meta($db,'catalog_languages_version','1');
}

function catalog_cache_metadata(PDO $db, array $mal, array $node = []): void
{
  catalog_invalidate($db);
  static $indexes = [];
  $version = (string)meta($db,'directory_updated','0');
  $key = spl_object_id($db) . ':' . $version;
  $index = $indexes[$key] ??= mal_catalog_index($db);
  $matches = [];
  foreach (json_decode($mal['aliases'],true) ?: [$mal['title']] as $alias) {
    $title = title_key($alias);
    if (mb_strlen($title)<5) continue;
    foreach ($index[$title] ?? [] as $local) {
      if (compatible_match($local,$mal)) $matches[$local['slug']] = true;
    }
  }
  if (count($matches)!==1) return;
  $slug = array_key_first($matches);
  $old = sql($db,'SELECT mal_id,extra FROM sa1_catalog_mal WHERE slug=?',[$slug])->fetch();
  // Two different MAL records with the same compatible name require a personal choice.
  $id = $old && (!$old['mal_id'] || (int)$old['mal_id']!==(int)$mal['mal_id']) ? null : (int)$mal['mal_id'];
  $extra = $old && $id ? (json_decode($old['extra'],true) ?: []) : [];
  if (isset($node['mean']) && is_numeric($node['mean'])) $extra['mean'] = max(0,min(10,(float)$node['mean']));
  if (isset($node['studios']) && is_array($node['studios'])) $extra['studios'] = array_values(array_filter(array_map(static fn($s)=>mb_substr((string)($s['name'] ?? ''),0,100),array_slice($node['studios'],0,20))));
  $row = ['slug'=>$slug,'mal_id'=>$id,'extra'=>json_encode($extra,JSON_UNESCAPED_UNICODE),'updated_at'=>(int)$mal['updated_at']];
  upsert($db,'sa1_catalog_mal',array_keys($row),[$row],['slug'],['mal_id','extra','updated_at']);
}

function ensure_catalog_metadata(PDO $db): void
{
  $version = (string)meta($db,'directory_updated','0');
  if (meta($db,'catalog_metadata_version') === $version) return;
  // These fields were never supplied by our XML importer: they came from MAL's API.
  foreach (sql($db,"SELECT * FROM sa1_mal_anime WHERE genres<>'[]' OR airing_status<>''")->fetchAll() as $mal) catalog_cache_metadata($db,$mal);
  set_meta($db,'catalog_metadata_version',$version);
}

function catalog_genre_values(mixed $value): array
{
  if (is_string($value)) {
    if (strlen($value)>2000) throw new WebError('Demasiados géneros.');
    $value = $value === '' ? [] : json_decode($value,true);
  }
  if (!is_array($value) || array_values($value)!==$value || count($value)>20) throw new WebError('Selección de géneros inválida.');
  foreach ($value as $genre) if (!is_string($genre) || trim($genre)==='' || mb_strlen($genre)>80) throw new WebError('Género inválido.');
  return array_values(array_unique($value));
}
