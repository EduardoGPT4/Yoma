<?php
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED', true);
require __DIR__ . '/private/app.php';
header('Referrer-Policy: no-referrer');
require_once __DIR__.'/private/yomashi-mal.php';
if(is_string($_GET['state']??null)&&str_starts_with($_GET['state'],'ys_')) ys_callback_page();
$callbackFlow=$_SESSION['mal_oauth']??null;
try {
  if ($_SERVER['REQUEST_METHOD'] !== 'GET') throw new WebError('Método no permitido.', 405);
  $result = mal_complete(db(), $_GET);
} catch (WebError $error) {
  $result = 'expired';
} catch (Throwable $error) {
  // No codes, secrets or provider responses in logs, HTML, or redirect URLs.
  $result = 'error';
}
// Feedback belongs to this authorization, even when another tab starts a newer one.
if(uid()&&is_array($callbackFlow)&&($callbackFlow['user_id']??0)===uid()){
  $database=db();$database->beginTransaction();
  try{
    $hash=sql($database,'SELECT state_hash FROM sa1_oauth_attempts WHERE user_id=?'.($database->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'?' FOR UPDATE':''),[uid()])->fetchColumn();
    if(is_string($hash)&&hash_equals($hash,hash('sha256',$callbackFlow['state']))&&hash_equals($callbackFlow['state'],(string)($_GET['state']??'')))
      upsert($database,'sa1_user_notices',['user_id','notice','created_at'],[['user_id'=>uid(),'notice'=>$result,'created_at'=>time()]],['user_id'],['notice','created_at']);
    $database->commit();
  }catch(Throwable $ignored){if($database->inTransaction())$database->rollBack();}
}
header('Location: ./?mal=' . $result . '#account', true, 303);
exit();
