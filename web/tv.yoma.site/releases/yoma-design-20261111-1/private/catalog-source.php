<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit(); }

function catalog_source_taxonomy(): array
{
  static $items;
  if ($items !== null) return $items;
  $file = dirname(__DIR__) . '/data/catalog-taxonomy.json';
  return $items = is_file($file)
    ? json_decode(file_get_contents($file), true, 64, JSON_THROW_ON_ERROR) : [];
}

function catalog_source_genres(array $values): array
{
  // Keep links made before the Spanish AnimeAV1 taxonomy was introduced usable.
  $english = [1=>'Action',2=>'Adventure',24=>'Sci-Fi',4=>'Comedy',30=>'Sports',8=>'Drama',10=>'Fantasy',7=>'Mystery',36=>'Slice of Life',22=>'Romance',42=>'Seinen',25=>'Shoujo',27=>'Shounen',37=>'Supernatural',41=>'Suspense',14=>'Horror',51=>'Anthropomorphic',17=>'Martial Arts',3=>'Racing',39=>'Detective',9=>'Ecchi',50=>'Adult Cast',23=>'School',29=>'Space',58=>'Gore',47=>'Gourmet',35=>'Harem',13=>'Historical',61=>'Idols (Male)',60=>'Idols (Female)',15=>'Kids',62=>'Isekai',43=>'Josei',11=>'Strategy Game',66=>'Mahou Shoujo',18=>'Mecha',38=>'Military',6=>'Mythology',19=>'Music',20=>'Parody',40=>'Psychological',21=>'Samurai',26=>'Girls Love',28=>'Boys Love',31=>'Super Power',32=>'Vampire'];
  $aliases = [];
  foreach (catalog_source_taxonomy() as $genre) {
    foreach ([$genre['name'], $genre['slug'], $english[$genre['malId']] ?? ''] as $name)
      if ($name !== '') $aliases[title_key($name)] = $genre['name'];
  }
  return array_values(array_unique(array_map(static fn($value) => $aliases[title_key($value)] ?? $value, $values)));
}

function seed_catalog_source(PDO $db): void
{
  $root = dirname(__DIR__) . '/data/';
  if (!is_file($root . 'catalog-facets-meta.json') || !is_file($root . 'catalog-facets.json.gz')) return;
  $meta = json_decode(file_get_contents($root . 'catalog-facets-meta.json'), true, 32, JSON_THROW_ON_ERROR);
  if (meta($db, 'catalog_source_version') === $meta['version'] && meta($db,'directory_seed_updated')!==null) return;
  $data = json_decode(gzdecode(file_get_contents($root . 'catalog-facets.json.gz')), true, 64, JSON_THROW_ON_ERROR);
  if ($data['version'] !== $meta['version'] || count($data['anime']) !== (int)$meta['total'])
    throw new RuntimeException('El índice de filtros de AnimeAV1 está incompleto.');
  $directory = [];
  foreach ($data['directory'] as $item) {
    if (!preg_match('/^[A-Za-z0-9_-]{1,240}$/D', $item['slug']) || !is_numeric($item['id']) || empty($item['title']))
      throw new RuntimeException('Una ficha del índice no es válida.');
    $directory[] = ['slug'=>$item['slug'],'source_id'=>(int)$item['id'],'title'=>html_entity_decode($item['title'],ENT_QUOTES|ENT_HTML5,'UTF-8'),
      'synopsis'=>html_entity_decode($item['synopsis'] ?? '',ENT_QUOTES|ENT_HTML5,'UTF-8'),'cover'=>'https://cdn.animeav1.com/covers/'.(int)$item['id'].'.jpg',
      'weekday'=>0,'latest'=>'','published'=>'','start_date'=>null,'season'=>'','category'=>$item['category']['name'] ?? 'Anime',
      'active'=>0,'catalog_complete'=>0,'updated_at'=>(int)$data['fetched_at']];
  }
  $rows = [];
  foreach ($data['anime'] as $item) {
    $year = $item['year'];
    if (($year !== null && (!is_int($year) || $year<1900 || $year>2199)) || !is_array($item['genres']) ||
      !in_array($item['airing_status'], ['', 'currently_airing','finished_airing','not_yet_aired'],true))
      throw new RuntimeException('Los metadatos de AnimeAV1 no son válidos.');
    $rows[] = ['slug'=>$item['slug'],'genres'=>json_encode($item['genres'],JSON_UNESCAPED_UNICODE),'premiere_year'=>$year,
      'airing_status'=>$item['airing_status'],'updated_at'=>(int)$data['fetched_at']];
  }
  $db->beginTransaction();
  try {
    $newerDirectory=[];$newerSource=[];
    foreach(sql($db,'SELECT slug FROM sa1_catalog_freshness WHERE directory_at>?',[(int)$data['fetched_at']])->fetchAll(PDO::FETCH_COLUMN) as $slug) $newerDirectory[$slug]=true;
    foreach(sql($db,'SELECT slug FROM sa1_catalog_source WHERE updated_at>?',[(int)$data['fetched_at']])->fetchAll(PDO::FETCH_COLUMN) as $slug) $newerSource[$slug]=true;
    $directory=array_values(array_filter($directory,static fn($row)=>!isset($newerDirectory[$row['slug']])));
    $rows=array_values(array_filter($rows,static fn($row)=>!isset($newerSource[$row['slug']])));
    if ($directory) upsert($db,'sa1_anime',array_keys($directory[0]),$directory,['slug'],['source_id','title','synopsis','cover','category']);
    $directoryDates=array_map(static fn($row)=>['slug'=>$row['slug'],'directory_at'=>(int)$data['fetched_at']],$directory);
    if ($directoryDates) upsert($db,'sa1_catalog_freshness',['slug','directory_at'],$directoryDates,['slug'],['directory_at']);
    if ($rows) upsert($db,'sa1_catalog_source',array_keys($rows[0]),$rows,['slug'],['genres','premiere_year','airing_status','updated_at']);
    set_meta($db,'catalog_source_version',$data['version']);
    set_meta($db,'catalog_source_updated',(string)max((int)meta($db,'catalog_source_updated','0'),(int)$data['fetched_at']));
    set_meta($db,'directory_updated',(string)max((int)meta($db,'directory_updated','0'),(int)$data['fetched_at']));
    set_meta($db,'directory_seed_updated',(string)$data['fetched_at']);
    $db->commit();
  } catch (Throwable $error) { $db->rollBack(); throw $error; }
}

function catalog_source_detail(PDO $db, string $slug, string $state): void
{
  $media = LiteralReader::property($state, 'media');
  if (!is_array($media) || ($media['slug'] ?? '') !== $slug) return;
  $genres = $media['genres'] ?? null;
  // A detail page may carry shared JS references; never publish a partial parse.
  if (!is_array($genres)) return;
  $names = [];
  foreach ($genres as $genre) {
    $genre = $genre['genre'] ?? $genre;
    if (!is_array($genre) || !isset($genre['name'])) return;
    $names[] = $genre['name'];
  }
  $date = $media['startDate'] ?? null;
  $status = $media['status'] ?? null;
  $statuses = [0=>'finished_airing',1=>'not_yet_aired',2=>'currently_airing'];
  $row = ['slug'=>$slug,'genres'=>json_encode(catalog_source_genres($names),JSON_UNESCAPED_UNICODE),
    'premiere_year'=>is_string($date) && preg_match('/^((?:19|20|21)\d{2})-/', $date,$match) ? (int)$match[1] : null,
    'airing_status'=>is_int($status) ? ($statuses[$status] ?? '') : '', 'updated_at'=>time()];
  upsert($db,'sa1_catalog_source',array_keys($row),[$row],['slug'],['genres','premiere_year','airing_status','updated_at']);
  catalog_touch($db,$slug,['genres_at']);
  if ($row['airing_status']!=='') catalog_touch($db,$slug,['airing_at']);
  if (is_string($date) && preg_match('/^\d{4}-\d{2}-\d{2}$/D',$date)) sql($db,'UPDATE sa1_anime SET start_date=?,season=? WHERE slug=?',[$date,season_name($date),$slug]);
}
