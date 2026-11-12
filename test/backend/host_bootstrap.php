<?php
// Isolated localhost fixture for the host contract. Never installed or published.
declare(strict_types=1);
session_start();$_SESSION['csrf']??=bin2hex(random_bytes(24));
header('Cache-Control: no-store');
// Match the production policy so browser tests exercise redirected form submits.
header("Content-Security-Policy: default-src 'self'; script-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'");
class WebError extends RuntimeException { function __construct(string $m,public int $status=422){parent::__construct($m);} }
class MalRemoteError extends RuntimeException { function __construct(public int $httpStatus,public string $kind=''){parent::__construct('MAL fixture failed');} }
function db():PDO { static $db;$db??=new PDO('sqlite:'.getenv('YS_TEST_DB'),null,null,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);return $db; }
function sql(PDO $db,string $query,array $args=[]):PDOStatement { $q=$db->prepare($query);$q->execute($args);return $q; }
function rate(PDO $db,string $key,int $max,int $seconds):void {}
function mal_require_config():array { return ['client_id'=>'fixture-client','client_secret'=>'fixture-secret-DO-NOT-PUBLISH-REAL-VALUES','redirect_uri'=>'https://tv.yoma.site/mal-callback.php','encryption_key'=>base64_encode(hash('sha256','local-fixture-key',true))]; }
function mal_tokens(array $r,?string $refresh=null):array { if(!is_string($r['access_token']??null))throw new MalRemoteError(502);return ['access_token'=>$r['access_token'],'refresh_token'=>$r['refresh_token']??$refresh,'expires_at'=>time()+(int)$r['expires_in']]; }
function mal_profile_data(array $r):array { return ['id'=>(int)$r['id'],'name'=>(string)$r['name']]; }
function mal_http(string $endpoint,array $params=[],?string $token=null,string $method='GET'):array {
  $url=getenv('YS_TEST_MOCK').'/'.$endpoint;
  if(!str_starts_with($url,'http://127.0.0.1:'))throw new RuntimeException('Local fixtures only');
  if($endpoint==='token')$method='POST';
  $query=http_build_query($params);
  if($method==='GET'&&$query!=='')$url.='?'.$query;
  $headers=['Accept: application/json'];
  if($token!==null)$headers[]='Authorization: Bearer '.$token;
  if($method!=='GET')$headers[]='Content-Type: application/x-www-form-urlencoded';
  $curl=curl_init($url);curl_setopt_array($curl,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_CUSTOMREQUEST=>$method,CURLOPT_HTTPHEADER=>$headers,CURLOPT_TIMEOUT=>5]);
  if($method!=='GET')curl_setopt($curl,CURLOPT_POSTFIELDS,$query);
  $raw=curl_exec($curl);$status=(int)curl_getinfo($curl,CURLINFO_HTTP_CODE);unset($curl);
  if($status<200||$status>=300)throw new MalRemoteError($status,(json_decode($raw,true)['error']??'')==='invalid_grant'?'invalid_grant':'');
  return json_decode($raw,true,32,JSON_THROW_ON_ERROR);
}

function ys_anime_transport(string $route,array $params,string $token,string $method="GET"):array{return mal_http($route,$params,$token,$method);}
