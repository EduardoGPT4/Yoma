"""HTTP contract tests: real PHP endpoints, OAuth/session/CSRF and a local MAL fixture.

No credentials are read and no real MAL account is modified.
"""
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.cookiejar,json,os,re,shutil,socket,sqlite3,subprocess,tempfile,threading,time,unittest,urllib.error,urllib.parse,urllib.request

ROOT=Path(__file__).resolve().parents[2]
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args):return None

class Fixture(BaseHTTPRequestHandler):
    records=[];patches=[];chapters=0;status='plan_to_read';token_calls=0
    profile={'id':7,'name':'MangaTester','picture':'https://cdn.myanimelist.net/images/userimages/7.jpg'};profile_status=200;token_status=200;token_error='server_error'
    library_payload=None;library_status=200
    def log_message(self,*args):pass
    def respond(self,data,status=200):
        raw=json.dumps(data).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
    def do_GET(self):
        type(self).records.append(('GET',self.path))
        if self.path=='/profile':return self.respond(self.profile,self.profile_status)
        if self.path.startswith('/manga-list?'):
            return self.respond(self.library_payload if self.library_payload is not None else {'data':[], 'paging':{}},self.library_status)
        node={'id':2,'title':'Berserk fixture','num_chapters':100,'status':'finished','main_picture':{},'my_list_status':{'status':self.status,'num_chapters_read':self.chapters}}
        if self.path.startswith('/manga-search?'):return self.respond({'data':[{'node':node}]})
        if self.path.startswith('/manga:2?'):return self.respond(node)
        return self.respond({'error':'not found'},404)
    def do_POST(self):
        values=urllib.parse.parse_qs(self.rfile.read(int(self.headers.get('Content-Length',0))).decode());type(self).records.append(('POST',self.path))
        if self.path=='/token':
            if self.token_status!=200:return self.respond({'error':self.token_error},self.token_status)
            if values.get('grant_type')==['refresh_token'] and values.get('refresh_token')!=['fixture-refresh-token-'+str(self.token_calls)]:
                return self.respond({'error':'invalid_grant'},400)
            type(self).token_calls+=1
            assert 'client_secret' in values
            return self.respond({'access_token':'fixture-access-token','refresh_token':'fixture-refresh-token-'+str(self.token_calls),'token_type':'bearer','expires_in':30})
        return self.respond({},404)
    def do_PATCH(self):
        values=urllib.parse.parse_qs(self.rfile.read(int(self.headers.get('Content-Length',0))).decode());type(self).records.append(('PATCH',self.path))
        if self.path!='/manga-list-status:2':return self.respond({},404)
        assert set(values)=={'status','num_chapters_read'}
        type(self).patches.append(values);type(self).chapters=int(values['num_chapters_read'][0]);type(self).status=values['status'][0]
        return self.respond({'num_chapters_read':self.chapters,'status':self.status,'score':8,'num_volumes_read':3})

class TestMangaBridge(unittest.TestCase):
    def setUp(self):
        Fixture.profile={'id':7,'name':'MangaTester','picture':'https://cdn.myanimelist.net/images/userimages/7.jpg'}
        Fixture.profile_status=200
        Fixture.token_status=200;Fixture.token_error='server_error'
        Fixture.library_payload=None;Fixture.library_status=200
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='yomashi-mal-');cls.folder=Path(cls.temp.name)
        (cls.folder/'private').mkdir()
        shutil.copy(ROOT/'test/backend/host_bootstrap.php',cls.folder/'private/app.php')
        for source in (ROOT/'server').rglob('*.php'):
            target=cls.folder/source.relative_to(ROOT/'server');target.parent.mkdir(exist_ok=True,parents=True);shutil.copy(source,target)
        (cls.folder/'mal-callback.php').write_text("<?php define('SEASON_BOOTSTRAPPED',true);require __DIR__.'/private/app.php';require __DIR__.'/private/yomashi-mal.php';ys_callback_page();",encoding='utf-8')
        cls.mock=ThreadingHTTPServer(('127.0.0.1',0),Fixture);threading.Thread(target=cls.mock.serve_forever,daemon=True).start()
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        env={**os.environ,'YS_TEST_DB':str(cls.folder/'fixture.sqlite'),'YS_TEST_MOCK':f'http://127.0.0.1:{cls.mock.server_port}'}
        cls.log=open(cls.folder/'php.log','wb');cls.php=subprocess.Popen(['php','-S',f'127.0.0.1:{port}','-t',str(cls.folder)],env=env,stdout=cls.log,stderr=cls.log)
        cls.base=f'http://127.0.0.1:{port}/'
        cls.opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),NoRedirect())
        for _ in range(100):
            try:urllib.request.urlopen(cls.base,timeout=.3);break
            except urllib.error.HTTPError as e:e.close();break
            except OSError:time.sleep(.05)
        cls.token=None
    @classmethod
    def tearDownClass(cls):
        cls.php.terminate();cls.php.wait(timeout=10);cls.mock.shutdown();cls.mock.server_close();cls.log.close()
        cls.temp.cleanup()
    def request(self,path='yomashi-api.php',payload=None,token=None,form=False,token_header=False,extra_headers=None):
        data=None;headers={}
        if payload is not None:
            data=(urllib.parse.urlencode(payload) if form else json.dumps(payload)).encode();headers['Content-Type']='application/x-www-form-urlencoded' if form else 'application/json'
        if token:headers['X-YomaShi-Token' if token_header else 'Authorization']=token if token_header else 'Bearer '+token
        if extra_headers:headers.update(extra_headers)
        request=urllib.request.Request(self.base+path,data=data,headers=headers)
        try:r=self.opener.open(request,timeout=10)
        except urllib.error.HTTPError as e:r=e
        raw=r.read()
        return r.status,raw,r.headers
    def connect_fixture(self):
        status,raw,_=self.request(payload={'action':'start'});self.assertEqual(status,200,raw)
        pair=json.loads(raw)
        status,raw,_=self.request('yomashi-connect.php?device='+pair['device_id']);self.assertEqual(status,200,raw)
        csrf=re.search(rb'name="csrf" value="([a-f0-9]+)"',raw)[1].decode()
        status,raw,headers=self.request('yomashi-connect.php',{'device':pair['device_id'],'csrf':csrf},form=True);self.assertEqual(status,303,raw)
        state=urllib.parse.parse_qs(urllib.parse.urlparse(headers['Location']).query)['state'][0]
        status,raw,_=self.request('mal-callback.php?'+urllib.parse.urlencode({'state':state,'code':'fixture'}));self.assertEqual(status,200,raw)
        return pair
    def age_profile_cache(self,device,legacy=False):
        # Only the encrypted localhost fixture is touched, never production data.
        program=r'''define('SEASON_BOOTSTRAPPED',true);require $argv[1].'/private/app.php';require $argv[1].'/private/yomashi-mal.php';$db=db();$row=sql($db,'SELECT * FROM sa1_yomashi_devices WHERE id=?',[$argv[2]])->fetch();$tokens=json_decode(ys_crypt($row['tokens'],$row['id'],true),true);$tokens['profile_next_refresh']=0;if($argv[3]==='legacy')unset($tokens['profile']);sql($db,'UPDATE sa1_yomashi_devices SET tokens=? WHERE id=?',[ys_crypt(json_encode($tokens,JSON_THROW_ON_ERROR),$row['id']),$row['id']]);'''
        env={**os.environ,'YS_TEST_DB':str(self.folder/'fixture.sqlite')}
        result=subprocess.run(['php','-r',program,str(self.folder),device,'legacy' if legacy else 'age'],env=env,capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr)
    def encrypted_profile_cache(self,device):
        program=r'''define('SEASON_BOOTSTRAPPED',true);require $argv[1].'/private/app.php';require $argv[1].'/private/yomashi-mal.php';$row=sql(db(),'SELECT * FROM sa1_yomashi_devices WHERE id=?',[$argv[2]])->fetch();$tokens=json_decode(ys_crypt($row['tokens'],$row['id'],true),true);echo json_encode(['profile'=>$tokens['profile']??null,'profile_next_refresh'=>$tokens['profile_next_refresh']??0,'expires_at'=>$tokens['expires_at']??0]);'''
        result=subprocess.run(['php','-r',program,str(self.folder),device],env={**os.environ,'YS_TEST_DB':str(self.folder/'fixture.sqlite')},capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr);return json.loads(result.stdout)
    def profile_status(self,token):
        status,raw,_=self.request(payload={'action':'status'},token=token)
        self.assertEqual(status,200,raw)
        self.assertNotIn(b'fixture-access-token',raw);self.assertNotIn(b'fixture-refresh-token',raw)
        result=json.loads(raw);self.assertTrue(result['connected']);return result['profile']
    def test_avatar_status_upgrades_legacy_sessions_and_caches_refreshes(self):
        pair=self.connect_fixture();token=pair['device_token'];device=pair['device_id']
        def requests():return len([path for method,path in Fixture.records if path=='/profile'])
        before=requests()
        self.assertEqual(self.profile_status(token)['picture'],Fixture.profile['picture'])
        self.assertEqual(requests(),before) # Initial authorization cached the image.
        self.age_profile_cache(device,legacy=True)
        self.assertEqual(self.profile_status(token)['picture'],Fixture.profile['picture'])
        self.assertEqual(requests(),before+1) # No reconnect needed for existing sessions.
        old=Fixture.profile['picture'];Fixture.profile['picture']='https://cdn.myanimelist.net/s/common/userimages/7-new.jpg'
        self.assertEqual(self.profile_status(token)['picture'],old)
        self.assertEqual(requests(),before+1)
        self.age_profile_cache(device)
        self.assertEqual(self.profile_status(token)['picture'],Fixture.profile['picture'])
        self.assertEqual(requests(),before+2)
        Fixture.profile_status=503;self.age_profile_cache(device)
        refreshes=Fixture.token_calls
        self.assertEqual(self.profile_status(token)['picture'],Fixture.profile['picture'])
        self.assertGreater(Fixture.token_calls,refreshes) # Expired access token rotated before the profile failure.
        cached=self.encrypted_profile_cache(device)
        self.assertEqual(cached['profile']['picture'],Fixture.profile['picture'])
        self.assertGreater(cached['profile_next_refresh'],int(time.time()))
        self.assertLess(cached['profile_next_refresh'],int(time.time())+620)
        after_failure=requests()
        self.assertEqual(self.profile_status(token)['picture'],Fixture.profile['picture'])
        self.assertEqual(requests(),after_failure) # Provider errors back off, retaining image.
        Fixture.profile_status=200
        for unsafe in ['https://untrusted.example/avatar.jpg','http://cdn.myanimelist.net/avatar.jpg',
                       'https://cdn.myanimelist.net.evil.example/avatar.jpg','https://name:pass@cdn.myanimelist.net/avatar.jpg',
                       'https://cdn.myanimelist.net:444/avatar.jpg','https://cdn.myanimelist.net/avatar.jpg#fragment',
                       'https://cdn.myanimelist.net/avatar.jpg\r\n']:
            Fixture.profile['picture']=unsafe;self.age_profile_cache(device)
            self.assertEqual(self.profile_status(token)['picture'],'',unsafe)
        Fixture.profile['picture']='';self.age_profile_cache(device)
        self.assertEqual(self.profile_status(token)['picture'],'') # Accounts may have no avatar.
        Fixture.profile_status=401;self.age_profile_cache(device)
        self.assertEqual(self.request(payload={'action':'status'},token=token)[0],401)
        self.assertEqual(self.request(payload={'action':'status'},token=token)[0],401)
    def test_avatar_account_mismatch_revokes_device_before_future_writes(self):
        pair=self.connect_fixture();token=pair['device_token'];device=pair['device_id']
        Fixture.profile={'id':8,'name':'OtherOwner','picture':'https://cdn.myanimelist.net/images/userimages/8.jpg'}
        self.age_profile_cache(device)
        status,raw,_=self.request(payload={'action':'status'},token=token)
        self.assertEqual(status,401,raw);self.assertNotIn(b'OtherOwner',raw)
        conn=sqlite3.connect(self.folder/'fixture.sqlite')
        self.assertEqual(conn.execute('SELECT COUNT(*) FROM sa1_yomashi_devices WHERE id=?',(device,)).fetchone()[0],0);conn.close()
        before=len(Fixture.patches)
        self.assertEqual(self.request(payload={'action':'update','id':2,'chapters_read':1,'status':'reading'},token=token)[0],401)
        self.assertEqual(len(Fixture.patches),before)
    def test_avatar_refresh_outage_keeps_cache_and_invalid_grant_revokes(self):
        pair=self.connect_fixture();token=pair['device_token'];device=pair['device_id']
        self.age_profile_cache(device);before=Fixture.token_calls
        Fixture.token_status=503
        self.assertEqual(self.profile_status(token)['picture'],Fixture.profile['picture'])
        self.assertEqual(Fixture.token_calls,before)
        self.assertEqual(self.encrypted_profile_cache(device)['profile']['picture'],Fixture.profile['picture'])
        # Repeated app resumes cannot hammer the unavailable token endpoint.
        before=len(Fixture.records);self.profile_status(token);self.assertEqual(len(Fixture.records),before)
        Fixture.token_status=200;self.age_profile_cache(device)
        self.assertEqual(self.profile_status(token)['picture'],Fixture.profile['picture'])
        self.assertGreater(Fixture.token_calls,0)
        Fixture.token_status=400;Fixture.token_error='invalid_grant';self.age_profile_cache(device)
        self.assertEqual(self.request(payload={'action':'status'},token=token)[0],401)
    @unittest.skipUnless(os.environ.get('YOMASHI_BROWSER_TESTS')=='1','Opt-in Chromium UI regression')
    def test_browser_authorization_navigation(self):
        env={**os.environ,'YOMASHI_TEST_BASE':self.base}
        result=subprocess.run(['node',str(ROOT/'test/backend/test_authorize_browser.cjs')],env=env,capture_output=True,text=True,timeout=90)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        data=json.loads(result.stdout.strip().splitlines()[-1])
        self.assertTrue(data['destination_requested'])
        self.assertEqual(data['form_post_status'],303)
    def test_manga_library_filters_private_statuses_and_paginates_without_following_urls(self):
        pair=self.connect_fixture();token=pair['device_token']
        node={'id':1,'title':'Obra principal','num_chapters':20,'status':'finished',
              'main_picture':{'medium':'https://cdn.myanimelist.net/images/manga/1/1.jpg'},
              'alternative_titles':{'en':'English Title','ja':'別題','synonyms':['Alias','English Title']},
              'my_list_status':{'status':'completed','num_chapters_read':20}}
        before=len(Fixture.patches)
        for state in ['reading','plan_to_read']:
            Fixture.library_payload={'data':[
                {'node':node,'list_status':{'status':state,'num_chapters_read':3}},
                {'node':{**node,'id':2},'list_status':{'status':'completed','num_chapters_read':20}},
            ],'paging':{'next':'https://untrusted.example/do-not-follow'}}
            code,raw,_=self.request(payload={'action':'library','status':state,'limit':2,'owner_id':7},token=token)
            self.assertEqual(code,200,raw);page=json.loads(raw)
            self.assertEqual(page['next_offset'],2);self.assertEqual(len(page['items']),1)
            manga=page['items'][0];self.assertEqual(manga['status'],state);self.assertEqual(manga['chapters_read'],3)
            self.assertEqual(manga['alternative_titles'],['English Title','別題','Alias'])
            self.assertNotIn(b'fixture-access-token',raw);self.assertNotIn(b'fixture-refresh-token',raw)
            path=next(path for method,path in reversed(Fixture.records) if path.startswith('/manga-list?'))
            query=urllib.parse.parse_qs(urllib.parse.urlparse(path).query)
            self.assertEqual(query['status'],[state]);self.assertEqual(query['sort'],['manga_title'])
            self.assertEqual(query['limit'],['2']);self.assertIn('list_status',query['fields'][0])
            Fixture.library_payload={'data':[{'node':{**node,'id':3},'list_status':{'status':state,'num_chapters_read':0}}],'paging':{}}
            code,raw,_=self.request(payload={'action':'library','status':state,'offset':2,'owner_id':7},token=token)
            self.assertEqual(code,200,raw);self.assertIsNone(json.loads(raw)['next_offset'])
        self.assertEqual(len(Fixture.patches),before)

    def test_manga_library_rejects_invalid_filters_and_wrong_owner_before_refresh(self):
        pair=self.connect_fixture();token=pair['device_token'];before=Fixture.token_calls
        for invalid in [{'status':'completed'},{'status':'watching'},{'status':'all'},{'offset':-1},{'offset':'1'},{'limit':0},{'limit':101}]:
            code,raw,_=self.request(payload={'action':'library','status':'reading',**invalid},token=token)
            self.assertEqual(code,422,raw)
        code,raw,_=self.request(payload={'action':'library','status':'reading','owner_id':8},token=token)
        self.assertEqual(code,409,raw);self.assertEqual(Fixture.token_calls,before)
        self.assertEqual(self.request(payload={'action':'library','status':'reading'})[0],401)
        code,raw,_=self.request(payload={'action':'start'});pending=json.loads(raw)
        self.assertEqual(self.request(payload={'action':'library','status':'reading'},token=pending['device_token'])[0],409)

    def test_manga_library_rejects_incomplete_pages_and_preserves_provider_failures(self):
        pair=self.connect_fixture();token=pair['device_token']
        for malformed in [{'data':None},{'data':[],'paging':{'next':'https://api.myanimelist.net/next'}},{'data':[{'node':{'id':1}}]}]:
            Fixture.library_payload=malformed
            code,raw,_=self.request(payload={'action':'library','status':'reading'},token=token)
            self.assertEqual(code,502,raw)
        Fixture.library_status=429
        self.assertEqual(self.request(payload={'action':'library','status':'reading'},token=token)[0],429)

    def test_complete_manga_authorization_and_updates(self):
        code,raw,_=self.request(payload={'action':'start'});self.assertEqual(code,200,raw)
        pair=json.loads(raw);token=pair['device_token'];device=pair['device_id']
        self.assertNotIn('client_secret',raw.decode());self.assertNotIn('access_token',raw.decode())
        self.assertEqual(self.request(payload={'action':'status'},token=token,token_header=True)[0],200)
        self.assertEqual(self.request(payload={'action':'status'},token=token,extra_headers={'X-YomaShi-Token':'b'*64})[0],401)
        self.assertEqual(self.request(payload={'action':'status'})[0],401)
        self.assertEqual(self.request()[0],405)
        status,raw,headers=self.request('yomashi-connect.php?device='+device);self.assertEqual(status,200)
        policies=headers.get_all('Content-Security-Policy')
        self.assertEqual(len(policies),1) # A second header would retain the old restriction.
        self.assertIn("form-action 'self' https://myanimelist.net",policies[0])
        self.assertIn("frame-ancestors 'none'",policies[0])
        self.assertIn("script-src 'self'",policies[0])
        self.assertNotIn('unsafe-inline',policies[0])
        csrf=re.search(rb'name="csrf" value="([a-f0-9]+)"',raw)[1].decode()
        self.assertEqual(self.request('yomashi-connect.php',{'device':device,'csrf':'bad'},form=True)[0],403)
        status,raw,headers=self.request('yomashi-connect.php',{'device':device,'csrf':csrf},form=True);self.assertEqual(status,303,raw)
        params=urllib.parse.parse_qs(urllib.parse.urlparse(headers['Location']).query)
        self.assertEqual(params['code_challenge_method'],['plain']);self.assertNotIn('client_secret',headers['Location'])
        state=params['state'][0]
        self.assertEqual(self.request('mal-callback.php?state=ys_wrong&code=fixture')[0],400)
        status,raw,_=self.request('mal-callback.php?'+urllib.parse.urlencode({'state':state,'code':'fixture'}));self.assertEqual(status,200,raw)
        self.assertNotIn(b'fixture-access-token',raw)
        status,raw,_=self.request(payload={'action':'status'},token=token);self.assertEqual(status,200,raw);self.assertEqual(json.loads(raw)['profile']['id'],7)
        conn=sqlite3.connect(self.folder/'fixture.sqlite');cipher=conn.execute('SELECT tokens FROM sa1_yomashi_devices WHERE id=?',(device,)).fetchone()[0];conn.close()
        self.assertNotIn('fixture-access-token',cipher);self.assertNotIn('fixture-refresh-token',cipher)
        status,raw,_=self.request(payload={'action':'search','query':'Berserk'},token=token);self.assertEqual(status,200,raw);self.assertEqual(json.loads(raw)['items'][0]['id'],2)
        self.assertGreaterEqual(Fixture.token_calls,2) # Expires-in=30 exercises refresh.
        # A refresh followed by a failed lookup must retain the rotated token.
        self.assertEqual(self.request(payload={'action':'detail','id':404},token=token)[0],404)
        self.assertEqual(self.request(payload={'action':'search','query':'Berserk'},token=token)[0],200)
        for state_to_preserve in ['on_hold','dropped']:
            Fixture.status=state_to_preserve
            status,raw,_=self.request(payload={'action':'update','id':2,'chapters_read':100,'status':'reading','automatic':True},token=token)
            self.assertEqual(status,200,raw);self.assertEqual(json.loads(raw)['manga']['status'],state_to_preserve)
        Fixture.status='plan_to_read';Fixture.chapters=0
        status,raw,_=self.request(payload={'action':'update','id':2,'chapters_read':30,'status':'reading','owner_id':7},token=token);self.assertEqual(status,200,raw)
        status,raw,_=self.request(payload={'action':'update','id':2,'chapters_read':10,'status':'reading','automatic':True,'owner_id':7},token=token);self.assertEqual(status,200,raw);self.assertEqual(json.loads(raw)['manga']['chapters_read'],30)
        self.assertEqual(self.request(payload={'action':'update','id':2,'chapters_read':31,'status':'reading','owner_id':8},token=token)[0],409)
        status,raw,_=self.request(payload={'action':'update','id':2,'chapters_read':100,'status':'reading','automatic':True},token=token);self.assertEqual(status,200,raw);self.assertEqual(json.loads(raw)['manga']['status'],'completed')
        before=len(Fixture.patches)
        for changes in [{'chapters_read':101},{'chapters_read':-1},{'status':'watching'},{'id':0}]:
            self.assertEqual(self.request(payload={'action':'update','id':2,'chapters_read':40,'status':'reading',**changes},token=token)[0],422)
        self.assertEqual(len(Fixture.patches),before)
        self.assertTrue(all('anime' not in path for method,path in Fixture.records))
        self.assertEqual(self.request(payload={'action':'disconnect'},token=token)[0],200)
        self.assertEqual(self.request(payload={'action':'status'},token=token)[0],401)
        self.assertEqual(self.request('mal-callback.php?'+urllib.parse.urlencode({'state':state,'code':'fixture'}))[0],400)
        status,raw,_=self.request(payload={'action':'start'});pair=json.loads(raw)
        conn=sqlite3.connect(self.folder/'fixture.sqlite');conn.execute('UPDATE sa1_yomashi_devices SET expires_at=0 WHERE id=?',(pair['device_id'],));conn.commit();conn.close()
        self.assertEqual(self.request(payload={'action':'status'},token=pair['device_token'])[0],401)

if __name__=='__main__':unittest.main(verbosity=2)
