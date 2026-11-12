<?php
$root=__DIR__;
$current=json_decode((string)@file_get_contents($root.'/private/current.json'),true);
$id=$current['release']??'';
if(!is_string($id)||!preg_match('/^[a-z0-9][a-z0-9-]{5,63}$/D',$id)||!is_file($root.'/releases/'.$id.'/private/ready.json')){http_response_code(503);exit;}
define('SEASON_APP_ROOT',$root);define('SEASON_RELEASE_ID',$id);
define('YOMA_WEB_BOOTSTRAP',$root.'/releases/'.$id.'/private/app.php');
require $root.'/releases/yoma-native-mal-464c8a1095fdcd5e/yomashi-api.php';
