<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit(); }

// Uses the host's existing private MAL configuration. No app secret is sent to Android.
const YS_ORIGIN = 'https://tv.yoma.site/';
const YS_STATUSES = ['reading','completed','on_hold','dropped','plan_to_read'];
function ys_schema(PDO $db): void {
  $db->exec('CREATE TABLE IF NOT EXISTS sa1_yomashi_devices (id VARCHAR(64) PRIMARY KEY, token_hash VARCHAR(64) NOT NULL UNIQUE, tokens TEXT NULL, mal_user_id BIGINT NULL, mal_name VARCHAR(60) NULL, expires_at BIGINT NOT NULL, created_at BIGINT NOT NULL)');
}
function ys_id(mixed $input): int {
  if (!is_int($input) || $input<1 || $input>999999999) throw new WebError('ID de manga inválido.');
  return $input;
}
function ys_profile_picture(mixed $value): string {
  if(!is_string($value) || strlen($value)>2048 || preg_match('/[\x00-\x20\\\\]/',$value)) return '';
  $url=parse_url($value);
  return is_array($url) && ($url['scheme']??'')==='https' && ($url['host']??'')==='cdn.myanimelist.net'
    && !isset($url['user']) && !isset($url['pass']) && !isset($url['fragment'])
    && ($url['port']??443)===443 ? $value : '';
}
function ys_profile(array $response): array {
  $identity=mal_profile_data($response);
  return ['id'=>$identity['id'],'name'=>$identity['name'],'picture'=>ys_profile_picture($response['picture']??'')];
}
function ys_crypt(string $input, string $device, bool $decrypt=false): string {
  $key=base64_decode(mal_require_config()['encryption_key'],true);
  if($decrypt) {
    $raw=base64_decode($input,true);
    $result=$raw && strlen($raw)>28?openssl_decrypt(substr($raw,28),'aes-256-gcm',$key,OPENSSL_RAW_DATA,substr($raw,0,12),substr($raw,12,16),'YomaShi:'.$device):false;
  } else {
    $iv=random_bytes(12);$tag='';
    $cipher=openssl_encrypt($input,'aes-256-gcm',$key,OPENSSL_RAW_DATA,$iv,$tag,'YomaShi:'.$device);
    $result=$cipher===false?false:base64_encode($iv.$tag.$cipher);
  }
  if($result===false) throw new WebError('Vuelve a conectar MyAnimeList.',401);
  return $result;
}
function ys_start(PDO $db): array {
  mal_require_config();ys_schema($db);
  rate($db,'ys-pair-ip:'.hash('sha256',(string)($_SERVER['REMOTE_ADDR']??'')),6,600);
  rate($db,'ys-pair-global',100,3600);
  sql($db,'DELETE FROM sa1_yomashi_devices WHERE expires_at<?',[time()]);
  $id=bin2hex(random_bytes(16));$token=bin2hex(random_bytes(32));$expires=time()+600;
  sql($db,'INSERT INTO sa1_yomashi_devices (id,token_hash,expires_at,created_at) VALUES (?,?,?,?)',[$id,hash('sha256',$token),$expires,time()]);
  return ['device_id'=>$id,'device_token'=>$token,'connect_url'=>YS_ORIGIN.'yomashi-connect.php?device='.$id,'expires_at'=>$expires,'code'=>strtoupper(substr($id,0,6))];
}
function ys_begin(PDO $db,string $id): string {
  if(!preg_match('/^[a-f0-9]{32}$/D',$id)) throw new WebError('Conexión inválida.');
  ys_schema($db);$row=sql($db,'SELECT id FROM sa1_yomashi_devices WHERE id=? AND expires_at>? AND tokens IS NULL',[$id,time()])->fetch();
  if(!$row) throw new WebError('La conexión caducó. Iníciala otra vez desde YomaShi.',410);
  $config=mal_require_config();$state='ys_'.bin2hex(random_bytes(24));$verifier=bin2hex(random_bytes(48));
  $_SESSION['yomashi_oauth']=['device'=>$id,'state'=>$state,'verifier'=>$verifier,'issued_at'=>time()];
  return 'https://myanimelist.net/v1/oauth2/authorize?'.http_build_query(['response_type'=>'code','client_id'=>$config['client_id'],'redirect_uri'=>$config['redirect_uri'],'state'=>$state,'code_challenge'=>$verifier,'code_challenge_method'=>'plain'],'','&',PHP_QUERY_RFC3986);
}
function ys_complete(PDO $db,array $query): array {
  $flow=$_SESSION['yomashi_oauth']??null;
  if(!is_array($flow) || !is_string($query['state']??null) || !hash_equals($flow['state'],$query['state'])) throw new WebError('La autorización no corresponde a esta conexión.',400);
  unset($_SESSION['yomashi_oauth']);
  if(time()-$flow['issued_at']>600 || isset($query['error'])) throw new WebError('Autorización cancelada o caducada.',410);
  $code=$query['code']??null;
  if(!is_string($code) || strlen($code)<1 || strlen($code)>4096) throw new WebError('Código de autorización inválido.',400);
  $config=mal_require_config();
  $tokens=mal_tokens(mal_http('token',['grant_type'=>'authorization_code','client_id'=>$config['client_id'],'client_secret'=>$config['client_secret'],'redirect_uri'=>$config['redirect_uri'],'code'=>$code,'code_verifier'=>$flow['verifier']]));
  $profile=ys_profile(mal_http('profile',[],$tokens['access_token']));
  $tokens['profile']=$profile;$tokens['profile_next_refresh']=time()+86400;
  $cipher=ys_crypt(json_encode($tokens,JSON_THROW_ON_ERROR),$flow['device']);
  $changed=sql($db,'UPDATE sa1_yomashi_devices SET tokens=?,mal_user_id=?,mal_name=?,expires_at=? WHERE id=? AND tokens IS NULL AND expires_at>?',[$cipher,$profile['id'],$profile['name'],time()+90*86400,$flow['device'],time()])->rowCount();
  if($changed!==1) throw new WebError('La conexión caducó. Vuelve a iniciarla en YomaShi.',410);
  return $profile;
}
function ys_callback_page(): never {
  try {
    if($_SERVER['REQUEST_METHOD']!=='GET') throw new WebError('Método no permitido.',405);
    ys_complete(db(),$_GET);$message='Cuenta conectada. Vuelve a YomaShi para continuar.';
  } catch(WebError $e) { http_response_code($e->status);$message=$e->getMessage(); }
  catch(Throwable $e) { http_response_code(502);$message='No se pudo conectar MyAnimeList. Vuelve a intentarlo desde YomaShi.'; }
  header('Content-Type: text/html; charset=utf-8');header('Referrer-Policy: no-referrer');
  echo '<!doctype html><html lang="es"><meta name="viewport" content="width=device-width"><title>YomaShi</title><body><h1>YomaShi · MyAnimeList</h1><p>'.htmlspecialchars($message,ENT_QUOTES,'UTF-8').'</p></body></html>';exit;
}
function ys_normalize(array $m): array {
  $id=ys_id($m['id']??null);$title=$m['title']??null;
  if(!is_string($title) || $title==='') throw new MalRemoteError(502);
  $state=$m['my_list_status']??[];
  $alternatives=$m['alternative_titles']??[];$titles=[];
  if(is_array($alternatives)) {
    foreach([$alternatives['en']??'', $alternatives['ja']??'', ...(is_array($alternatives['synonyms']??null)?$alternatives['synonyms']:[])] as $name) {
      if(is_string($name) && trim($name)!=='' && strlen($name)<=300) $titles[]=trim($name);
    }
  }
  return ['id'=>$id,'title'=>$title,'picture'=>ys_profile_picture($m['main_picture']['medium']??''),'alternative_titles'=>array_slice(array_values(array_unique($titles)),0,16),'num_chapters'=>(int)($m['num_chapters']??0),'publishing_status'=>(string)($m['status']??''),'status'=>in_array($state['status']??'',YS_STATUSES,true)?$state['status']:'plan_to_read','chapters_read'=>max(0,(int)($state['num_chapters_read']??0))];
}
function ys_manga(string $token,int $id): array {
  return ys_normalize(mal_http('manga:'.$id,['fields'=>'id,title,main_picture,num_chapters,status,alternative_titles,my_list_status{status,num_chapters_read}'],$token));
}
function ys_library(string $token,array $input): array {
  $status=$input['status'];$offset=$input['offset']??0;$limit=$input['limit']??50;
  $response=mal_http('manga-list',['status'=>$status,'offset'=>$offset,'limit'=>$limit,'sort'=>'manga_title','fields'=>'id,title,main_picture,num_chapters,status,alternative_titles,list_status'],$token);
  $rows=$response['data']??null;
  if(!is_array($rows) || count($rows)>$limit) throw new MalRemoteError(502);
  $items=[];
  foreach($rows as $row) {
    if(!is_array($row) || !is_array($row['node']??null) || !is_array($row['list_status']??null) || !in_array($row['list_status']['status']??'',YS_STATUSES,true)) throw new MalRemoteError(502);
    if($row['list_status']['status']!==$status) continue;
    $node=$row['node'];$node['my_list_status']=$row['list_status'];$items[]=ys_normalize($node);
  }
  $hasNext=is_string($response['paging']['next']??null) && $response['paging']['next']!=='';
  if($hasNext && count($rows)===0) throw new MalRemoteError(502);
  return ['items'=>$items,'next_offset'=>$hasNext?$offset+count($rows):null];
}
function ys_access_tokens(PDO $db,array $row,array $tokens,bool &$refreshed): array {
  if(($tokens['expires_at']??0)<time()+60) {
    $config=mal_require_config();
    $next=mal_tokens(mal_http('token',['grant_type'=>'refresh_token','client_id'=>$config['client_id'],'client_secret'=>$config['client_secret'],'refresh_token'=>$tokens['refresh_token']]),$tokens['refresh_token']);
    // Preserve the encrypted profile cache when MAL rotates its tokens.
    $tokens=array_replace($tokens,$next);
    sql($db,'UPDATE sa1_yomashi_devices SET tokens=? WHERE id=?',[ys_crypt(json_encode($tokens,JSON_THROW_ON_ERROR),$row['id']),$row['id']]);
    $refreshed=true;
  }
  return $tokens;
}
function ys_status(PDO $db,array $row,bool &$refreshed): array {
  if($row['tokens']===null) return ['connected'=>false,'profile'=>null];
  $tokens=json_decode(ys_crypt($row['tokens'],$row['id'],true),true,16,JSON_THROW_ON_ERROR);
  $cached=$tokens['profile']??null;
  $profile=['id'=>(int)$row['mal_user_id'],'name'=>$row['mal_name'],'picture'=>''];
  if(is_array($cached) && ($cached['id']??null)===$profile['id']) {
    $profile['picture']=ys_profile_picture($cached['picture']??'');
  }
  if(($tokens['profile_next_refresh']??0)>time()) return ['connected'=>true,'profile'=>$profile];
  // Legacy sessions have no profile cache and are upgraded on their next status
  // request. Provider outages retain the last image and back off for ten minutes.
  $tokens['profile_next_refresh']=time()+600;
  try {
    $tokens=ys_access_tokens($db,$row,$tokens,$refreshed);
    $next=ys_profile(mal_http('profile',[],$tokens['access_token']));
    // Never keep an apparently connected device whose token now represents a
    // different account: the common 401 path revokes it before any later writes.
    if($next['id']!==$profile['id']) throw new MalRemoteError(401,'identity_changed');
    $profile=$next;$tokens['profile']=$profile;$tokens['profile_next_refresh']=time()+86400;
    sql($db,'UPDATE sa1_yomashi_devices SET mal_name=? WHERE id=? AND mal_user_id=?',[$profile['name'],$row['id'],$profile['id']]);
  } catch(MalRemoteError|WebError $error) {
    if($error instanceof MalRemoteError && ($error->httpStatus===401 || $error->kind==='invalid_grant')) throw $error;
  }
  sql($db,'UPDATE sa1_yomashi_devices SET tokens=? WHERE id=?',[ys_crypt(json_encode($tokens,JSON_THROW_ON_ERROR),$row['id']),$row['id']]);
  return ['connected'=>true,'profile'=>$profile];
}
function ys_dispatch(PDO $db,array $input,string $bearer): array {
  ys_schema($db);$action=$input['action']??'';
  if($action==='start') return ys_start($db);
  if(!preg_match('/^[a-f0-9]{64}$/D',$bearer)) throw new WebError('Conecta tu cuenta de MyAnimeList.',401);
  // Reject bad inputs before a possible OAuth refresh with rotating credentials.
  if(!in_array($action,['status','disconnect','search','detail','update','library'],true)) throw new WebError('Operación no disponible.',404);
  if($action==='library' && (!in_array($input['status']??null,['reading','plan_to_read'],true) || !is_int($input['offset']??0) || ($input['offset']??0)<0 || ($input['offset']??0)>1000000 || !is_int($input['limit']??50) || ($input['limit']??50)<1 || ($input['limit']??50)>100)) throw new WebError('Filtro o página de la lista MAL inválidos.');
  if($action==='search' && (!is_string($input['query']??null) || strlen(trim($input['query']))<3 || strlen(trim($input['query']))>192)) throw new WebError('Escribe al menos tres caracteres o usa el ID.');
  if(in_array($action,['detail','update'],true)) ys_id($input['id']??null);
  if($action==='update' && (!is_int($input['chapters_read']??null) || $input['chapters_read']<0 || $input['chapters_read']>100000 || !in_array($input['status']??null,YS_STATUSES,true))) throw new WebError('Capítulos o estado inválidos.');
  rate($db,'ys-device:'.hash('sha256',$bearer),120,60);
  $refreshed=false;
  $db->beginTransaction();
  try {
    $row=sql($db,'SELECT * FROM sa1_yomashi_devices WHERE token_hash=? AND expires_at>?'.($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'?' FOR UPDATE':''),[hash('sha256',$bearer),time()])->fetch();
    if(!$row) throw new WebError('La conexión caducó. Vuelve a conectar MyAnimeList.',401);
    if($action==='disconnect') { sql($db,'DELETE FROM sa1_yomashi_devices WHERE id=?',[$row['id']]);$db->commit();return ['connected'=>false]; }
    if($action==='status') { $result=ys_status($db,$row,$refreshed);$db->commit();return $result; }
    if($row['tokens']===null) throw new WebError('Termina la autorización en el navegador.',409);
    if(isset($input['owner_id']) && $input['owner_id']!==(int)$row['mal_user_id']) throw new WebError('La cuenta cambió. Vuelve a seleccionar el manga.',409);
    $tokens=json_decode(ys_crypt($row['tokens'],$row['id'],true),true,16,JSON_THROW_ON_ERROR);
    $tokens=ys_access_tokens($db,$row,$tokens,$refreshed);
    $token=$tokens['access_token'];
    if($action==='search') {
      $q=trim((string)($input['query']??''));
      if(strlen($q)<3 || strlen($q)>192) throw new WebError('Escribe al menos tres caracteres o usa el ID.');
      $results=mal_http('manga-search',['q'=>$q,'limit'=>10,'fields'=>'id,title,main_picture,num_chapters,status,my_list_status{status,num_chapters_read}'],$token);
      $result=['items'=>array_map(fn($e)=>ys_normalize($e['node']),$results['data']??[])];
    } elseif($action==='library') $result=ys_library($token,$input);
    elseif($action==='detail') $result=['manga'=>ys_manga($token,ys_id($input['id']??null))];
    elseif($action==='update') {
      $id=ys_id($input['id']??null);$chapters=$input['chapters_read']??null;$status=$input['status']??null;
      if(!is_int($chapters) || $chapters<0 || $chapters>100000 || !in_array($status,YS_STATUSES,true)) throw new WebError('Capítulos o estado inválidos.');
      $m=ys_manga($token,$id);
      if(($input['automatic']??false)===true) {
        $chapters=max($chapters,$m['chapters_read']);
        $status=in_array($m['status'],['completed','on_hold','dropped'],true)?$m['status']:'reading';
        if($status==='reading' && $m['publishing_status']==='finished' && $m['num_chapters']>0 && $chapters>=$m['num_chapters']) $status='completed';
      }
      if($m['num_chapters']>0 && $chapters>$m['num_chapters']) throw new WebError('El progreso supera los capítulos del manga en MAL. Comprueba el vínculo o ajusta el número.');
      $saved=mal_http('manga-list-status:'.$id,['status'=>$status,'num_chapters_read'=>$chapters],$token,'PATCH');
      $result=['manga'=>[...$m,'status'=>$saved['status'],'chapters_read'=>(int)$saved['num_chapters_read']]];
    } else throw new WebError('Operación no disponible.',404);
    $db->commit();return $result;
  } catch(Throwable $e) {
    if($e instanceof MalRemoteError && ($e->httpStatus===401 || $e->kind==='invalid_grant') && isset($row['id'])) {
      sql($db,'DELETE FROM sa1_yomashi_devices WHERE id=?',[$row['id']]);
      if($db->inTransaction())$db->commit();
      throw new WebError('La autorización de MyAnimeList caducó. Conecta tu cuenta otra vez.',401);
    }
    // The refresh token can be single-use. Keep its replacement even if a later
    // manga request fails; these transactions contain no other local mutations.
    if($db->inTransaction()) { if($refreshed)$db->commit();else $db->rollBack(); }
    throw $e;
  }
}
