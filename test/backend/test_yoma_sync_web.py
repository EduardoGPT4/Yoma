"""La web de YomaTV en la sincronización de Yoma: PHP real y SQLite local.

Las tablas de la web se crean con sus columnas reales (schema.php) en la base
local del arnés. No se usa ninguna base, cuenta ni credencial real.
"""
import contextlib
import json
import os
import sqlite3
import subprocess
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_myanimelist as bridge  # noqa: E402

Fixture = bridge.Fixture
ROOT = Path(__file__).resolve().parents[2]

WEB_SCHEMA = """
CREATE TABLE IF NOT EXISTS sa1_users (id INTEGER PRIMARY KEY, name VARCHAR(60) NOT NULL, email VARCHAR(190) NOT NULL UNIQUE, password_hash VARCHAR(255) NOT NULL, created_at BIGINT NOT NULL);
CREATE TABLE IF NOT EXISTS sa1_anime (slug VARCHAR(240) PRIMARY KEY, source_id INTEGER, title VARCHAR(400) NOT NULL, synopsis TEXT NOT NULL, cover VARCHAR(400) NOT NULL, weekday INTEGER NOT NULL, latest VARCHAR(16) NOT NULL, published VARCHAR(60) NOT NULL, start_date VARCHAR(30), season VARCHAR(40) NOT NULL, category VARCHAR(40) NOT NULL, active INTEGER NOT NULL DEFAULT 1, catalog_complete INTEGER NOT NULL DEFAULT 0, updated_at BIGINT NOT NULL);
CREATE TABLE IF NOT EXISTS sa1_episodes (id INTEGER PRIMARY KEY, slug VARCHAR(240) NOT NULL, number VARCHAR(16) NOT NULL, number_value DOUBLE NOT NULL, url VARCHAR(500) NOT NULL, mirrors TEXT, mirrors_at BIGINT NOT NULL DEFAULT 0, UNIQUE(slug, number));
CREATE TABLE IF NOT EXISTS sa1_follow (user_id INTEGER NOT NULL, slug VARCHAR(240) NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'watching', favorite INTEGER NOT NULL DEFAULT 0, excluded INTEGER NOT NULL DEFAULT 0, score INTEGER NOT NULL DEFAULT 0, notes TEXT NOT NULL, PRIMARY KEY(user_id, slug));
CREATE TABLE IF NOT EXISTS sa1_watched (user_id INTEGER NOT NULL, episode_id INTEGER NOT NULL, watched_at BIGINT NOT NULL, PRIMARY KEY(user_id, episode_id));
CREATE TABLE IF NOT EXISTS sa1_playback (user_id INTEGER NOT NULL, episode_id INTEGER NOT NULL, mode VARCHAR(10) NOT NULL, position DOUBLE NOT NULL DEFAULT 0, duration DOUBLE NOT NULL DEFAULT 0, session_key VARCHAR(32) NOT NULL, sequence_no BIGINT NOT NULL DEFAULT 0, updated_at BIGINT NOT NULL DEFAULT 0, PRIMARY KEY(user_id, episode_id, mode));
CREATE TABLE IF NOT EXISTS sa1_mal_connections (user_id INTEGER PRIMARY KEY, mal_user_id BIGINT NOT NULL, mal_name VARCHAR(60) NOT NULL, token_cipher TEXT NOT NULL, expires_at BIGINT NOT NULL, connected_at BIGINT NOT NULL, checked_at BIGINT NOT NULL, needs_auth INTEGER NOT NULL DEFAULT 0, refresh_lock_until BIGINT NOT NULL DEFAULT 0);
"""


def now_ms():
    return int(time.time() * 1000)


class TestYomaSyncWeb(unittest.TestCase):
    setUpClass = classmethod(bridge.TestMangaBridge.setUpClass.__func__)
    tearDownClass = classmethod(bridge.TestMangaBridge.tearDownClass.__func__)
    request = bridge.TestMangaBridge.request
    connect_fixture = bridge.TestMangaBridge.connect_fixture
    user = 0

    @contextlib.contextmanager
    def db(self):
        # Confirma y cierra: en Windows un archivo abierto no se puede borrar.
        conn = sqlite3.connect(self.folder / 'fixture.sqlite', timeout=10)
        conn.row_factory = sqlite3.Row
        try:
            with conn:
                yield conn
        finally:
            conn.close()

    def setUp(self):
        Fixture.profile = {'id': 7, 'name': 'Tester', 'picture': ''}
        Fixture.profile_status = 200
        Fixture.token_status = 200
        self.token = self.connect_fixture()['device_token']
        type(self).user += 1
        self.uid = 100 + self.user
        with self.db() as c:
            c.executescript(WEB_SCHEMA)
            c.execute('INSERT INTO sa1_users VALUES (?,?,?,?,?)', (self.uid, 'Web', f'web{self.uid}@test', 'x', 0))
            c.execute('INSERT INTO sa1_mal_connections (user_id, mal_user_id, mal_name, token_cipher, expires_at, connected_at, checked_at) VALUES (?,?,?,?,?,?,?)', (self.uid, 7, 'Tester', '', 0, 0, 0))
            for slug, title in [('frieren-2', 'Frieren'), ('otro', 'Otro')]:
                c.execute("INSERT OR IGNORE INTO sa1_anime (slug, title, synopsis, cover, weekday, latest, published, season, category, updated_at) VALUES (?,?,'','https://cdn.example/c.jpg',1,'3','', 'otoño2026','TV',0)", (slug, title))
                for n in (1, 2, 3):
                    c.execute("INSERT OR IGNORE INTO sa1_episodes (id, slug, number, number_value, url) VALUES (?,?,?,?, '')", ((1 if slug == 'frieren-2' else 2) * 100 + n, slug, str(n), n))
        # Cada prueba empieza con la cuenta de MAL vacía.
        with self.db() as c:
            for table in ['sa1_yoma_sync', 'sa1_yoma_sync_rev']:
                try:
                    c.execute(f'DELETE FROM {table}')
                except sqlite3.OperationalError:
                    pass

    def web_sync(self, force=True, user=None):
        program = r'''define('SEASON_BOOTSTRAPPED',true);require $argv[1].'/private/app.php';require $argv[1].'/private/yoma-sync.php';require $argv[1].'/private/yoma-sync-web.php';echo json_encode(yoma_sync_web(db(),(int)$argv[2],$argv[3]==='1'));'''
        env = {**os.environ, 'YS_TEST_DB': str(self.folder / 'fixture.sqlite')}
        result = subprocess.run(['php', '-r', program, str(self.folder), str(user or self.uid), '1' if force else '0'], env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return json.loads(result.stdout)

    def api(self, action, **kw):
        status, raw, _ = self.request(payload={'action': action, **kw}, token=self.token)
        self.assertEqual(status, 200, raw)
        return json.loads(raw)

    def phone_items(self):
        changes, since = {}, 0
        while True:
            data = self.api('sync_pull', since=since, limit=500)
            for c in data['changes']:
                changes[(c['kind'], c['key'])] = c
            since = data['cursor']
            if not data['more']:
                return changes

    def test_the_web_library_reaches_the_phone(self):
        with self.db() as c:
            c.execute("INSERT INTO sa1_follow VALUES (?, 'frieren-2', 'watching', 1, 0, 0, '')", (self.uid,))
            c.execute('INSERT INTO sa1_watched VALUES (?, 101, ?)', (self.uid, int(time.time()) - 60))
            c.execute("INSERT INTO sa1_playback VALUES (?, 102, 'web', 300.5, 1420, 'k', 1, ?)", (self.uid, int(time.time())))
        result = self.web_sync()
        self.assertEqual(result['sent'], 3)
        items = self.phone_items()
        anime = items[('anime', 'frieren-2')]['payload']
        self.assertEqual((anime['saved'], anime['favorite'], anime['status'], anime['title']), (True, True, 'watching', 'Frieren'))
        self.assertTrue(items[('episode', 'frieren-2:1')]['payload']['watched'])
        self.assertEqual(items[('episode', 'frieren-2:2')]['payload']['position_ms'], 300500)
        self.assertEqual(items[('episode', 'frieren-2:2')]['payload']['episode_id'], 102)

    def test_the_web_ignores_manga_from_yomashi(self):
        # La web solo tiene anime: el manga del teléfono no se aplica ni la rompe.
        self.web_sync()
        t = now_ms()
        self.api('sync_push', changes=[
            {'kind': 'manga', 'key': 'a' * 40, 'updated_at': t, 'payload': {'url': 'https://mangadex.org/title/x', 'title': 'X'}},
            {'kind': 'manga_read', 'key': 'b' * 40, 'updated_at': t, 'payload': {'url': 'https://mangadex.org/chapter/y'}},
            {'kind': 'anime', 'key': 'otro', 'updated_at': t, 'payload': {'saved': True, 'status': 'planned'}},
        ])
        result = self.web_sync()
        self.assertEqual(result['applied'], 1)
        # Y no los borra ni los reescribe al subir lo de la web.
        items = self.phone_items()
        self.assertFalse(items[('manga', 'a' * 40)]['deleted'])

    def test_the_phone_reaches_the_web(self):
        self.web_sync()
        t = now_ms()
        self.api('sync_push', changes=[
            {'kind': 'anime', 'key': 'otro', 'updated_at': t, 'payload': {'saved': True, 'favorite': False, 'status': 'planned'}},
            {'kind': 'episode', 'key': 'otro:3', 'updated_at': t, 'payload': {'episode_id': 203, 'watched': True}},
            {'kind': 'anime', 'key': 'no-esta-en-la-web', 'updated_at': t, 'payload': {'saved': True}},
        ])
        result = self.web_sync()
        self.assertEqual(result['applied'], 2)
        with self.db() as c:
            follow = c.execute('SELECT status, favorite FROM sa1_follow WHERE user_id=? AND slug=?', (self.uid, 'otro')).fetchone()
            self.assertEqual((follow['status'], follow['favorite']), ('planned', 0))
            self.assertIsNotNone(c.execute('SELECT 1 FROM sa1_watched WHERE user_id=? AND episode_id=203', (self.uid,)).fetchone())
        # Lo aplicado no vuelve a subirse como cambio de la web.
        self.assertEqual(self.web_sync()['sent'], 0)

    def test_removals_travel_both_ways(self):
        with self.db() as c:
            c.execute("INSERT INTO sa1_follow VALUES (?, 'frieren-2', 'watching', 0, 0, 0, '')", (self.uid,))
            c.execute('INSERT INTO sa1_watched VALUES (?, 101, ?)', (self.uid, int(time.time()) - 60))
        self.web_sync()
        # El teléfono deja de seguirlo: desaparece de la web.
        self.api('sync_push', changes=[{'kind': 'anime', 'key': 'frieren-2', 'updated_at': now_ms() + 1000, 'payload': {'saved': False, 'favorite': False}}])
        self.web_sync()
        with self.db() as c:
            self.assertIsNone(c.execute('SELECT 1 FROM sa1_follow WHERE user_id=? AND slug=?', (self.uid, 'frieren-2')).fetchone())
            # La web desmarca el episodio: llega al teléfono.
            c.execute('DELETE FROM sa1_watched WHERE user_id=? AND episode_id=101', (self.uid,))
        self.web_sync()
        self.assertFalse(self.phone_items()[('episode', 'frieren-2:1')]['payload']['watched'])

    def test_first_sync_does_not_overwrite_newer_phone_data(self):
        self.api('sync_push', changes=[{'kind': 'anime', 'key': 'frieren-2', 'updated_at': now_ms(), 'payload': {'saved': True, 'favorite': True, 'status': 'completed'}}])
        with self.db() as c:
            c.execute("INSERT INTO sa1_follow VALUES (?, 'frieren-2', 'watching', 0, 0, 0, '')", (self.uid,))
        self.web_sync()
        self.assertEqual(self.phone_items()[('anime', 'frieren-2')]['payload']['status'], 'completed')
        with self.db() as c:
            row = c.execute('SELECT status, favorite FROM sa1_follow WHERE user_id=? AND slug=?', (self.uid, 'frieren-2')).fetchone()
        self.assertEqual((row['status'], row['favorite']), ('completed', 1))

    def test_hidden_anime_and_unlinked_accounts_are_left_alone(self):
        with self.db() as c:
            c.execute("INSERT INTO sa1_follow VALUES (?, 'otro', 'dropped', 0, 1, 0, '')", (self.uid,))
        self.api('sync_push', changes=[{'kind': 'anime', 'key': 'otro', 'updated_at': now_ms(), 'payload': {'saved': True, 'status': 'watching'}}])
        self.web_sync()
        with self.db() as c:
            row = c.execute('SELECT status, excluded FROM sa1_follow WHERE user_id=? AND slug=?', (self.uid, 'otro')).fetchone()
            self.assertEqual((row['status'], row['excluded']), ('dropped', 1))
            c.execute('INSERT INTO sa1_users VALUES (?,?,?,?,?)', (900 + self.uid, 'Sin MAL', f'nomal{self.uid}@test', 'x', 0))
        self.assertEqual(self.web_sync(user=900 + self.uid), {'linked': False})

    def test_web_sync_waits_between_runs(self):
        self.web_sync(force=False)
        self.assertTrue(self.web_sync(force=False).get('skipped'))


    def test_bridge_and_web_copies_load_together(self):
        # El puente arranca cargando la web: las dos copias en una petición.
        copy = self.folder / 'private' / 'web-copy'
        copy.mkdir(exist_ok=True)
        for name in ['yoma-sync.php', 'yoma-sync-web.php']:
            (copy / name).write_bytes((ROOT / 'server/private' / name).read_bytes())
        program = r'''define('SEASON_BOOTSTRAPPED',true);require $argv[1].'/private/app.php';require $argv[1].'/private/web-copy/yoma-sync.php';require $argv[1].'/private/web-copy/yoma-sync-web.php';require $argv[1].'/private/yomashi-mal.php';require $argv[1].'/private/yoma-sync-web.php';echo function_exists('yoma_sync_dispatch')&&function_exists('yoma_sync_web')?'ok':'missing';'''
        env = {**os.environ, 'YS_TEST_DB': str(self.folder / 'fixture.sqlite')}
        result = subprocess.run(['php', '-r', program, str(self.folder)], env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual((result.returncode, result.stdout), (0, 'ok'), result.stderr)

if __name__ == '__main__':
    unittest.main()
