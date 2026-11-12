<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {http_response_code(404);exit();}
function dispatch_match_review(PDO $db,string $action,array $input): ?array
{
  if(!in_array($action,['mal_match_batch','mal_link_batch','progress_reconcile'],true))return null;
  member();$account=mal_identity_id($db);
  if(isset($input['mal_account_id']) && $input['mal_account_id']!==$account)throw new WebError('La cuenta MAL cambió. Reabre la revisión.',409);
  if($action==='mal_match_batch'){
    $page=max(1,(int)($input['page']??1));$total=(int)sql($db,'SELECT COUNT(*) FROM sa1_mal_list l LEFT JOIN sa1_mal_links k ON k.user_id=l.user_id AND k.mal_id=l.mal_id WHERE l.user_id=? AND COALESCE(k.confirmed,0)=0',[uid()])->fetchColumn();$pages=max(1,(int)ceil($total/8));$page=min($page,$pages);
    $items=sql($db,'SELECT m.*,k.slug AS linked_slug FROM sa1_mal_list l JOIN sa1_mal_anime m ON m.mal_id=l.mal_id LEFT JOIN sa1_mal_links k ON k.user_id=l.user_id AND k.mal_id=l.mal_id WHERE l.user_id=? AND COALESCE(k.confirmed,0)=0 ORDER BY m.title LIMIT 8 OFFSET '.(($page-1)*8),[uid()])->fetchAll();
    $locals=sql($db,'SELECT a.slug,a.title,a.category,a.start_date,a.cover,a.season,a.catalog_complete,COUNT(e.id) AS episodes FROM sa1_anime a LEFT JOIN sa1_episodes e ON e.slug=a.slug GROUP BY a.slug,a.title,a.category,a.start_date,a.cover,a.season,a.catalog_complete')->fetchAll();
    foreach($items as &$item){$rank=[];$names=json_decode($item['aliases'],true)?:[$item['title']];foreach($locals as $local){$score=0;foreach($names as $name){similar_text(title_key($name),title_key($local['title']),$n);$score=max($score,$n);}if($score<45)continue;$rank[]=$local+['match_score'=>round($score),'compatible'=>compatible_match($local,$item)];}usort($rank,static fn($a,$b)=>$b['match_score']<=>$a['match_score']);$item['candidates']=array_slice($rank,0,6);}
    return ['match_batch'=>['items'=>$items,'total'=>$total,'page'=>$page,'pages'=>$pages,'mal_account_id'=>$account]];
  }
  if($action==='mal_link_batch'){
    $pairs=$input['pairs']??null;if(!is_array($pairs)||!$pairs||count($pairs)>20)throw new WebError('Revisa hasta veinte coincidencias por lote.');$ids=[];$slugs=[];
    foreach($pairs as $pair){$id=(int)($pair['mal_id']??0);$slug=(string)($pair['slug']??'');find_anime($db,$slug);
      if(!$id||in_array($id,$ids,true)||in_array($slug,$slugs,true)||!sql($db,'SELECT mal_id FROM sa1_mal_list WHERE user_id=? AND mal_id=?',[uid(),$id])->fetchColumn())throw new WebError('El lote contiene una ficha ajena o duplicada.');$ids[]=$id;$slugs[]=$slug;
      $old=sql($db,'SELECT slug,mal_id FROM sa1_mal_links WHERE user_id=? AND (slug=? OR mal_id=?)',[uid(),$slug,$id])->fetch();if($old && ($old['slug']!==$slug||(int)$old['mal_id']!==$id))throw new WebError('Ya existe otro vínculo para una ficha seleccionada. Revísalo individualmente.',409);
    }
    $db->beginTransaction();try{foreach($pairs as $pair){$row=['user_id'=>uid(),'slug'=>$pair['slug'],'mal_id'=>(int)$pair['mal_id'],'confirmed'=>1];upsert($db,'sa1_mal_links',array_keys($row),[$row],['user_id','slug'],['mal_id','confirmed']);mal_copy_follow($db,$pair['slug'],(int)$pair['mal_id']);}$db->commit();}catch(Throwable $error){$db->rollBack();throw $error;}
    return ['home'=>home_data($db),'patch'=>state_patch($db,$slugs),'message'=>count($pairs).' coincidencias revisadas y vinculadas.'];
  }
  $slug=(string)($input['slug']??'');find_anime($db,$slug);
  $m=sql($db,'SELECT l.*,m.title FROM sa1_mal_links k JOIN sa1_mal_list l ON l.user_id=k.user_id AND l.mal_id=k.mal_id JOIN sa1_mal_anime m ON m.mal_id=l.mal_id WHERE k.user_id=? AND k.slug=?',[uid(),$slug])->fetch();
  if(!$m)throw new WebError('Primero conecta, consulta tu lista y vincula este anime con MAL.',409);
  if(($input['confirmation']??'')!=='CORREGIR')throw new WebError('Confirma cómo reconciliar el progreso.',409);
  if(($input['direction']??'')==='mal_to_web'){
    mal_cancel_progress($db,$slug);progress_fence($db,$slug);progress_reconcile_local($db,$slug,(int)$m['watched']);
    return ['patch'=>state_patch($db,[$slug]),'detail'=>detail($db,$slug),'message'=>'Marcas locales ajustadas al progreso consultado de MAL.'];
  }
  if(($input['direction']??'')==='web_to_mal'){
    if(!(int)sql($db,'SELECT confirmed FROM sa1_mal_links WHERE user_id=? AND slug=?',[uid(),$slug])->fetchColumn())throw new WebError('Confirma primero la ficha MAL antes de enviar progreso.',409);
    $target=0;foreach(sql($db,'SELECT e.number_value FROM sa1_watched w JOIN sa1_episodes e ON e.id=w.episode_id WHERE w.user_id=? AND e.slug=? AND e.number_value>=1',[uid(),$slug])->fetchAll() as $ep)if((float)$ep['number_value']===(float)(int)$ep['number_value'])$target=max($target,(int)$ep['number_value']);
    return dispatch_mal_library($db,'mal_save',['mal_id'=>(int)$m['mal_id'],'mal_account_id'=>$account,'status'=>$m['status'],'score'=>(int)$m['score'],'watched'=>$target,'reconcile_local'=>true,'confirmation'=>'CORREGIR']);
  }
  throw new WebError('Elige una dirección de sincronización.');
}
