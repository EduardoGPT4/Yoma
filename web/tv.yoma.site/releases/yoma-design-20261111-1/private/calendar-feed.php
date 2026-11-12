<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit(); }
function calendar_subscriptions_enabled(): bool
{
  if (getenv('SEASON_WEB_SQLITE')) return true;
  $file=__DIR__.'/config.local.php';$config=is_file($file)?require $file:[];
  return ($config['calendar_subscriptions']??false)===true;
}
function ics_escape(string $v): string { return str_replace(['\\',"\r","\n",';',','],['\\\\','','\\n','\\;','\\,'],$v); }
function ics_line(string $line): string
{
  $out='';$limit=75;
  while(strlen($line)>$limit) { $part=mb_strcut($line,0,$limit,'UTF-8');$out.=$part."\r\n ";$line=substr($line,strlen($part));$limit=74; }
  return $out.$line."\r\n";
}
function calendar_body(PDO $db, int $user=0, string $scope='all'): string
{
  $where='a.active=1';$args=[];
  if ($scope==='followed') { $where.=" AND EXISTS(SELECT 1 FROM sa1_follow f WHERE f.slug=a.slug AND f.user_id=? AND f.excluded=0 AND (f.status IN ('watching','planned') OR f.favorite=1))";$args[]=$user; }
  $body=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//YomaTV//Horario semanal//ES','CALSCALE:GREGORIAN','METHOD:PUBLISH','X-WR-CALNAME:YomaTV · emisiones estimadas','REFRESH-INTERVAL;VALUE=DURATION:PT12H','X-PUBLISHED-TTL:PT12H'];
  foreach(sql($db,'SELECT a.* FROM sa1_anime a WHERE '.$where.' ORDER BY a.weekday,a.title',$args)->fetchAll() as $a) {
    if (!next_airing($a)) continue;
    $start=(new DateTimeImmutable($a['published']))->modify('+7 days')->getTimestamp();
    $body=array_merge($body,['BEGIN:VEVENT','UID:'.hash('sha256',meta($db,'installation').$a['slug']).'@seasonav1',
      'DTSTAMP:'.gmdate('Ymd\THis\Z',(int)meta($db,'catalog_updated','0')),'DTSTART:'.gmdate('Ymd\THis\Z',$start),
      'DTEND:'.gmdate('Ymd\THis\Z',$start+1800),'RRULE:FREQ=WEEKLY;UNTIL='.gmdate('Ymd\THis\Z',time()+90*86400),
      'SUMMARY:'.ics_escape($a['title'].' · estreno estimado'),
      'DESCRIPTION:'.ics_escape('Estimación semanal basada en AnimeAV1; puede cambiar. La suscripción se renueva cuando se actualiza el horario.'),
      'URL:https://animeav1.com/media/'.rawurlencode($a['slug']),'END:VEVENT']);
  }
  $body[]='END:VCALENDAR';return implode('',array_map('ics_line',$body));
}
function calendar_feed_path(string $key): string
{
  if (!preg_match('/^[a-f0-9]{64}$/D',$key)) throw new RuntimeException('Identificador de calendario inválido.');
  return application_root().'/feeds/'.$key.'.ics';
}
function calendar_write(PDO $db, array $feed, bool $creating=false): void
{
  $path=calendar_feed_path($feed['feed_key']);$temporary=$path.'.tmp';
  $own=!$db->inTransaction();if($own)$db->beginTransaction();
  try {
    if (!$creating) {
      $lock=$db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'?' FOR UPDATE':'';
      $current=sql($db,'SELECT feed_key FROM sa1_calendar_feeds WHERE user_id=?'.$lock,[$feed['user_id']])->fetchColumn();
      if ($current!==$feed['feed_key']) {if($own)$db->commit();return;}
    }
    $body=calendar_body($db,(int)$feed['user_id'],$feed['scope']);
    if (file_put_contents($temporary,$body,LOCK_EX)===false || !rename($temporary,$path)) throw new RuntimeException('No se pudo renovar el calendario.');
    sql($db,'UPDATE sa1_calendar_feeds SET updated_at=? WHERE user_id=? AND feed_key=?',[time(),$feed['user_id'],$feed['feed_key']]);
    if($own)$db->commit();
  } catch(Throwable $error) {if($own && $db->inTransaction())$db->rollBack();throw $error;}
}
function calendar_refresh_feeds(PDO $db, ?int $user=null): void
{
  $public=application_root().'/feeds/horario.ics';
  if ($user===null && (!is_file($public) || filemtime($public)<time()-43200 || filemtime($public)<(int)meta($db,'catalog_updated','0'))) {
    $temporary=$public.'.tmp';
    if (file_put_contents($temporary,calendar_body($db),LOCK_EX)===false || !rename($temporary,$public)) throw new RuntimeException('No se pudo renovar el calendario público.');
  }
  // Incremental refresh for dormant accounts; direct library edits refresh their own feed.
  $rows=sql($db,'SELECT * FROM sa1_calendar_feeds WHERE '.($user===null?'updated_at<? ORDER BY updated_at LIMIT 10':'user_id=?'),[$user??time()-43200])->fetchAll();
  foreach($rows as $feed) calendar_write($db,$feed);
}
function calendar_feed_info(PDO $db): ?array
{
  $r=sql($db,'SELECT feed_key,scope,updated_at FROM sa1_calendar_feeds WHERE user_id=?',[member()])->fetch();
  return $r?['url'=>'feeds/'.$r['feed_key'].'.ics','scope'=>$r['scope'],'updated_at'=>(int)$r['updated_at']]:null;
}
function dispatch_calendar(PDO $db, string $action, array $input): ?array
{
  if ($action==='calendar_feed') return ['calendar_feed'=>calendar_feed_info($db),'calendar_subscriptions_enabled'=>calendar_subscriptions_enabled()];
  if (!in_array($action,['calendar_create','calendar_revoke'],true)) return null;
  $user=member();
  if ($action==='calendar_create' && !calendar_subscriptions_enabled()) throw new WebError('InfinityFree exige JavaScript a los clientes externos. Usa la exportación .ics; la suscripción requiere un alojamiento compatible.',409);
  $scope=(string)($input['scope']??'followed');if(!in_array($scope,['all','followed'],true)) throw new WebError('Ámbito de calendario inválido.');
  if ($action==='calendar_create') rate($db,'calendar-create:'.$user,10,300);
  $feed=null;$db->beginTransaction();
  try {
    // Lock the owner even before their first feed exists. Two browser sessions
    // cannot leave an older private URL orphaned while creating or rotating it.
    if ($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql') sql($db,'SELECT id FROM sa1_users WHERE id=? FOR UPDATE',[$user])->fetchColumn();
    else sql($db,'UPDATE sa1_users SET auth_version=auth_version WHERE id=?',[$user]);
    $old=sql($db,'SELECT * FROM sa1_calendar_feeds WHERE user_id=?',[$user])->fetch();
    if ($action==='calendar_revoke') sql($db,'DELETE FROM sa1_calendar_feeds WHERE user_id=?',[$user]);
    else {
      $feed=['user_id'=>$user,'feed_key'=>bin2hex(random_bytes(32)),'scope'=>$scope,'updated_at'=>time()];
      // The old subscription stays intact if writing its replacement fails.
      calendar_write($db,$feed,true);
      upsert($db,'sa1_calendar_feeds',array_keys($feed),[$feed],['user_id'],['feed_key','scope','updated_at']);
    }
    $db->commit();
  } catch(Throwable $error) {
    if($db->inTransaction())$db->rollBack();
    if($feed)foreach([calendar_feed_path($feed['feed_key']),calendar_feed_path($feed['feed_key']).'.tmp'] as $path)if(is_file($path))unlink($path);
    throw $error;
  }
  if ($old && is_file(calendar_feed_path($old['feed_key']))) unlink(calendar_feed_path($old['feed_key']));
  if ($action==='calendar_revoke') return ['calendar_feed'=>null,'message'=>'Enlace de calendario revocado.'];
  return ['calendar_feed'=>calendar_feed_info($db),'message'=>'Suscripción creada. El enlace es privado: quien lo tenga podrá leer este horario.'];
}
