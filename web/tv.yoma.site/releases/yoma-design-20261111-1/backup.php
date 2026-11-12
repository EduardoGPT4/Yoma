<?php
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED',true);
require __DIR__.'/private/app.php';
require __DIR__.'/private/backup.php';
try{
  if($_SERVER['REQUEST_METHOD']!=='POST')throw new WebError('Usa POST.',405);
  if(!hash_equals($_SESSION['csrf'],(string)($_SERVER['HTTP_X_CSRF_TOKEN']??'')))throw new WebError('La sesión cambió.',403);
  validate_session(db());admin_member(db());rate(db(),'backup:'.uid(),2,3600);
  $input=json_decode(file_get_contents('php://input',false,null,0,2048),true,8,JSON_THROW_ON_ERROR);
  $password=(string)($input['password']??'');backup_key($password,str_repeat('x',32));
  release_remote_session();
  // Complete before sending headers: a failed snapshot never downloads as a success.
  $stream=tmpfile();if(!$stream)throw new RuntimeException('No se pudo crear el respaldo temporal.');
  $info=backup_write(db(),$stream,$password);set_meta(db(),'backup_last',json_encode($info));
  header('Content-Type: application/octet-stream');header('Cache-Control: no-store');
  header('Content-Disposition: attachment; filename="YomaTV-'.gmdate('Ymd-His').'.sa1backup"');
  rewind($stream);fpassthru($stream);fclose($stream);
}catch(Throwable $error){
  http_response_code($error instanceof WebError?$error->status:500);
  header('Content-Type: application/json');echo json_encode(['ok'=>false,'message'=>$error instanceof WebError?$error->getMessage():'No se pudo crear el respaldo.']);
}
