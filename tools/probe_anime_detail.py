from audit_anime_source import *
s=PublicSource();f=ROOT/'docs/yoma/source-audit'
status,raw,_=s.get('actions.php?action=state');state=json.loads(raw)['data']
status,raw,_=s.get('actions.php?action=catalog&page=1');cat=json.loads(raw)['catalog'];a=next(x for x in cat['items'] if x.get('episodes',0)>0)
status,raw,_=s.get('actions.php?action=detail&slug='+urllib.parse.quote(a['slug']));(f/'detail.json').write_bytes(raw);data=json.loads(raw);detail=data.get('detail',{})
print(json.dumps({'catalog_keys':list(cat),'catalog_total':cat.get('total'),'anime_keys':list(a),'detail_status':status,'detail_keys':list(detail),'detail_anime_keys':list(detail.get('anime',{})),'episode_sample':detail.get('episodes',[])[:1],'other_fields':{k:v for k,v in detail.items() if k not in ['anime','episodes']}},ensure_ascii=False)[:6500])
episodes=detail.get('episodes',[])
if episodes:
 state=json.loads(s.get('actions.php?action=state')[1])['data']
 cookie='; '.join(['__test='+s.cookie]+[c.name+'='+c.value for c in s.jar if c.name!='__test'])
 body=json.dumps({'action':'player','episode_id':episodes[0]['id']}).encode()
 req=urllib.request.Request(BASE+'actions.php',data=body,headers={'User-Agent':'Mozilla/5.0 Yoma native public client','Content-Type':'application/json','X-CSRF-Token':state['csrf'],'Cookie':cookie})
 try:r=s.opener.open(req,timeout=35)
 except urllib.error.HTTPError as e:r=e
 raw=r.read();(f/'player.json').write_bytes(raw)
 d=json.loads(raw);print(json.dumps({'player_status':r.status,'player':d},ensure_ascii=False)[:5000])
