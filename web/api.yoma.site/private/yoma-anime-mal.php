<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit; }
const YS_ANIME_STATUSES=['watching','completed','on_hold','dropped','plan_to_watch'];
// Fixed MAL v2 routes only: never accept a URL, redirect, or bearer from the app.
if (!function_exists('ys_anime_transport')) {
function ys_anime_transport(string $route,array $params,string $token,string $method='GET'):array {
  // These exact aliases were inspected in the active host's mal-http.php.
  if($route==='anime-list' && $method==='GET')return mal_http('list',$params,$token);
  if(preg_match('/^anime:([1-9][0-9]{0,8})$/D',$route,$m) && $method==='GET')return mal_http($route,$params,$token);
  if(preg_match('/^anime-list-status:([1-9][0-9]{0,8})$/D',$route,$m) && $method==='PATCH')return mal_http('list-status:'.$m[1],$params,$token,'PATCH');
  throw new LogicException('Invalid MAL anime route.');
}}
function ys_anime_normalize(array $node):array {
  $id=ys_id($node['id']??null);$title=$node['title']??null;$state=$node['my_list_status']??[];
  if(!is_string($title)||$title==='')throw new MalRemoteError(502);
  return ['id'=>$id,'title'=>$title,'picture'=>ys_profile_picture($node['main_picture']['medium']??''),'num_episodes'=>max(0,(int)($node['num_episodes']??0)),'year'=>max(0,(int)($node['start_season']['year']??0)),'episodes_watched'=>max(0,(int)($state['num_episodes_watched']??0)),'status'=>in_array($state['status']??null,YS_ANIME_STATUSES,true)?$state['status']:'plan_to_watch'];
}
function ys_anime_validate(array $input):void {
  $action=$input['action'];
  if($action==='anime_library' && (!in_array($input['status']??null,YS_ANIME_STATUSES,true)||!is_int($input['offset']??0)||($input['offset']??0)<0||($input['offset']??0)>1000000||!is_int($input['limit']??50)||($input['limit']??50)<1||($input['limit']??50)>100))throw new WebError('Filtro o página de anime inválidos.');
  if(in_array($action,['anime_detail','anime_update'],true))ys_id($input['id']??null);
  if($action==='anime_update') {
    foreach(['episodes_watched','expected_episodes'] as $key)if(!is_int($input[$key]??null)||$input[$key]<0||$input[$key]>100000)throw new WebError('Progreso de anime inválido.');
    if(array_key_exists('decrease',$input)&&!is_bool($input['decrease']))throw new WebError('Progreso de anime inválido.');
    if(!is_int($input['owner_id']??null)||$input['owner_id']<1)throw new WebError('Confirma la cuenta de MyAnimeList.',409);
  }
}
function ys_anime_dispatch(string $token,array $input):array {
  $action=$input['action'];
  if($action==='anime_capabilities')return ['anime'=>true,'conflict_check'=>true,'decrease'=>true];
  if($action==='anime_library') {
    $offset=$input['offset']??0;$limit=$input['limit']??50;$status=$input['status'];
    $response=ys_anime_transport('anime-list',['status'=>$status,'offset'=>$offset,'limit'=>$limit,'sort'=>'anime_title','fields'=>'id,title,main_picture,num_episodes,start_season,list_status'],$token);
    $rows=$response['data']??null;if(!is_array($rows)||count($rows)>$limit)throw new MalRemoteError(502);
    $items=[];foreach($rows as $row){if(!is_array($row['node']??null)||!in_array($row['list_status']['status']??null,YS_ANIME_STATUSES,true))throw new MalRemoteError(502);if($row['list_status']['status']!==$status)continue;$items[]=ys_anime_normalize([...$row['node'],'my_list_status'=>$row['list_status']]);}
    $next=is_string($response['paging']['next']??null)&&$response['paging']['next']!=='';
    if($next&&count($rows)===0)throw new MalRemoteError(502);
    return ['items'=>$items,'next_offset'=>$next?$offset+count($rows):null];
  }
  $id=ys_id($input['id']);
  $anime=ys_anime_normalize(ys_anime_transport('anime:'.$id,['fields'=>'id,title,main_picture,num_episodes,start_season,my_list_status'],$token));
  if($action==='anime_detail')return ['anime'=>$anime];
  $wanted=$input['episodes_watched'];
  if($wanted===$anime['episodes_watched'] && $wanted>=$input['expected_episodes'])return ['anime'=>$anime];
  if($anime['episodes_watched']!==$input['expected_episodes'])throw new WebError('El progreso cambió en MAL. Revisa el conflicto antes de sincronizar.',409);
  // Bajar el progreso solo es posible como deshacer explícito (el usuario desmarcó un episodio
  // en Yoma) y, por la comprobación anterior, solo si MAL sigue exactamente donde Yoma lo dejó.
  $lower=$wanted<$anime['episodes_watched'];
  if($lower&&($input['decrease']??false)!==true)throw new WebError('No se reducirá el progreso de MAL automáticamente.',409);
  if($anime['num_episodes']>0&&$wanted>$anime['num_episodes'])throw new WebError('El progreso supera los episodios del anime en MAL. Revisa el vínculo.',409);
  if($wanted===$anime['episodes_watched'])return ['anime'=>$anime]; // Retry after a lost response is harmless.
  if($lower)$status=$anime['status']==='completed'?'watching':$anime['status'];
  else{
    $status=in_array($anime['status'],['completed','on_hold','dropped'],true)?$anime['status']:'watching';
    if($status==='watching'&&$anime['num_episodes']>0&&$wanted===$anime['num_episodes'])$status='completed';
  }
  $saved=ys_anime_transport('anime-list-status:'.$id,['num_watched_episodes'=>$wanted,'status'=>$status],$token,'PATCH');
  if(!is_int($saved['num_episodes_watched']??null)||$saved['num_episodes_watched']!==$wanted||!in_array($saved['status']??null,YS_ANIME_STATUSES,true))throw new MalRemoteError(502);
  return ['anime'=>[...$anime,'episodes_watched'=>$wanted,'status'=>$saved['status']]];
}
