<?php
declare(strict_types=1);
$allowed=['index.php','actions.php','mal-callback.php','calendar.php','maintenance.php','catalog-public.php','backup.php','release-health.php','service-worker.php','app-manifest.php','yomashi-api.php','yomashi-connect.php'];
if(!isset($seasonEntry)||!in_array($seasonEntry,$allowed,true)){http_response_code(404);exit();}
$base=dirname(__DIR__);$pointer=json_decode((string)@file_get_contents(__DIR__.'/current.json'),true);
$id=$pointer['release']??'';
if(!is_string($id)||!preg_match('/^[a-z0-9][a-z0-9-]{5,63}$/D',$id)){http_response_code(503);exit('Publicación no disponible.');}
$folder=$base.'/releases/'.$id;
if(!is_file($folder.'/private/ready.json')||!is_file($folder.'/'.$seasonEntry)){http_response_code(503);exit('Publicación incompleta.');}
define('SEASON_APP_ROOT',$base);define('SEASON_RELEASE_ID',$id);
require $folder.'/'.$seasonEntry;
