<?php
// Immutable Yoma identity extension. Resolve YomaTV's current backend per request.
$base=__DIR__;
$current=json_decode((string)@file_get_contents($base.'/private/current.json'),true);
$id=$current['release']??'';
if(!is_string($id)||!preg_match('/^[a-z0-9][a-z0-9-]{5,63}$/D',$id)){http_response_code(503);exit('Publicación no disponible.');}
$bootstrap=$base.'/releases/'.$id.'/private/app.php';
if(!is_file($bootstrap)||!is_file($base.'/releases/'.$id.'/private/ready.json')){http_response_code(503);exit('Publicación incompleta.');}
define('SEASON_APP_ROOT',$base);define('SEASON_RELEASE_ID',$id);
define('YOMA_WEB_BOOTSTRAP',$bootstrap);
require $base.'/releases/yoma-bridge-a49ba5fd34aed365/yoma-session.php';
