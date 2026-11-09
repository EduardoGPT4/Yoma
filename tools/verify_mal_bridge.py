from pathlib import Path
import importlib.util,json
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('yomatv_release',root.parent/'Expedition-6/YomaTVWeb/release.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
status,body,_=module.PublicClient().get('yoma-session.php')
assert status==401,(status,body[:120])
assert 'Conecta MAL'.encode() in body
health=module.check_health();assert health.get('ok')
result={'ok':True,'anonymous_bridge_status':status,'web_release':health.get('release'),'site_health':True}
(root/'docs/yoma/mal-bridge-live.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
