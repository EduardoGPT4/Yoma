"""Deploy only the Yoma MAL extension. Credentials are read from stdin, never persisted."""
from pathlib import Path
import ftplib,ssl,io,json,sys,re,hashlib,argparse
ROOT=Path(__file__).resolve().parents[1]
class HostingFTP(ftplib.FTP_TLS):
    def ntransfercmd(self,cmd,rest=None):
        # Same endpoint as the authenticated control channel; ignore private PASV addresses.
        self.trust_server_pasv_ipv4_address=False
        return super().ntransfercmd(cmd,rest)
def read(ftp,path):
    data=io.BytesIO();ftp.retrbinary('RETR '+path,data.write);return data.getvalue()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--publish',action='store_true');args=parser.parse_args()
    print('Waiting for deployment credential on stdin (not saved).',flush=True)
    import getpass
    auth={'username':input('FTP user: '),'password':getpass.getpass('FTP password: ')}
    if auth.get('username')!='if0_43115975':raise RuntimeError('Unexpected hosting account')
    ftp=HostingFTP(context=ssl.create_default_context(),timeout=35)
    ftp.connect('ftpupload.net',21);ftp.login(auth['username'],auth['password']);auth.clear();ftp.prot_p();ftp.cwd('/htdocs/seasonav1')
    current=json.loads(read(ftp,'private/current.json'));active=current['release']
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{5,63}',active):raise RuntimeError('Invalid active release')
    old=read(ftp,'yomashi-api.php')
    folder=ROOT/'docs/yoma/deployment';folder.mkdir(parents=True,exist_ok=True)
    (folder/'yomashi-api.before.php').write_bytes(old)
    # Inspect source code only; never retrieve private configuration or tokens.
    adapter=read(ftp,'releases/'+active+'/private/mal-http.php');(folder/'mal-http-inspected.php').write_bytes(adapter)
    if not args.publish:
        print(json.dumps({'active_release':active,'entry_bytes':len(old),'entry_sha256':hashlib.sha256(old).hexdigest(),'read_only':True}));ftp.quit();return
    api=(ROOT/'server/yomashi-api.php').read_text(encoding='utf-8').replace("require __DIR__.'/private/app.php';", "require YOMA_WEB_BOOTSTRAP;")
    files={'yomashi-api.php':api.encode(),'private/yomashi-mal.php':(ROOT/'server/private/yomashi-mal.php').read_bytes(),'private/yoma-anime-mal.php':(ROOT/'server/private/yoma-anime-mal.php').read_bytes()}
    digest=hashlib.sha256(b''.join(files[k] for k in sorted(files))).hexdigest();release='yoma-native-mal-'+digest[:16]
    # Add an immutable extension, not a new active web release.
    base='releases/'+release
    for path in [base,base+'/private']:
        try:ftp.mkd(path)
        except ftplib.error_perm as e:
            if not str(e).startswith('550'):raise
    files['.htaccess']=b'Options -Indexes\n'
    files['private/.htaccess']=b'Require all denied\n'
    for name,data in files.items():
        path=base+'/'+name
        try:previous=read(ftp,path)
        except ftplib.error_perm:previous=None
        if previous is not None and previous!=data:raise RuntimeError('Immutable extension mismatch')
        if previous is None:ftp.storbinary('STOR '+path,io.BytesIO(data))
        if read(ftp,path)!=data:raise RuntimeError('Uploaded file differs')
    wrapper='''<?php
$root=__DIR__;
$current=json_decode((string)@file_get_contents($root.'/private/current.json'),true);
$id=$current['release']??'';
if(!is_string($id)||!preg_match('/^[a-z0-9][a-z0-9-]{5,63}$/D',$id)||!is_file($root.'/releases/'.$id.'/private/ready.json')){http_response_code(503);exit;}
define('SEASON_APP_ROOT',$root);define('SEASON_RELEASE_ID',$id);
define('YOMA_WEB_BOOTSTRAP',$root.'/releases/'.$id.'/private/app.php');
require $root.'/releases/RELEASE/yomashi-api.php';
'''.replace('RELEASE/yomashi',release+'/yomashi').encode()
    if read(ftp,'yomashi-api.php')!=old or json.loads(read(ftp,'private/current.json'))!=current:raise RuntimeError('Concurrent site change; deployment stopped')
    backup='private/yomashi-api.backup-'+hashlib.sha256(old).hexdigest()[:16]+'.php'
    ftp.storbinary('STOR '+backup,io.BytesIO(old))
    if read(ftp,backup)!=old:raise RuntimeError('Backup verification failed')
    pending='yomashi-api.pending-'+digest[:12]+'.php';ftp.storbinary('STOR '+pending,io.BytesIO(wrapper))
    if read(ftp,pending)!=wrapper:raise RuntimeError('Pending entry mismatch')
    ftp.rename(pending,'yomashi-api.php')
    if read(ftp,'yomashi-api.php')!=wrapper:raise RuntimeError('Entry publication mismatch')
    if json.loads(read(ftp,'private/current.json'))!=current:raise RuntimeError('Concurrent active release change')
    receipt={'extension':release,'active_web_release_unchanged':active,'backup':backup,'entry_sha256':hashlib.sha256(wrapper).hexdigest(),'sha256':{k:hashlib.sha256(v).hexdigest() for k,v in files.items()}}
    (folder/'receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8');print(json.dumps(receipt));ftp.quit()
if __name__=='__main__':
    try:main()
    except Exception as e:print('Deployment failed: '+type(e).__name__,flush=True);sys.exit(1)

