"""Add only the MAL bridge as an immutable extension to the existing YomaTV site.
Does not replace the active release, configuration, database, or source projects.
"""
from pathlib import Path
import argparse, hashlib, io, json, re, ssl, sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'Expedition-7'))
from deploy import InfinityFTP, credentials

def read(ftp,name,missing=False):
    out=io.BytesIO()
    try:ftp.retrbinary('RETR '+name,out.write)
    except Exception as e:
        if missing and str(e).startswith('550'):return None
        raise
    return out.getvalue()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--publish',action='store_true');args=parser.parse_args()
    config=credentials()
    if config['username']!='if0_43115975' or config['database']!='if0_43115975_anime':raise RuntimeError('Unexpected hosting account')
    source=(ROOT/'server/yoma-session.php').read_bytes();digest=hashlib.sha256(source).hexdigest();release='yoma-bridge-'+digest[:16]
    wrapper=('''<?php
// Immutable Yoma identity extension. Resolve YomaTV's current backend per request.
$base=__DIR__;
$current=json_decode((string)@file_get_contents($base.'/private/current.json'),true);
$id=$current['release']??'';
if(!is_string($id)||!preg_match('/^[a-z0-9][a-z0-9-]{5,63}$/D',$id)){http_response_code(503);exit('Publicación no disponible.');}
$bootstrap=$base.'/releases/'.$id.'/private/app.php';
if(!is_file($bootstrap)||!is_file($base.'/releases/'.$id.'/private/ready.json')){http_response_code(503);exit('Publicación incompleta.');}
define('SEASON_APP_ROOT',$base);define('SEASON_RELEASE_ID',$id);
define('YOMA_WEB_BOOTSTRAP',$bootstrap);
require $base.'/releases/RELEASE/yoma-session.php';
'''.replace('RELEASE/yoma','%s/yoma'%release)).encode()
    with InfinityFTP(context=ssl.create_default_context(),timeout=45) as ftp:
        ftp.connect('ftpupload.net',21);ftp.login(config['username'],config['password']);ftp.prot_p();ftp.cwd('/htdocs/seasonav1')
        current=json.loads(read(ftp,'private/current.json'));existing=read(ftp,'yoma-session.php',True)
        if not args.publish:
            print(json.dumps({'current_release':current['release'],'bridge_present':existing is not None,'prepared_extension':release,'sha256':digest}));return
        if existing is not None and existing!=wrapper:raise RuntimeError('A different bridge entry exists; refusing to overwrite it')
        folder='releases/'+release
        try:ftp.mkd(folder)
        except Exception as e:
            if not str(e).startswith('550'):raise
        files={'yoma-session.php':source,'.htaccess':b'Options -Indexes\n<FilesMatch "\\.php$">\nRequire all denied\n</FilesMatch>\n','ready.json':json.dumps({'sha256':digest}).encode()}
        for name,data in files.items():
            path=folder+'/'+name;previous=read(ftp,path,True)
            if previous is not None and previous!=data:raise RuntimeError('Immutable extension mismatch: '+name)
            if previous is None:ftp.storbinary('STOR '+path,io.BytesIO(data))
            if read(ftp,path)!=data:raise RuntimeError('Upload verification failed: '+name)
        if existing is None:
            temp='yoma-session.php.pending-'+digest[:12]
            ftp.storbinary('STOR '+temp,io.BytesIO(wrapper))
            if read(ftp,temp)!=wrapper:raise RuntimeError('Entry verification failed')
            ftp.rename(temp,'yoma-session.php')
        if read(ftp,'yoma-session.php')!=wrapper:raise RuntimeError('Published entry mismatch')
        if json.loads(read(ftp,'private/current.json'))!=current:raise RuntimeError('Active site changed concurrently')
        receipt={'ok':True,'extension':release,'current_release':current['release'],'sha256':digest,'active_release_unchanged':True}
        (ROOT/'docs/yoma/mal-bridge-deploy.json').write_text(json.dumps(receipt,indent=2))
        print(json.dumps(receipt))
if __name__=='__main__':main()
