from pathlib import Path
import subprocess,xml.etree.ElementTree as ET,re,json,time,argparse
ROOT=Path(__file__).resolve().parents[1]
ADB=str(Path.home()/'AppData/Local/Android/Sdk/platform-tools/adb.exe')
PKG='app.yomashi.reader.qa'
def adb(*args):return subprocess.run([ADB,'-s','emulator-5554',*args],capture_output=True,check=True).stdout.decode(errors='replace')
def nodes():
    adb('shell','uiautomator','dump','/sdcard/yoma-window.xml')
    return ET.fromstring(adb('shell','cat','/sdcard/yoma-window.xml'))
def tap(text):
    for node in nodes().iter('node'):
        if any(text in value.split('\n') for value in (node.get('text',''),node.get('content-desc',''))):
            v=list(map(int,re.findall(r'\d+',node.get('bounds',''))));adb('shell','input','tap',str((v[0]+v[2])//2),str((v[1]+v[3])//2));return True
    return False
def perf(label):
    adb('shell','appops','set',PKG,'MANAGE_EXTERNAL_STORAGE','allow')
    adb('shell','pm','grant',PKG,'android.permission.POST_NOTIFICATIONS')
    adb('shell','am','start','-n',PKG+'/app.yomashi.reader.MainActivity')
    time.sleep(3)
    for _ in range(8):
        if not any(tap(name) for name in ['Saltar','Empezar','Comenzar','Entendido','Siguiente','Aceptar']):break
        time.sleep(.4)
    times=[]
    for _ in range(3):
        adb('shell','am','force-stop',PKG)
        out=adb('shell','am','start','-W','-n',PKG+'/app.yomashi.reader.MainActivity')
        times.append(int(re.search(r'TotalTime: (\d+)',out)[1]))
        time.sleep(2)
    # Capture exact visible state instead of claiming a catalog measurement on onboarding.
    visible=[(n.get('text') or n.get('content-desc')) for n in nodes().iter('node') if n.get('text') or n.get('content-desc')]
    result={'mode':'release','environment':'Android 35 emulator x86_64 / SwiftShader / 2048 MB','cold_activity_ms':times,'initial_visible':visible}
    for name in ['Siguiente','Siguiente','Siguiente','Comenzar','Entendido','Continuar','Aceptar']:
        if tap(name):time.sleep(.5)
    tap('Anime');time.sleep(12)
    adb('shell','dumpsys','gfxinfo',PKG,'reset')
    for _ in range(8):
        adb('shell','input','swipe','500','1800','500','550','400');time.sleep(.25)
    gfx=adb('shell','dumpsys','gfxinfo',PKG,'framestats');mem=adb('shell','dumpsys','meminfo',PKG)
    folder=ROOT/'docs/yoma';(folder/(label+'-gfx.txt')).write_text(gfx,encoding='utf-8');(folder/(label+'-mem.txt')).write_text(mem,encoding='utf-8')
    result['final_visible']=[(n.get('text') or n.get('content-desc')) for n in nodes().iter('node') if n.get('text') or n.get('content-desc')]
    for key,pattern in [('rendered_frames',r'Total frames rendered: (\d+)'),('janky',r'Janky frames: (\d+)'),('pss_kb',r'TOTAL PSS:\s*(\d+)')]:
        match=re.search(pattern,gfx if key!='pss_kb' else mem);result[key]=int(match[1]) if match else None
    (folder/(label+'.json')).write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('label');args=parser.parse_args();perf(args.label)
