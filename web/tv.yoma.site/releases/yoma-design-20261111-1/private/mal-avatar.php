<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {http_response_code(404);exit();}

function mal_avatar_url(mixed $value): string
{
  if (!is_string($value) || strlen($value)>2048 || preg_match('/[\x00-\x20\\\\]/',$value)) return '';
  $url=parse_url($value);
  return is_array($url) && ($url['scheme']??'')==='https' && ($url['host']??'')==='cdn.myanimelist.net'
    && !isset($url['user']) && !isset($url['pass'])
    && in_array($url['port']??443,[443],true) && !isset($url['fragment']) ? $value : '';
}
function mal_avatar_entry(?string $payload,int $account): array
{
  $entry=json_decode($payload??'',true);
  if (!is_array($entry) || (int)($entry['mal_id']??0)!==$account) return ['mal_id'=>$account,'picture'=>'','next_refresh'=>0];
  return ['mal_id'=>$account,'picture'=>mal_avatar_url($entry['picture']??''),'next_refresh'=>(int)($entry['next_refresh']??0)];
}
function mal_save_avatar(PDO $db,int $account,?string $picture): array
{
  $own=!$db->inTransaction();if($own)$db->beginTransaction();
  try {
    $row=sql($db,'SELECT mal_user_id FROM sa1_mal_connections WHERE user_id=? AND needs_auth=0'.($db->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql'?' FOR UPDATE':''),[member()])->fetch();
    if ((int)($row['mal_user_id']??0)!==$account) throw new WebError('La cuenta de MyAnimeList cambió.',409);
    $old=sql($db,"SELECT payload FROM sa1_personal_data WHERE user_id=? AND kind='mal_avatar' AND item_key='profile'",[uid()])->fetchColumn();
    $entry=mal_avatar_entry(is_string($old)?$old:null,$account);
    // Claim a short refresh lease while retaining a previously valid image on failure.
    if($picture===null && $entry['next_refresh']>time()){if($own)$db->commit();return ['claimed'=>false,...$entry];}
    $entry['next_refresh']=time()+($picture===null?600:86400);
    if($picture!==null)$entry['picture']=mal_avatar_url($picture);
    upsert($db,'sa1_personal_data',['user_id','kind','item_key','payload','updated_at'],[
      ['user_id'=>uid(),'kind'=>'mal_avatar','item_key'=>'profile','payload'=>json_encode($entry,JSON_THROW_ON_ERROR),'updated_at'=>time()]
    ],['user_id','kind','item_key'],['payload','updated_at']);
    if($own)$db->commit();return ['claimed'=>true,...$entry];
  }catch(Throwable $error){if($own && $db->inTransaction())$db->rollBack();throw $error;}
}
function mal_refresh_avatar(PDO $db): array
{
  $status=mal_status($db);
  if(!$status['connected'])return ['mal'=>$status];
  $account=$status['profile']['id'];
  try {
    $claim=mal_save_avatar($db,$account,null);
    if($claim['claimed']){
      $profile=mal_profile_data(mal_read($db,'profile',[],'GET',$account));
      if($profile['id']!==$account)throw new WebError('La cuenta de MyAnimeList cambió.',409);
      mal_save_avatar($db,$account,$profile['picture']);
    }
  }catch(MalRemoteError|WebError $error){/* Keep the last avatar during provider outages. */}
  return ['mal'=>mal_status($db)];
}
