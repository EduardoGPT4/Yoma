"""Physical-device runner: only installs the verified, task-owned integration package.
The driver attaches to an existing VM; Flutter is never allowed to uninstall a personal app.
"""
from pathlib import Path
import argparse,subprocess,json,time,os,re,urllib.parse
ROOT=Path(__file__).resolve().parents[1]
SDK=Path.home()/'AppData/Local/Android/Sdk'
ADB=str(SDK/'platform-tools/adb.exe');PKG='app.yoma.integration.qa'
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--device',required=True);parser.add_argument('--apk',type=Path,required=True);parser.add_argument('--label',default='phone-profile');args=parser.parse_args()
    assert re.fullmatch('[a-z0-9-]+',args.label)
    def adb(*parts,timeout=40):return subprocess.run([ADB,'-s',args.device,*parts],capture_output=True,check=True,timeout=timeout).stdout.decode(errors='replace')
    badging=subprocess.run([str(SDK/'build-tools/36.0.0/aapt.exe'),'dump','badging',str(args.apk)],capture_output=True,text=True,check=True).stdout
    if not badging.startswith("package: name='"+PKG+"'"):raise RuntimeError('Refusing an APK outside the isolated integration package')
    folder=ROOT/'docs/yoma/physical';folder.mkdir(exist_ok=True)
    receipt=folder/'owned-package.json'
    installed=adb('shell','pm','list','packages',PKG).strip()
    if installed:
        owner=json.loads(receipt.read_text()) if receipt.is_file() else {}
        if owner.get('device')!=args.device or owner.get('package')!=PKG or not owner.get('owned_by_this_task'):raise RuntimeError('Integration package was not created by this task on this device; refusing replacement')
    result=adb('install','-r',str(args.apk),timeout=120)
    if 'Success' not in result:raise RuntimeError('Install did not succeed')
    receipt.write_text(json.dumps({'device':args.device,'package':PKG,'owned_by_this_task':True}),encoding='utf-8')
    print('Installed isolated integration package; personal packages untouched.',flush=True)
    try:adb('shell','pm','grant',PKG,'android.permission.POST_NOTIFICATIONS')
    except subprocess.CalledProcessError:print('Runtime notification permission will use the normal Android dialog.',flush=True)
    adb('shell','am','force-stop',PKG)
    adb('shell','am','start','-W','-n',PKG+'/app.yomashi.reader.MainActivity')
    vm=None;pid=None
    for _ in range(60):
        pid=adb('shell','pidof',PKG).strip().split()[0]
        logs=adb('logcat','-d','--pid='+pid,'-s','flutter:I')
        matches=re.findall(r'The Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)',logs)
        if matches:vm=urllib.parse.urlsplit(matches[-1]);break
        time.sleep(.5)
    if vm is None:raise RuntimeError('No VM service from the isolated app')
    port=adb('forward','tcp:0','tcp:'+str(vm.port)).strip()
    env={**os.environ,'VM_SERVICE_URL':'http://127.0.0.1:'+port+vm.path,'YOMASHI_REPORT_NAME':args.label}
    try:
        with (folder/(args.label+'-driver.txt')).open('w',encoding='utf-8') as output:
            driver=subprocess.run(['C:/flutter/bin/dart.bat','run','test_driver/integration_test.dart'],cwd=ROOT,env=env,stdout=output,stderr=subprocess.STDOUT,timeout=600)
        (folder/(args.label+'-logcat.txt')).write_text(adb('logcat','-d','--pid='+pid,'-s','flutter:I'),encoding='utf-8')
        (folder/(args.label+'-memory.txt')).write_text(adb('shell','dumpsys','meminfo',PKG),encoding='utf-8')
        (folder/(args.label+'-battery-after.txt')).write_text(adb('shell','dumpsys','battery'),encoding='utf-8')
        print('Physical integration driver exit:',driver.returncode,flush=True)
        if driver.returncode:raise RuntimeError('Physical tests failed; see task-only logs')
    finally:
        adb('forward','--remove','tcp:'+port)
        adb('shell','am','force-stop',PKG)
if __name__=='__main__':main()
