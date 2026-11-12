<?php
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED',true);
require __DIR__.'/private/app.php';
// Public projection only. No follows, notes, MAL identity, tokens or job state.
$items=sql(db(),'SELECT slug,title,category FROM sa1_anime ORDER BY slug')->fetchAll();
$content=sql(db(),'SELECT slug,title,synopsis,cover,category FROM sa1_anime ORDER BY slug')->fetchAll();
$version=hash('sha256',json_encode($content,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: public, max-age=0, must-revalidate');
header('ETag: "'.$version.'"');
if (($_SERVER['HTTP_IF_NONE_MATCH']??'')==='"'.$version.'"') { http_response_code(304);exit(); }
echo json_encode(['version'=>$version,'updated_at'=>(int)meta(db(),'directory_updated','0'),'items'=>$items],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR);
