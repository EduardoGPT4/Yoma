<?php
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED',true);
require __DIR__.'/private/app.php';
header('Content-Type: application/json');
try{
  $database=db();echo json_encode(['ok'=>true,'release'=>defined('SEASON_RELEASE_ID')?SEASON_RELEASE_ID:'development','schema'=>meta($database,'schema_version')]);
}catch(Throwable $error){http_response_code(503);echo '{"ok":false}';}
