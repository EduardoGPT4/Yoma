"""Entrar a la web con MyAnimeList: PHP real, SQLite local y un MAL simulado.

Se publica tv.yoma.site tal como está en web/tv.yoma.site (con su enrutado por
versiones). No se usa ninguna base, cuenta ni credencial real.
"""
import http.cookiejar
import json
import os
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
import urllib.parse
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_myanimelist as bridge  # noqa: E402

Fixture = bridge.Fixture
ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / 'web/tv.yoma.site'
ADMIN = 'admin@test.example'


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Browser:
    """Un navegador con sus cookies (su propia sesión de la web)."""

    def __init__(self, base):
        self.base = base
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar), _NoRedirect)
        self.csrf = ''

    def open(self, path, data=None, headers=None):
        request = urllib.request.Request(self.base + path, data=data, headers=headers or {})
        try:
            response = self.opener.open(request, timeout=20)
        except urllib.error.HTTPError as e:
            response = e
        with response:
            return response.status, dict(response.headers), response.read()

    def state(self):
        status, _, body = self.open('actions.php?action=state')
        data = json.loads(body)
        assert status == 200, data
        data = data['data']
        self.csrf = data['csrf']
        return data

    def action(self, action, **values):
        if not self.csrf:
            self.state()
        status, _, body = self.open('actions.php', json.dumps({'action': action, **values}).encode(),
                                    {'Content-Type': 'application/json', 'X-CSRF-Token': self.csrf})
        data = json.loads(body)
        if isinstance(data.get('data'), dict) and data['data'].get('csrf'):
            self.csrf = data['data']['csrf']
        return status, data

    def mal_login(self, **callback):
        """Pulsa «Iniciar sesión con MyAnimeList», autoriza en MAL y vuelve."""
        status, data = self.action('mal_login')
        assert status == 200, data
        url = urllib.parse.urlparse(data['authorization_url'])
        query = urllib.parse.parse_qs(url.query)
        assert (url.scheme, url.netloc, url.path) == ('https', 'myanimelist.net', '/v1/oauth2/authorize'), url
        assert query['redirect_uri'] == ['https://tv.yoma.site/mal-callback.php'], query
        params = {'code': 'fixture-code', 'state': query['state'][0], **callback}
        status, headers, _ = self.open('mal-callback.php?' + urllib.parse.urlencode(params))
        assert status == 303, status
        location = headers['Location']
        self.csrf = ''
        return urllib.parse.parse_qs(urllib.parse.urlparse(location).query)['mal'][0], query['state'][0]


class TestWebMalLogin(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='yoma-web-login-')
        cls.folder = Path(cls.temp.name) / 'htdocs'
        shutil.copytree(SITE, cls.folder)
        # El catálogo inicial lo genera el servidor; aquí basta uno mínimo.
        release = json.loads((SITE / 'private/current.json').read_text(encoding='utf-8'))['release']
        seed = cls.folder / 'releases' / release / 'data/season.json'
        seed.parent.mkdir(exist_ok=True)
        seed.write_text(json.dumps({'fetched_at': 0, 'anime': [{
            'slug': 'frieren-2', 'title': 'Frieren', 'synopsis': '', 'cover': 'https://cdn.example/f.jpg',
            'weekday': 1, 'latest': '1', 'published': '', 'start_date': None, 'season': 'otoño2026',
            'category': 'TV', 'active': 1, 'catalog_complete': 0, 'updated_at': 0}],
            'episodes': [{'slug': 'frieren-2', 'number': '1', 'number_value': 1, 'url': ''}]}), encoding='utf-8')
        cls.db_file = Path(cls.temp.name) / 'web.sqlite'
        cls.mock = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        threading.Thread(target=cls.mock.serve_forever, daemon=True).start()
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        env = {**os.environ, 'SEASON_WEB_SQLITE': str(cls.db_file),
               'SEASON_WEB_MAL_TEST_URL': f'http://127.0.0.1:{cls.mock.server_port}',
               'SEASON_WEB_ADMIN_EMAILS': ADMIN}
        cls.log = open(Path(cls.temp.name) / 'php.log', 'wb')
        cls.php = subprocess.Popen(['php', '-S', f'127.0.0.1:{port}', '-t', str(cls.folder)], env=env, stdout=cls.log, stderr=cls.log)
        cls.base = f'http://127.0.0.1:{port}/'
        try:
            for attempt in range(200):
                try:
                    Browser(cls.base).state()
                    break
                except OSError:
                    if attempt == 199:
                        raise
                    time.sleep(.05)
        except BaseException:
            cls.tearDownClass()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.php.terminate()
        cls.php.wait(timeout=10)
        cls.mock.shutdown()
        cls.mock.server_close()
        cls.log.close()
        cls.temp.cleanup()

    def setUp(self):
        Fixture.profile = {'id': 7001, 'name': 'Tester', 'picture': 'https://cdn.myanimelist.net/images/userimages/7001.jpg'}
        Fixture.profile_status = 200
        Fixture.token_status = 200
        Fixture.token_calls = 0
        # Todas las pruebas llegan desde 127.0.0.1: cada una empieza sin intentos.
        self.sql("DELETE FROM sa1_limits WHERE name LIKE 'mal-login:%'")

    def sql(self, query, values=()):
        conn = sqlite3.connect(self.db_file, timeout=10)
        try:
            with conn:
                return conn.execute(query, values).fetchall()
        finally:
            conn.close()

    def profile(self, account, name):
        Fixture.profile = {'id': account, 'name': name, 'picture': ''}

    def test_first_login_creates_the_account_and_later_logins_enter_it(self):
        self.profile(7101, 'Nueva')
        first = Browser(self.base)
        self.assertTrue(first.state()['mal_login'])
        result, state = first.mal_login()
        self.assertEqual(result, 'welcome')
        self.assertTrue(state.startswith('yl_'))
        user = first.state()['user']
        self.assertEqual((user['name'], user['mal_only']), ('Nueva', True))
        # La conexión con MAL queda hecha: el token solo se guarda cifrado.
        status, data = first.action('account')
        self.assertEqual(status, 200, data)
        self.assertEqual(data['account']['mal_notice'], 'welcome')
        self.assertTrue(data['account']['mal']['connected'])
        self.assertEqual(data['account']['mal']['profile']['id'], 7101)
        cipher = self.sql('SELECT token_cipher FROM sa1_mal_connections WHERE user_id=?', (user['id'],))[0][0]
        self.assertNotIn('fixture-access-token', cipher)
        # Otro navegador (o la misma persona otro día) entra en la misma cuenta.
        second = Browser(self.base)
        self.assertEqual(second.mal_login()[0], 'signed_in')
        self.assertEqual(second.state()['user']['id'], user['id'])
        self.assertEqual(self.sql('SELECT COUNT(*) FROM sa1_users WHERE email=?', ('mal-7101@mal.yoma.site',))[0][0], 1)

    def test_an_email_account_that_connected_mal_is_found_by_its_mal_id(self):
        self.profile(7102, 'Correo')
        owner = Browser(self.base)
        status, data = owner.action('register', name='Con correo', email='correo@test.example', password='contraseña-segura')
        self.assertEqual(status, 200, data)
        status, data = owner.action('mal_connect')
        self.assertEqual(status, 200, data)
        query = urllib.parse.parse_qs(urllib.parse.urlparse(data['authorization_url']).query)
        status, headers, _ = owner.open('mal-callback.php?' + urllib.parse.urlencode({'code': 'c', 'state': query['state'][0]}))
        self.assertIn('mal=connected', headers['Location'])
        account = owner.state()['user']
        self.assertFalse(account['mal_only'])

        other = Browser(self.base)
        self.assertEqual(other.mal_login()[0], 'signed_in')
        self.assertEqual(other.state()['user']['id'], account['id'])
        # El correo y la contraseña siguen funcionando.
        third = Browser(self.base)
        status, data = third.action('login', email='correo@test.example', password='contraseña-segura')
        self.assertEqual(status, 200, data)
        self.assertEqual(data['data']['user']['id'], account['id'])

    def test_a_mal_account_comes_back_after_unlinking_mal(self):
        self.profile(7103, 'Vuelve')
        first = Browser(self.base)
        first.mal_login()
        user = first.state()['user']['id']
        status, data = first.action('mal_disconnect')
        self.assertEqual(status, 200, data)
        self.assertEqual(Browser(self.base).mal_login()[0], 'signed_in')
        self.assertEqual(self.sql('SELECT COUNT(*) FROM sa1_users WHERE email=?', ('mal-7103@mal.yoma.site',))[0][0], 1)
        again = Browser(self.base)
        again.mal_login()
        self.assertEqual(again.state()['user']['id'], user)

    def test_mal_accounts_have_no_password_and_their_address_cannot_be_taken(self):
        self.profile(7104, 'Reservada')
        # Nadie puede registrar antes la dirección interna de otra persona.
        status, data = Browser(self.base).action('register', name='Intruso', email='mal-7104@mal.yoma.site', password='contraseña-segura')
        self.assertEqual(status, 422, data)
        browser = Browser(self.base)
        browser.mal_login()
        # Ni la dirección interna ni una contraseña vacía sirven para entrar.
        for password in ['', 'x']:
            status, _ = Browser(self.base).action('login', email='mal-7104@mal.yoma.site', password=password)
            self.assertIn(status, (401, 422))
        # Se puede eliminar sin contraseña (no tiene).
        status, data = browser.action('account_delete', confirmation='ELIMINAR')
        self.assertEqual(status, 200, data)
        self.assertIsNone(browser.state()['user'])

    def test_an_administrator_account_keeps_entering_with_its_password(self):
        self.sql('INSERT INTO sa1_users(name,email,password_hash,created_at) VALUES(?,?,?,?)', ('Admin', ADMIN, 'x', 0))
        admin = self.sql('SELECT id FROM sa1_users WHERE email=?', (ADMIN,))[0][0]
        self.sql('INSERT INTO sa1_mal_connections (user_id,mal_user_id,mal_name,token_cipher,expires_at,connected_at,checked_at) VALUES (?,?,?,?,?,?,?)',
                 (admin, 7105, 'Admin', '', 0, 0, 0))
        self.profile(7105, 'Admin')
        browser = Browser(self.base)
        self.assertEqual(browser.mal_login()[0], 'use_password')
        self.assertIsNone(browser.state()['user'])

    def test_cancelled_forged_or_expired_authorizations_do_not_sign_in(self):
        self.profile(7106, 'Cancela')
        browser = Browser(self.base)
        self.assertEqual(browser.mal_login(error='access_denied')[0], 'denied')
        self.assertIsNone(browser.state()['user'])
        # Un estado que esta sesión no pidió.
        status, headers, _ = browser.open('mal-callback.php?' + urllib.parse.urlencode({'code': 'c', 'state': 'yl_' + '0' * 48}))
        self.assertIn('mal=expired', headers['Location'])
        self.assertIsNone(browser.state()['user'])
        # Una autorización iniciada en otro navegador no vale en este.
        status, data = Browser(self.base).action('mal_login')
        state = urllib.parse.parse_qs(urllib.parse.urlparse(data['authorization_url']).query)['state'][0]
        status, headers, _ = browser.open('mal-callback.php?' + urllib.parse.urlencode({'code': 'c', 'state': state}))
        self.assertIn('mal=expired', headers['Location'])
        self.assertIsNone(browser.state()['user'])
        # MAL no responde: no se crea nada.
        Fixture.token_status = 500
        self.assertEqual(browser.mal_login()[0], 'error')
        self.assertIsNone(browser.state()['user'])
        self.assertEqual(self.sql('SELECT COUNT(*) FROM sa1_users WHERE email=?', ('mal-7106@mal.yoma.site',))[0][0], 0)

    def test_starting_many_logins_from_one_address_is_limited(self):
        browser = Browser(self.base)
        statuses = [browser.action('mal_login')[0] for _ in range(11)]
        self.assertEqual(statuses, [200] * 10 + [429])

    def test_the_session_changes_when_signing_in(self):
        self.profile(7107, 'Sesion')
        browser = Browser(self.base)
        browser.state()
        before = {c.name: c.value for c in browser.jar}
        browser.mal_login()
        after = {c.name: c.value for c in browser.jar}
        self.assertNotEqual(before.get('SEASONAV1_WEB'), after.get('SEASONAV1_WEB'))


if __name__ == '__main__':
    unittest.main()
