"""Read-only audit of YomaTV's public source. No credentials or old projects."""
from pathlib import Path
import http.cookiejar,json,re,subprocess,urllib.request,urllib.error,urllib.parse
ROOT=Path(__file__).resolve().parents[1]
BASE='https://hk-br035.gt.tc/seasonav1/'
class PublicSource:
    def __init__(self):
        self.jar=http.cookiejar.CookieJar();self.opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar));self.cookie=''
    def get(self,path):
        if not path or path.startswith(('http','/')) or '..' in path.split('/'):raise ValueError('Relative public app path required')
        for attempt in range(3):
            headers={'User-Agent':'Mozilla/5.0 Yoma native public client'}
            if self.cookie:headers['Cookie']='__test='+self.cookie
            req=urllib.request.Request(BASE+path,headers=headers)
            try:response=self.opener.open(req,timeout=35)
            except urllib.error.HTTPError as e:response=e
            body=response.read(12*1024*1024);status=response.status
            if b'slowAES.decrypt' not in body:return status,body,response.headers
            values=re.findall(r'toNumbers\("([a-fA-F0-9]+)"\)',body.decode(errors='replace'))
            if len(values)!=3:raise RuntimeError('Unknown first-party hosting handshake')
            php=r'C:/Users/Eduardo/.config/herd-lite/bin/php.exe'
            code='$v=json_decode(stream_get_contents(STDIN),true);echo bin2hex(openssl_decrypt(hex2bin($v[2]),"aes-128-cbc",hex2bin($v[0]),OPENSSL_RAW_DATA|OPENSSL_ZERO_PADDING,hex2bin($v[1])));'
            self.cookie=subprocess.run([php,'-r',code],input=json.dumps(values),capture_output=True,text=True,check=True).stdout.strip()
            if not re.fullmatch('[a-f0-9]{32}',self.cookie):raise RuntimeError('Invalid hosting cookie')
            if not re.search(r'(?:[?&])i=',path):path+=('&' if '?' in path else '?')+'i=1'
        raise RuntimeError('First-party hosting handshake failed')
if __name__=='__main__':
    source=PublicSource();folder=ROOT/'docs/yoma/source-audit'
    status,body,headers=source.get('index.php');(folder/'index.html').write_bytes(body)
    scripts=re.findall(r'<script[^>]+src=["\']([^"\']+)',body.decode(errors='replace'))
    results=[]
    for path in scripts:
        if path.startswith(('http','//')):continue
        status,body,_=source.get(path);name=Path(urllib.parse.urlsplit(path).path).name
        (folder/name).write_bytes(body);results.append({'path':path,'status':status,'bytes':len(body)})
    (folder/'scripts.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
