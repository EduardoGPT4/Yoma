from audit_anime_source import *
source=PublicSource();folder=ROOT/'docs/yoma/source-audit'
summary=[]
for path,name in [('actions.php?action=state','state'),('actions.php?action=catalog&page=1','catalog'),('catalog-public.php','catalog-public'),('actions.php?action=home','home')]:
    status,body,headers=source.get(path);(folder/(name+'.json')).write_bytes(body)
    try:data=json.loads(body);summary.append({'name':name,'status':status,'keys':list(data) if isinstance(data,dict) else 'array'})
    except ValueError:summary.append({'name':name,'status':status,'json':False})
print(json.dumps(summary,indent=2))
