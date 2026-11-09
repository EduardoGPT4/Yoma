"""Measure process-cold Release starts of the task-owned physical integration package."""
from pathlib import Path
import argparse,subprocess,json,re,statistics
ROOT=Path(__file__).resolve().parents[1];SDK=Path.home()/'AppData/Local/Android/Sdk';PKG='app.yoma.integration.qa'
def main():
    p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--apk',type=Path,required=True);args=p.parse_args()
    receipt=json.loads((ROOT/'docs/yoma/physical/owned-package.json').read_text())
    assert receipt['device']==args.device and receipt['package']==PKG and receipt['owned_by_this_task']
    def adb(*parts):return subprocess.run([str(SDK/'platform-tools/adb.exe'),'-s',args.device,*parts],capture_output=True,check=True,timeout=120).stdout.decode(errors='replace')
    badging=subprocess.run([str(SDK/'build-tools/36.0.0/aapt.exe'),'dump','badging',str(args.apk)],capture_output=True,text=True,check=True).stdout
    assert badging.startswith("package: name='"+PKG+"'")
    print(adb('install','-r',str(args.apk)).strip(),flush=True)
    times=[];raw=[]
    for _ in range(5):
        adb('shell','am','force-stop',PKG)
        launch=adb('shell','am','start','-W','-n',PKG+'/app.yomashi.reader.MainActivity');raw.append(launch)
        match=re.search(r'TotalTime: (\d+)',launch)
        if not match:raise RuntimeError('No Activity timing returned')
        times.append(int(match[1]))
        # Let the selector and its initialization settle; this is not app data reset.
        import time;time.sleep(2)
    folder=ROOT/'docs/yoma/physical'
    memory=adb('shell','dumpsys','meminfo',PKG);(folder/'phone-release-memory.txt').write_text(memory,encoding='utf-8')
    (folder/'phone-release-launches.txt').write_text('\n'.join(raw),encoding='utf-8')
    result={'mode':'release','package':PKG,'cold_activity_ms':times,'median_activity_ms':statistics.median(times),'mean_activity_ms':statistics.mean(times),'selector_pss_kib':int(re.search(r'TOTAL PSS:\s*(\d+)',memory)[1])}
    (folder/'phone-release.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result),flush=True)
    adb('shell','am','force-stop',PKG)
if __name__=='__main__':main()
