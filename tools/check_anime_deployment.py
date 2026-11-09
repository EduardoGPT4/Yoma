import sys,json,urllib.request,urllib.error
from pathlib import Path
sys.path.insert(0,'tools')
from audit_anime_source import PublicSource,BASE
source=PublicSource();results={}
for name,path in [('web_state','actions.php?action=state'),('catalog','actions.php?action=catalog&page=1')]:
    status,raw,_=source.get(path);body=json.loads(raw);results[name]={'status':status,'ok':body.get('ok'),'catalog_count':body.get('catalog',{}).get('total')}
status,raw,_=source.get('yomashi-api.php');print('API warmup:',status,raw[:100].decode(errors='replace'))
for action,payload in [('anime_capabilities',{}),('anime_update',{'id':1,'owner_id':7,'expected_episodes':0,'episodes_watched':-1})]:
    req=urllib.request.Request(BASE+'yomashi-api.php?i=1',data=json.dumps({'action':action,**payload}).encode(),headers={'Content-Type':'application/json','Cookie':'__test='+source.cookie,'X-YomaShi-Token':'a'*64,'User-Agent':'Mozilla/5.0 Yoma native public client'})
    try:r=source.opener.open(req,timeout=30)
    except urllib.error.HTTPError as e:r=e
    raw=r.read();results[action]={'status':r.status,'body':json.loads(raw) if raw.startswith(b'{') else raw[:300].decode(errors='replace')}
Path('docs/yoma/deployment/http-verification.json').write_text(json.dumps(results,indent=2,ensure_ascii=False),encoding='utf-8');print(json.dumps(results,ensure_ascii=False))
assert results['catalog']['status']==200 and results['anime_capabilities']['status']==401 and results['anime_update']['status']==422


