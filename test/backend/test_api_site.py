"""api.yoma.site de punta a punta: su arranque propio, PHP real, SQLite y un MAL simulado.

Se publica el sitio tal como está en web/api.yoma.site. No se usa ninguna base,
cuenta ni credencial real.
"""
import hashlib
import json
import os
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_myanimelist as bridge  # noqa: E402

Fixture = bridge.Fixture
ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / 'web/api.yoma.site'
WEB = ROOT / 'web/tv.yoma.site/releases/yoma-design-20261111-1/private'


def function_source(text, name):
    match = re.search(r'^function ' + name + r'\(.*?^\}\n', text, re.S | re.M)
    return match.group(0) if match else None


class TestApiSiteSources(unittest.TestCase):
    """Las copias de api.yoma.site no se separan de su original."""

    def test_bridge_files_are_the_server_sources(self):
        self.assertEqual((SITE / 'yomashi-api.php').read_bytes(), (ROOT / 'server/yomashi-api.php').read_bytes())
        for name in ['yomashi-mal.php', 'yoma-anime-mal.php', 'yoma-sync.php']:
            self.assertEqual((SITE / 'private' / name).read_bytes(), (ROOT / 'server/private' / name).read_bytes(), name)

    def test_shared_helpers_are_the_web_ones(self):
        self.assertEqual((SITE / 'private/mal-http.php').read_bytes(), (WEB / 'mal-http.php').read_bytes())
        app = (SITE / 'private/app.php').read_text(encoding='utf-8')
        for file, name in [('db.php', 'sql'), ('bootstrap.php', 'rate'), ('runtime.php', 'consume_limit'),
                           ('runtime.php', 'release_remote_session'), ('mal.php', 'mal_tokens'),
                           ('mal.php', 'mal_profile_data'), ('mal-avatar.php', 'mal_avatar_url')]:
            original = function_source((WEB / file).read_text(encoding='utf-8'), name)
            self.assertIsNotNone(original, name)
            self.assertEqual(function_source(app, name), original, name)

    def test_private_configuration_is_never_in_the_site(self):
        self.assertFalse(list(SITE.rglob('*.local.php')))
        self.assertIn('Require all denied', (SITE / 'private/.htaccess').read_text(encoding='utf-8'))


class TestApiSite(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='yoma-api-')
        cls.folder = Path(cls.temp.name) / 'htdocs'
        shutil.copytree(SITE, cls.folder)
        cls.db_file = Path(cls.temp.name) / 'api.sqlite'
        with sqlite3.connect(cls.db_file) as c:
            # La web crea esta tabla en la base compartida.
            c.execute('CREATE TABLE sa1_limits (name VARCHAR(190) PRIMARY KEY, hits INTEGER NOT NULL, reset_at BIGINT NOT NULL)')
        c.close()
        cls.mock = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        threading.Thread(target=cls.mock.serve_forever, daemon=True).start()
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        cls.env = {**os.environ, 'SEASON_WEB_SQLITE': str(cls.db_file), 'SEASON_WEB_MAL_TEST_URL': f'http://127.0.0.1:{cls.mock.server_port}'}
        cls.log = open(Path(cls.temp.name) / 'php.log', 'wb')
        cls.php = subprocess.Popen(['php', '-S', f'127.0.0.1:{port}', '-t', str(cls.folder)], env=cls.env, stdout=cls.log, stderr=cls.log)
        cls.base = f'http://127.0.0.1:{port}/'
        for _ in range(100):
            try:
                urllib.request.urlopen(cls.base, timeout=.3).close()
                break
            except urllib.error.HTTPError as e:
                e.close()
                break
            except OSError:
                time.sleep(.05)

    @classmethod
    def tearDownClass(cls):
        cls.php.terminate()
        cls.php.wait(timeout=10)
        cls.mock.shutdown()
        cls.mock.server_close()
        cls.log.close()
        cls.temp.cleanup()

    def setUp(self):
        Fixture.profile = {'id': 7, 'name': 'Tester', 'picture': 'https://cdn.myanimelist.net/images/userimages/7.jpg'}
        Fixture.profile_status = 200
        Fixture.token_status = 200
        Fixture.token_calls = 0

    def api(self, payload, token=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['X-YomaShi-Token'] = token
        request = urllib.request.Request(self.base + 'yomashi-api.php', data=json.dumps(payload).encode(), headers=headers)
        try:
            response = urllib.request.urlopen(request, timeout=10)
        except urllib.error.HTTPError as e:
            response = e
        with response:
            return response.status, json.loads(response.read())

    def connected_device(self, expires_in=3600):
        """Un teléfono ya conectado (la autorización ocurre en tv.yoma.site)."""
        token = os.urandom(32).hex()
        device = os.urandom(16).hex()
        program = r'''define('SEASON_BOOTSTRAPPED',true);require $argv[1].'/private/app.php';require $argv[1].'/private/yomashi-mal.php';$db=db();ys_schema($db);
$tokens=['access_token'=>'fixture-access-token','refresh_token'=>'fixture-refresh-token-0','expires_at'=>time()+(int)$argv[4],'profile'=>['id'=>7,'name'=>'Tester','picture'=>''],'profile_next_refresh'=>time()+3600];
sql($db,'INSERT INTO sa1_yomashi_devices (id,token_hash,tokens,mal_user_id,mal_name,expires_at,created_at) VALUES (?,?,?,?,?,?,?)',[$argv[2],hash('sha256',$argv[3]),ys_crypt(json_encode($tokens),$argv[2]),7,'Tester',time()+86400,time()]);'''
        result = subprocess.run(['php', '-r', program, str(self.folder), device, token, str(expires_in)], env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return token

    def test_the_status_page_answers_without_exposing_configuration(self):
        with urllib.request.urlopen(self.base, timeout=10) as r:
            self.assertEqual(json.loads(r.read()), {'service': 'yoma-api', 'ok': False})

    def test_ping_proves_the_database_works(self):
        self.assertEqual(self.api({'action': 'ping'}), (200, {'service': 'yoma-api', 'sync': True}))

    def test_connection_starts_here_but_authorizes_on_tv(self):
        status, data = self.api({'action': 'start'})
        self.assertEqual(status, 200, data)
        self.assertTrue(data['connect_url'].startswith('https://tv.yoma.site/yomashi-connect.php?device='), data['connect_url'])

    def test_a_connected_phone_uses_mal_and_sync_through_the_api(self):
        token = self.connected_device()
        status, data = self.api({'action': 'status'}, token)
        self.assertEqual((status, data['connected'], data['profile']['id']), (200, True, 7), data)
        status, data = self.api({'action': 'search', 'query': 'Berserk'}, token)
        self.assertEqual(status, 200, data)
        self.assertEqual(data['items'][0]['id'], 2)
        status, data = self.api({'action': 'sync_push', 'changes': [{'kind': 'anime', 'key': 'frieren-2', 'updated_at': int(time.time() * 1000), 'payload': {'saved': True}}]}, token)
        self.assertEqual((status, data['accepted']), (200, 1), data)
        status, data = self.api({'action': 'sync_pull', 'since': 0}, token)
        self.assertEqual([c['key'] for c in data['changes']], ['frieren-2'])

    def test_expired_access_is_renewed_with_the_shared_configuration(self):
        token = self.connected_device(expires_in=-10)
        status, data = self.api({'action': 'search', 'query': 'Berserk'}, token)
        self.assertEqual(status, 200, data)
        self.assertEqual(Fixture.token_calls, 1)  # Renovó con client_secret del config.
        self.assertNotIn('fixture-access-token', json.dumps(data))

    def test_unknown_devices_and_requests_are_rejected(self):
        self.assertEqual(self.api({'action': 'status'}, '0' * 64)[0], 401)
        self.assertEqual(self.api({'action': 'nada'}, '0' * 64)[0], 404)
        status, _ = self.api({'action': 'sync_pull', 'since': -1}, self.connected_device())
        self.assertEqual(status, 422)


if __name__ == '__main__':
    unittest.main()
