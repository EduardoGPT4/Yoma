<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit(); }
function relation_types(): array
{
  return ['prequel'=>'Precuela','sequel'=>'Secuela','season'=>'Otra temporada','movie'=>'Película','special'=>'Especial','side_story'=>'Historia paralela','other'=>'Relacionado'];
}
function catalog_relations_import(PDO $db, string $slug, string $html, string $state): void
{
  // Read the label rendered by AnimeAV1, rather than guessing undocumented enum numbers.
  $media = LiteralReader::property($state,'media');
  if (!is_array($media) || ($media['slug']??'')!==$slug || !is_array($media['relations']??null)) return;
  foreach ($media['relations'] as $r) {
    $target = $r['destination']['slug']??'';
    if ($target===$slug || !sql($db,'SELECT slug FROM sa1_anime WHERE slug=?',[$target])->fetchColumn()) continue;
    $label = ''; $doc = new DOMDocument(); $prev = libxml_use_internal_errors(true);
    $doc->loadHTML('<?xml encoding="UTF-8">'.$html,LIBXML_NONET|LIBXML_NOERROR|LIBXML_NOWARNING); libxml_clear_errors();libxml_use_internal_errors($prev);
    $xpath = new DOMXPath($doc);
    foreach($xpath->query('//article') as $article) foreach($article->getElementsByTagName('a') as $a) if ($a->getAttribute('href')==='/media/'.$target) {
      foreach($article->getElementsByTagName('span') as $span) if(str_contains($span->getAttribute('class'),'text-xs')) $label=trim($span->textContent);
    }
    $type = ['precuela'=>'prequel','secuela'=>'sequel','historia paralela'=>'side_story','otro'=>'other','especial'=>'special','pelicula'=>'movie','temporada'=>'season'][title_key($label)]??'other';
    if (sql($db,'SELECT state FROM sa1_relations WHERE slug=? AND target=?',[$slug,$target])->fetchColumn()) continue;
    $row=['slug'=>$slug,'target'=>$target,'relation'=>$type,'evidence'=>'https://animeav1.com/media/'.$slug,'state'=>'pending','reviewed_by'=>null,'updated_at'=>time()];
    upsert($db,'sa1_relations',array_keys($row),[$row],['slug','target'],['evidence']);
  }
  catalog_touch($db,$slug,['relations_at']);
}
function catalog_relations(PDO $db, string $slug): array
{
  $admin = administrator($db);
  return sql($db,"SELECT r.target,r.relation,r.state,r.evidence,a.title,a.cover,a.category,a.start_date FROM sa1_relations r JOIN sa1_anime a ON a.slug=r.target WHERE r.slug=?".($admin?'':" AND r.state='approved'").' ORDER BY a.start_date,a.title',[$slug])->fetchAll();
}
/** Narrative seasons are distinct catalog entries, never the broadcast quarter. */
function series_seasons(PDO $db, string $slug): array
{
  $found=[$slug=>find_anime($db,$slug)];$frontier=[$slug];
  for($depth=0;$frontier&&$depth<8&&count($found)<60;$depth++){
    $marks=implode(',',array_fill(0,count($frontier),'?'));
    $rows=sql($db,"SELECT a.slug,a.title,a.category,a.start_date,r.relation FROM sa1_relations r JOIN sa1_anime a ON a.slug=r.target WHERE r.slug IN ($marks) AND r.state='approved' AND r.relation IN ('prequel','sequel','season','special') ORDER BY a.start_date,a.title LIMIT 120",$frontier)->fetchAll();
    $frontier=[];
    foreach($rows as $a){
      if(isset($found[$a['slug']])||count($found)>=60)continue;
      if($a['relation']!=='special'&&!in_array(title_key($a['category']),['tvanime','tv','ona','ova'],true))continue;
      $found[$a['slug']]=$a;$frontier[]=$a['slug'];
    }
  }
  $rows=array_values($found);usort($rows,fn($a,$b)=>strcmp($a['start_date']??'9999',$b['start_date']??'9999')?:strcmp($a['title'],$b['title']));
  return array_map(fn($a)=>['slug'=>$a['slug'],'title'=>$a['title'],'label'=>$a['title'],'category'=>$a['category'],'selected'=>$a['slug']===$slug],$rows);
}
function dispatch_catalog_relations(PDO $db, string $action, array $input): ?array
{
  if ($action!=='relation_review') return null;
  $user=admin_member($db); $slug=(string)($input['slug']??'');$target=(string)($input['target']??'');
  find_anime($db,$slug);find_anime($db,$target);
  $type=(string)($input['relation']??'');$state=(string)($input['state']??'approved');
  if ($slug===$target || !isset(relation_types()[$type]) || !in_array($state,['approved','rejected'],true)) throw new WebError('Relación inválida.');
  $old=sql($db,'SELECT evidence FROM sa1_relations WHERE slug=? AND target=?',[$slug,$target])->fetchColumn();
  $row=['slug'=>$slug,'target'=>$target,'relation'=>$type,'evidence'=>$old?:'Revisión manual del administrador','state'=>$state,'reviewed_by'=>$user,'updated_at'=>time()];
  $reverse=$row;$reverse['slug']=$target;$reverse['target']=$slug;
  $reverse['relation']=['prequel'=>'sequel','sequel'=>'prequel','season'=>'season'][$type]??'other';
  $db->beginTransaction();
  try {
    upsert($db,'sa1_relations',array_keys($row),[$row,$reverse],['slug','target'],['relation','state','reviewed_by','updated_at']);
    $db->commit();
  } catch(Throwable $error) {$db->rollBack();throw $error;}
  return ['detail'=>detail($db,$slug),'message'=>'Relación revisada.'];
}
