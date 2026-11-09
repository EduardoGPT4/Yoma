"""Exercise the real bridge over HTTP with isolated SQLite and fake identities."""
from pathlib import Path
import json, os, shutil, socket, subprocess, tempfile, time, urllib.request, urllib.error
ROOT=Path(__file__).resolve().parents[2]
def _php():
    # YOMA_PHP > PHP de Herd en Windows > php del PATH (CI y Linux).
    if os.environ.get('YOMA_PHP'):return os.environ['YOMA_PHP']
    herd=Path(os.environ.get('USERPROFILE','~')).expanduser()/'.config/herd-lite/bin/php.exe'
    return str(herd) if herd.is_file() else (shutil.which('php') or 'php')
PHP=_php()
bootstrap=r'''<?php
session_start();
class WebError extends RuntimeException { public function __construct($m,public int $status=422){parent::__construct($m);} }
function db(){static $db;if($db)return $db;$db=new PDO('sqlite::memory:');$db->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE,PDO::FETCH_ASSOC);
$db->exec('CREATE TABLE sa1_yomashi_devices(token_hash TEXT,expires_at INTEGER,tokens TEXT,mal_user_id INTEGER);CREATE TABLE sa1_users(id INTEGER,auth_version INTEGER);CREATE TABLE sa1_mal_connections(user_id INTEGER,mal_user_id INTEGER,needs_auth INTEGER);');
$case=$_SERVER['HTTP_X_YOMA_TEST_CASE']??'';
$db->prepare('INSERT INTO sa1_yomashi_devices VALUES(?,?,?,?)')->execute([hash('sha256',str_repeat('a',64)),time()+($case==='expired'?-1:600),$case==='pending'?null:'encrypted-fixture',123]);
$db->exec('INSERT INTO sa1_users VALUES(10,7)');
if($case!=='missing')$db->exec('INSERT INTO sa1_mal_connections VALUES(10,123,'.($case==='needs_auth'?'1':'0').')');
if($case==='ambiguous')$db->exec('INSERT INTO sa1_users VALUES(11,0);INSERT INTO sa1_mal_connections VALUES(11,123,0)');
return $db;}
function sql($db,$q,$args=[]){$s=$db->prepare($q);$s->execute($args);return $s;}
function rate($db,$key,$limit,$window){}
'''
with tempfile.TemporaryDirectory(prefix='yoma-bridge-') as folder:
    folder=Path(folder);(folder/'bootstrap.php').write_text(bootstrap)
    (folder/'index.php').write_text("<?php define('YOMA_WEB_BOOTSTRAP',__DIR__.'/bootstrap.php');require "+repr(str(ROOT/'server/yoma-session.php').replace('\\','/'))+";")
    (folder/'who.php').write_text("<?php session_start();header('Content-Type: application/json');echo json_encode($_SESSION);")
    with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
    process=subprocess.Popen([str(PHP),'-S',f'127.0.0.1:{port}','-t',str(folder)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    base=f'http://127.0.0.1:{port}/'; checks=[]
    try:
        for _ in range(100):
            try:urllib.request.urlopen(base+'who.php',timeout=1);break
            except OSError:time.sleep(.1)
        def request(case='',token='a'*64,method='GET',query=''):
            headers={'X-Yoma-Test-Case':case}
            if token is not None:headers['X-YomaShi-Token']=token
            req=urllib.request.Request(base+query,headers=headers,method=method)
            try:return urllib.request.urlopen(req,timeout=5)
            except urllib.error.HTTPError as e:return e
        for case,expected in [('expired',401),('pending',401),('missing',409),('needs_auth',409),('ambiguous',409)]:
            result=request(case);assert result.code==expected,(case,result.code);checks.append(case)
        assert request(token=None).code==401;checks.append('missing_header')
        assert request(token='invalid').code==401;checks.append('invalid_token')
        assert request(token=None,query='?token='+'a'*64).code==401;checks.append('no_query_credentials')
        assert request(method='POST').code==405;checks.append('method_guard')
        result=request();body=result.read().decode();assert result.code==200
        assert 'a'*64 not in body and 'a'*64 not in str(result.headers)
        assert result.headers['Cache-Control']=='no-store'
        assert "default-src 'none'" in result.headers['Content-Security-Policy']
        assert 'nonce-yoma-session' not in result.headers['Content-Security-Policy']
        cookie=result.headers.get_all('Set-Cookie')[-1].split(';')[0]
        state=json.load(urllib.request.urlopen(urllib.request.Request(base+'who.php',headers={'Cookie':cookie})))
        assert state['user_id']==10 and state['auth_version']==7 and len(state['csrf'])==48
        assert 'device_token' not in state and len(state['yoma_device'])==64
        checks+=['same_identity_session','no_credential_echo','no_store_csp','session_rotation']
        print(json.dumps({'ok':True,'checks':checks},indent=2))
    finally:process.terminate();process.wait(timeout=5)
