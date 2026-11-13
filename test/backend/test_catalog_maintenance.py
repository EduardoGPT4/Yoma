"""La tarea «Mantenimiento del catálogo»: tools/run_catalog_maintenance.py.

- Contra un alojamiento simulado con la comprobación de InfinityFree.
- Contra la web real en local (PHP, SQLite), sin pedir nada a la fuente.
No usa ningún token, base ni credencial real.
"""
import hashlib
import io
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
from contextlib import redirect_stdout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import run_catalog_maintenance as tool  # noqa: E402

SITE = ROOT / 'web/tv.yoma.site'
TOKEN = 'ab' * 32


def aes_encrypt_hex(key, iv, plain):
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    except ImportError:
        openssl = shutil.which('openssl')
        if not openssl:
            raise unittest.SkipTest('Sin openssl ni cryptography')
        return subprocess.run([openssl, 'enc', '-e', '-aes-128-cbc', '-K', key, '-iv', iv, '-nopad'],
                              input=bytes.fromhex(plain), capture_output=True, check=True).stdout.hex()
    encryptor = Cipher(algorithms.AES(bytes.fromhex(key)), modes.CBC(bytes.fromhex(iv))).encryptor()
    return (encryptor.update(bytes.fromhex(plain)) + encryptor.finalize()).hex()


class Hosting(BaseHTTPRequestHandler):
    """Como InfinityFree: sin la cookie __test responde con la comprobación."""
    key, iv, cookie = '0f' * 16, '1e' * 16, '2d' * 16
    results = []
    calls = []

    def log_message(self, *args):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        type(self).calls.append((self.headers.get('Authorization'), self.headers.get('Cookie')))
        if self.headers.get('Cookie') != '__test=' + self.cookie:
            cipher = aes_encrypt_hex(self.key, self.iv, self.cookie)
            body = ('<html><body><script src="/aes.js"></script><script>function toNumbers(d){}'
                    f'var a=toNumbers("{self.key}"),b=toNumbers("{self.iv}"),c=toNumbers("{cipher}");'
                    'document.cookie="__test="+toHex(slowAES.decrypt(c,2,a,b));</script></body></html>').encode()
            return self.reply(200, body, 'text/html')
        if self.headers.get('Authorization') != 'Bearer ' + TOKEN:
            return self.reply(403, json.dumps({'ok': False, 'message': 'Token de actualización no válido.'}).encode())
        result = type(self).results.pop(0) if type(self).results else {'skipped': True, 'remaining': 0, 'reason': 'Nada pendiente.'}
        self.reply(200, json.dumps({'ok': True, 'result': result}).encode())

    def reply(self, status, body, kind='application/json'):
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class TestRunner(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), Hosting)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = f'http://127.0.0.1:{cls.server.server_port}/maintenance.php'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        Hosting.calls = []
        Hosting.results = []

    def run_tool(self, token=TOKEN, steps=5):
        lines = []
        code = tool.run(tool.Runner(self.url, token), steps, 0, sleep=lambda _: None, out=lines.append)
        return code, lines

    def test_solves_the_hosting_check_and_runs_until_nothing_is_left(self):
        Hosting.results = [{'skipped': False, 'anime': 40, 'remaining': 2},
                           {'skipped': False, 'updated_slug': 'frieren-2', 'updated_kind': 'detail', 'remaining': 1},
                           {'skipped': True, 'remaining': 0, 'reason': 'Nada pendiente.'}]
        code, lines = self.run_tool(steps=10)
        self.assertEqual(code, 0, lines)
        self.assertEqual(lines[:3], ['Paso 1: horario revisado: 40 animes · pendientes: 2',
                                     'Paso 2: listado actualizado: frieren-2 · pendientes: 1',
                                     'Paso 3: sin trabajo: Nada pendiente. · pendientes: 0'])
        # La primera llamada recibió la comprobación; las demás ya llevan la cookie.
        self.assertIsNone(Hosting.calls[0][1])
        self.assertTrue(all(cookie == '__test=' + Hosting.cookie for _, cookie in Hosting.calls[1:]))
        self.assertEqual(len(Hosting.calls), 4)

    def test_a_rejected_token_fails_without_showing_it(self):
        code, lines = self.run_tool(token='cd' * 32)
        self.assertEqual(code, 1)
        self.assertIn('HTTP 403', lines[0])
        self.assertNotIn('cd' * 32, '\n'.join(lines))

    def test_without_a_token_it_does_nothing(self):
        out = io.StringIO()
        old = os.environ.pop('YOMA_MAINTENANCE_TOKEN', None)
        try:
            with redirect_stdout(out):
                self.assertEqual(tool.main(['--steps', '3']), 0)
        finally:
            if old is not None:
                os.environ['YOMA_MAINTENANCE_TOKEN'] = old
        self.assertIn('no se hace nada', out.getvalue())
        self.assertEqual(Hosting.calls, [])

    def test_brings_the_intermediates_the_hosting_does_not_send(self):
        # Linux no los descarga solos: sin ellos, GitHub no verifica tv.yoma.site.
        pems = sorted(tool.INTERMEDIATES.glob('gts_*.pem'))
        self.assertIn('gts_wr1.pem', [p.name for p in pems])
        workflow = (ROOT / '.github/workflows/catalog-maintenance.yml').read_text(encoding='utf-8')
        self.assertIn('android/app/src/main/res/raw/gts_*.pem', workflow)
        self.assertTrue(tool.tls_context().cert_store_stats()['x509'] >= len(pems))

    def test_only_the_site_or_this_computer(self):
        for url in ['https://evil.example/maintenance.php', 'http://tv.yoma.site/maintenance.php']:
            with self.assertRaises(tool.MaintenanceError):
                tool.Runner(url, TOKEN)


class TestRealSite(unittest.TestCase):
    """El endpoint real de la web, en local y sin acceso a la fuente."""

    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='yoma-maintenance-')
        cls.folder = Path(cls.temp.name) / 'htdocs'
        shutil.copytree(SITE, cls.folder)
        release = json.loads((SITE / 'private/current.json').read_text(encoding='utf-8'))['release']
        seed = cls.folder / 'releases' / release / 'data/season.json'
        seed.parent.mkdir(exist_ok=True)
        seed.write_text(json.dumps({'fetched_at': 0, 'anime': [{
            'slug': 'frieren-2', 'title': 'Frieren', 'synopsis': '', 'cover': '', 'weekday': 1, 'latest': '1',
            'published': '', 'start_date': None, 'season': '', 'category': 'TV', 'active': 0,
            'catalog_complete': 1, 'updated_at': 0}],
            'episodes': [{'slug': 'frieren-2', 'number': '1', 'number_value': 1, 'url': ''}]}), encoding='utf-8')
        cls.config = cls.folder / 'releases' / release / 'private/config.local.php'
        cls.db_file = Path(cls.temp.name) / 'web.sqlite'
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        env = {**os.environ, 'SEASON_WEB_SQLITE': str(cls.db_file)}
        cls.log = open(Path(cls.temp.name) / 'php.log', 'wb')
        cls.php = subprocess.Popen(['php', '-S', f'127.0.0.1:{port}', '-t', str(cls.folder)], env=env, stdout=cls.log, stderr=cls.log)
        cls.url = f'http://127.0.0.1:{port}/maintenance.php'
        import urllib.request
        for attempt in range(200):
            try:
                urllib.request.urlopen(f'http://127.0.0.1:{port}/actions.php?action=state', timeout=5).close()
                break
            except OSError:
                if attempt == 199:
                    cls.tearDownClass()
                    raise
                time.sleep(.05)
        # Todo al día: ningún paso necesita la fuente.
        far = str(int(time.time()) + 86400)
        conn = sqlite3.connect(cls.db_file)
        with conn:
            for name, value in [('maintenance_token_hash', hashlib.sha256(TOKEN.encode()).hexdigest()),
                                ('maintenance_next_due', far), ('directory_next_cycle', far)]:
                conn.execute('INSERT OR REPLACE INTO sa1_meta(name,value) VALUES(?,?)', (name, value))
            conn.execute('INSERT OR REPLACE INTO sa1_catalog_freshness(slug,episodes_at) VALUES(?,?)', ('frieren-2', int(time.time())))
        conn.close()

    @classmethod
    def tearDownClass(cls):
        cls.php.terminate()
        cls.php.wait(timeout=10)
        cls.log.close()
        cls.temp.cleanup()

    def run_tool(self, token=TOKEN):
        lines = []
        code = tool.run(tool.Runner(self.url, token), 3, 0, sleep=lambda _: None, out=lines.append)
        return code, lines

    def test_disabled_until_the_configuration_allows_it(self):
        self.config.unlink(missing_ok=True)
        code, lines = self.run_tool()
        self.assertEqual(code, 1)
        self.assertIn('desactivada', lines[0])

    def test_runs_with_the_token_and_rejects_another(self):
        self.config.write_text("<?php return ['external_maintenance' => true];", encoding='utf-8')
        try:
            code, lines = self.run_tool()
            self.assertEqual(code, 0, lines)
            self.assertTrue(lines[0].startswith('Paso 1: sin trabajo'), lines)
            code, lines = self.run_tool(token='cd' * 32)
            self.assertEqual(code, 1)
            self.assertIn('Token de actualización no válido', lines[0])
        finally:
            self.config.unlink(missing_ok=True)


if __name__ == '__main__':
    unittest.main()
