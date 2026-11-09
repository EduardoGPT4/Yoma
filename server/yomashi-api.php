<?php
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED',true);
require __DIR__.'/private/app.php';
require __DIR__.'/private/yomashi-mal.php';
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
try {
  if($_SERVER['REQUEST_METHOD']!=='POST') throw new WebError('Usa POST.',405);
  if(stripos((string)($_SERVER['CONTENT_TYPE']??''),'application/json')!==0) throw new WebError('Usa JSON.',415);
  $raw=file_get_contents('php://input',false,null,0,8193);
  if(strlen($raw)>8192) throw new WebError('Solicitud demasiado grande.',413);
  $input=json_decode($raw,true,16,JSON_THROW_ON_ERROR);
  if(!is_array($input)) throw new WebError('Solicitud inválida.');
  $authorization=(string)($_SERVER['HTTP_AUTHORIZATION']??$_SERVER['REDIRECT_HTTP_AUTHORIZATION']??'');
  $bearer=str_starts_with($authorization,'Bearer ')?substr($authorization,7):'';
  // This host strips Authorization before PHP. Use a dedicated HTTPS header,
  // while rejecting conflicting credentials on hosts that forward both.
  $deviceHeader=(string)($_SERVER['HTTP_X_YOMASHI_TOKEN']??'');
  if($deviceHeader!=='') {
    if($bearer!=='' && !hash_equals($bearer,$deviceHeader)) throw new WebError('Credenciales de dispositivo incompatibles.',401);
    $bearer=$deviceHeader;
  }
  if(session_status()===PHP_SESSION_ACTIVE) session_write_close();
  echo json_encode(ys_dispatch(db(),$input,$bearer),JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE);
} catch(WebError $e) { http_response_code($e->status);echo json_encode(['error'=>$e->getMessage()]); }
catch(JsonException $e) { http_response_code(400);echo '{"error":"JSON inválido."}'; }
catch(MalRemoteError $e) { http_response_code(in_array($e->httpStatus,[401,403,404,429],true)?$e->httpStatus:502);echo '{"error":"MyAnimeList no pudo completar la solicitud. Reintenta o vuelve a conectar tu cuenta."}'; }
catch(Throwable $e) { http_response_code(500);echo '{"error":"No se pudo completar la operación."}'; }
