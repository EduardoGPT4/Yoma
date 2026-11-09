from pathlib import Path
import os,subprocess,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
adb=str(Path(os.environ['LOCALAPPDATA'])/'Android/Sdk/platform-tools/adb.exe')
pkg='app.yoma.integration.qa'
def run(*args,input=None):return subprocess.run([adb,'-s','emulator-5554',*args],input=input,capture_output=True,check=True).stdout
assert pkg.encode() in run('shell','pm','list','packages',pkg)
run('shell','am','force-stop',pkg)
path='shared_prefs/FlutterSharedPreferences.xml'
xml=run('shell','run-as',pkg,'cat',path)
tree=ET.fromstring(xml)
for key in ['onboarding_completed_v1','welcome_notice_seen_v1','manage_storage_explained_v1']:
    name='flutter.'+key
    for item in list(tree):
        if item.get('name')==name:tree.remove(item)
    ET.SubElement(tree,'boolean',{'name':name,'value':'true'})
run('shell','run-as',pkg,'tee',path,input=ET.tostring(tree,encoding='utf-8',xml_declaration=True))
run('shell','pm','grant',pkg,'android.permission.POST_NOTIFICATIONS')
run('shell','am','start','-n',pkg+'/app.yomashi.reader.MainActivity')
print('Started isolated Flutter smoke test; broad file access remains disabled.')
