from test_myanimelist import TestMangaBridge, Fixture
import json,unittest,urllib.parse
original_get=Fixture.do_GET
original_patch=Fixture.do_PATCH

def anime_get(self):
    if self.path.startswith('/anime-list?'):
        return self.respond({'data':[{'node':{'id':1,'title':'Anime test','num_episodes':12},'list_status':{'status':self.anime_status,'num_episodes_watched':self.episodes}}], 'paging':{}})
    if self.path.startswith('/anime:1?'):
        return self.respond({'id':1,'title':'Anime test','num_episodes':12,'my_list_status':{'status':self.anime_status,'num_episodes_watched':self.episodes}})
    return original_get(self)
def anime_patch(self):
    if self.path!='/anime-list-status:1':return original_patch(self)
    values=urllib.parse.parse_qs(self.rfile.read(int(self.headers.get('Content-Length',0))).decode())
    assert set(values)=={'status','num_watched_episodes'}
    type(self).episodes=int(values['num_watched_episodes'][0]);type(self).anime_status=values['status'][0];type(self).anime_writes+=1
    return self.respond({'status':self.anime_status,'num_episodes_watched':self.episodes})
Fixture.do_GET=anime_get;Fixture.do_PATCH=anime_patch
class TestAnimeBridge(unittest.TestCase):
    setUpClass=classmethod(TestMangaBridge.setUpClass.__func__)
    tearDownClass=classmethod(TestMangaBridge.tearDownClass.__func__)
    request=TestMangaBridge.request
    connect_fixture=TestMangaBridge.connect_fixture
    def setUp(self):
        Fixture.episodes=2;Fixture.anime_status='watching';Fixture.anime_writes=0
        Fixture.profile_status=200;Fixture.token_status=200
        self.pair=self.connect_fixture();self.token=self.pair['device_token']
    def api(self,action,**kw):
        status,raw,_=self.request(payload={'action':action,**kw},token=self.token);return status,json.loads(raw)
    def test_list_and_shared_revoke(self):
        self.assertEqual(self.api('anime_capabilities')[1]['anime'],True)
        status,data=self.api('anime_library',status='watching',offset=0,limit=50)
        self.assertEqual(status,200);self.assertEqual(data['items'][0]['episodes_watched'],2)
        self.assertNotIn('access_token',str(data));self.assertEqual(self.api('disconnect')[0],200)
        self.assertEqual(self.api('anime_capabilities')[0],401)
    def test_conflict_and_invalid_owner_never_write(self):
        for fields in [dict(owner_id=8,expected_episodes=2,episodes_watched=3),dict(owner_id=7,expected_episodes=1,episodes_watched=3),dict(owner_id=7,expected_episodes=2,episodes_watched=1),dict(owner_id=7,expected_episodes=2,episodes_watched=13)]:
            self.assertEqual(self.api('anime_update',id=1,**fields)[0],409)
        self.assertEqual(Fixture.anime_writes,0)
    def test_updates_and_lost_response_retry_are_idempotent(self):
        kw=dict(id=1,owner_id=7,expected_episodes=2,episodes_watched=3)
        self.assertEqual(self.api('anime_update',**kw)[0],200)
        self.assertEqual(self.api('anime_update',**kw)[0],200)
        self.assertEqual(Fixture.anime_writes,1)
        self.assertEqual(self.api('anime_update',id=1,owner_id=7,expected_episodes=3,episodes_watched=12)[1]['anime']['status'],'completed')
    def test_paused_remote_status_and_scores_are_not_overwritten(self):
        Fixture.anime_status='on_hold'
        self.assertEqual(self.api('anime_update',id=1,owner_id=7,expected_episodes=2,episodes_watched=3)[1]['anime']['status'],'on_hold')
    def test_validation_precedes_refresh(self):
        calls=Fixture.token_calls
        self.assertEqual(self.api('anime_library',status='reading')[0],422)
        self.assertEqual(self.api('anime_update',id=1,owner_id=7,expected_episodes=2,episodes_watched=-1)[0],422)
        self.assertEqual(calls,Fixture.token_calls)
    def test_explicit_undo_lowers_only_from_the_expected_count(self):
        # Sin la marca de deshacer el progreso nunca baja.
        self.assertEqual(self.api('anime_update',id=1,owner_id=7,expected_episodes=2,episodes_watched=1)[0],409)
        # Si MAL ya no está donde Yoma lo dejó, tampoco.
        self.assertEqual(self.api('anime_update',id=1,owner_id=7,expected_episodes=3,episodes_watched=1,decrease=True)[0],409)
        self.assertEqual(self.api('anime_update',id=1,owner_id=7,expected_episodes=2,episodes_watched=1,decrease='yes')[0],422)
        self.assertEqual(Fixture.anime_writes,0)
        status,data=self.api('anime_update',id=1,owner_id=7,expected_episodes=2,episodes_watched=1,decrease=True)
        self.assertEqual(status,200);self.assertEqual(data['anime']['episodes_watched'],1)
        self.assertEqual(data['anime']['status'],'watching')
        self.assertEqual(Fixture.episodes,1);self.assertEqual(Fixture.anime_writes,1)
    def test_undo_of_a_completed_anime_returns_to_watching(self):
        Fixture.episodes=12;Fixture.anime_status='completed'
        data=self.api('anime_update',id=1,owner_id=7,expected_episodes=12,episodes_watched=11,decrease=True)[1]
        self.assertEqual(data['anime']['status'],'watching');self.assertEqual(Fixture.episodes,11)
    def test_undo_keeps_a_paused_status_and_is_announced(self):
        Fixture.anime_status='on_hold'
        data=self.api('anime_update',id=1,owner_id=7,expected_episodes=2,episodes_watched=0,decrease=True)[1]
        self.assertEqual(data['anime']['status'],'on_hold');self.assertEqual(data['anime']['episodes_watched'],0)
        self.assertEqual(self.api('anime_capabilities')[1]['decrease'],True)
        # Sin temporada de estreno en MAL el año es 0, no un valor inventado.
        self.assertEqual(self.api('anime_detail',id=1)[1]['anime']['year'],0)
if __name__=='__main__':unittest.main()
