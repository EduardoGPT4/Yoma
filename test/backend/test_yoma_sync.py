"""Sincronización de Yoma por cuenta de MAL: PHP real, SQLite local y MAL simulado.

No se leen credenciales ni se toca ninguna cuenta real.
"""
import hashlib
import json
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_myanimelist as bridge  # noqa: E402

Fixture = bridge.Fixture  # La clase del puente no se importa: no se vuelve a ejecutar aquí.


def now_ms():
    return int(time.time() * 1000)


class TestYomaSync(unittest.TestCase):
    setUpClass = classmethod(bridge.TestMangaBridge.setUpClass.__func__)
    tearDownClass = classmethod(bridge.TestMangaBridge.tearDownClass.__func__)
    request = bridge.TestMangaBridge.request
    connect_fixture = bridge.TestMangaBridge.connect_fixture

    def setUp(self):
        Fixture.profile = {'id': 7, 'name': 'MangaTester', 'picture': ''}
        Fixture.profile_status = 200
        Fixture.token_status = 200
        self.token = self.connect_fixture()['device_token']

    def api(self, action, token=None, **kw):
        status, raw, _ = self.request(payload={'action': action, **kw}, token=token or self.token)
        return status, json.loads(raw)

    def pull_all(self, since=0, token=None):
        changes = []
        while True:
            status, data = self.api('sync_pull', token=token, since=since, limit=500)
            self.assertEqual(status, 200, data)
            changes += data['changes']
            since = data['cursor']
            if not data['more']:
                return changes, since

    def test_capabilities_and_mal_is_never_called(self):
        before = len(Fixture.records)
        status, data = self.api('sync_capabilities')
        self.assertEqual(status, 200)
        self.assertEqual(data['sync'], 1)
        self.assertIn('episode', data['kinds'])
        self.api('sync_pull', since=0)
        self.assertEqual(len(Fixture.records), before)  # Ni perfil ni tokens.

    def test_two_devices_of_the_same_account_share_changes(self):
        phone, other = self.token, self.connect_fixture()['device_token']
        _, start = self.pull_all(token=other)
        t = now_ms()
        status, data = self.api('sync_push', token=phone, changes=[
            {'kind': 'anime', 'key': 'frieren-2', 'updated_at': t, 'payload': {'saved': True, 'favorite': True, 'status': 'watching', 'title': 'Frieren', 'cover': 'https://cdn.example/c.jpg', 'extra': 'x'}},
            {'kind': 'episode', 'key': 'frieren-2:3', 'updated_at': t, 'payload': {'episode_id': 135, 'position_ms': 600000, 'duration_ms': 1420000, 'watched': False}},
        ])
        self.assertEqual((status, data['accepted']), (200, 2), data)
        changes, cursor = self.pull_all(since=start, token=other)
        by_key = {c['key']: c for c in changes}
        self.assertEqual(by_key['frieren-2']['payload']['favorite'], True)
        self.assertNotIn('extra', by_key['frieren-2']['payload'])  # Solo campos conocidos.
        self.assertEqual(by_key['frieren-2:3']['payload']['position_ms'], 600000)
        # Sin cambios nuevos, no vuelve nada.
        self.assertEqual(self.pull_all(since=cursor, token=other)[0], [])

    def test_newest_change_wins_and_deletions_travel(self):
        t = now_ms()
        self.api('sync_push', changes=[{'kind': 'anime', 'key': 'lww', 'updated_at': t, 'payload': {'status': 'completed', 'saved': True}}])
        # Un cambio más antiguo (otro dispositivo sin conexión) no pisa al nuevo.
        status, data = self.api('sync_push', changes=[{'kind': 'anime', 'key': 'lww', 'updated_at': t - 5000, 'payload': {'status': 'dropped', 'saved': True}}])
        self.assertEqual(data['accepted'], 0)
        changes, _ = self.pull_all()
        self.assertEqual([c['payload']['status'] for c in changes if c['key'] == 'lww'], ['completed'])
        # Borrado: llega como marca a los demás.
        self.api('sync_push', changes=[{'kind': 'anime', 'key': 'lww', 'updated_at': t + 1000, 'deleted': True}])
        changes, _ = self.pull_all()
        self.assertTrue([c for c in changes if c['key'] == 'lww'][0]['deleted'])

    def test_future_clock_cannot_block_later_changes(self):
        far = now_ms() + 30 * 86400000
        self.api('sync_push', changes=[{'kind': 'anime', 'key': 'clock', 'updated_at': far, 'payload': {'status': 'watching'}}])
        time.sleep(0.01)
        # Se limitó a «ahora + 10 min»: un cambio dentro de una hora gana.
        status, data = self.api('sync_push', changes=[{'kind': 'anime', 'key': 'clock', 'updated_at': now_ms() + 3600000, 'payload': {'status': 'completed'}}])
        self.assertEqual(data['accepted'], 1)

    def test_accounts_are_isolated(self):
        self.api('sync_push', changes=[{'kind': 'anime', 'key': 'private-7', 'updated_at': now_ms(), 'payload': {'saved': True}}])
        Fixture.profile = {'id': 8, 'name': 'Other', 'picture': ''}
        other = self.connect_fixture()['device_token']
        changes, _ = self.pull_all(token=other)
        self.assertNotIn('private-7', [c['key'] for c in changes])

    def test_invalid_input_is_rejected_before_writing(self):
        t = now_ms()
        for changes in [
            [{'kind': 'manga', 'key': 'x', 'updated_at': t, 'payload': {}}],
            [{'kind': 'anime', 'key': '../x', 'updated_at': t, 'payload': {}}],
            [{'kind': 'episode', 'key': 'x', 'updated_at': t, 'payload': {}}],
            [{'kind': 'anime', 'key': 'x', 'updated_at': 5, 'payload': {}}],
            [{'kind': 'anime', 'key': 'x', 'updated_at': t, 'payload': {'title': 'a' * 5000}}],
            [{'kind': 'manga', 'key': 'a' * 40, 'updated_at': t, 'payload': {'url': 'file:///sdcard/manga'}}],
            [{'kind': 'manga_read', 'key': 'a' * 40, 'updated_at': t, 'payload': {}}],
            [{'kind': 'anime', 'key': 'x', 'updated_at': t, 'deleted': 'yes'}],
            [{'kind': 'anime', 'key': f'k{i}', 'updated_at': t, 'payload': {}} for i in range(201)],
        ]:
            status, _ = self.api('sync_push', changes=changes)
            self.assertIn(status, (413, 422), changes[0])
        for bad in [dict(since=-1), dict(since='0'), dict(limit=0), dict(limit=501)]:
            self.assertEqual(self.api('sync_pull', **bad)[0], 422, bad)
        self.assertNotIn('x', [c['key'] for c in self.pull_all()[0]])

    def test_online_manga_travels_between_devices(self):
        # YomaShi: biblioteca, progreso y capítulos leídos, identificados por URL.
        phone, other = self.token, self.connect_fixture()['device_token']
        _, start = self.pull_all(token=other)
        key = lambda url: hashlib.sha256(url.encode()).hexdigest()[:40]
        manga, chapter = 'https://mangadex.org/title/abc', 'https://mangadex.org/chapter/c1'
        t = now_ms()
        status, data = self.api('sync_push', token=phone, changes=[
            {'kind': 'manga', 'key': key(manga), 'updated_at': t, 'payload': {'url': manga, 'title': 'Frieren', 'cover': 'https://cdn.example/f.jpg'}},
            {'kind': 'manga_progress', 'key': key(manga), 'updated_at': t, 'payload': {'url': manga, 'title': 'Frieren', 'chapter_url': chapter, 'chapter_title': 'Cap. 1', 'page': 12, 'source': 'mangadex', 'extra': 1}},
            {'kind': 'manga_read', 'key': key(chapter), 'updated_at': t, 'payload': {'url': chapter}},
        ])
        self.assertEqual((status, data['accepted']), (200, 3), data)
        by_kind = {c['kind']: c for c in self.pull_all(since=start, token=other)[0]}
        self.assertEqual(by_kind['manga_progress']['payload'], {'url': manga, 'title': 'Frieren', 'cover': '', 'chapter_url': chapter, 'chapter_title': 'Cap. 1', 'page': 12, 'source': 'mangadex'})
        self.assertEqual(by_kind['manga_read']['payload'], {'url': chapter})
        # Quitarlo de la biblioteca llega como borrado.
        self.api('sync_push', token=phone, changes=[{'kind': 'manga', 'key': key(manga), 'updated_at': t + 1000, 'deleted': True}])
        changes, _ = self.pull_all(token=other)
        self.assertTrue([c for c in changes if c['kind'] == 'manga'][0]['deleted'])
        status, data = self.api('sync_capabilities')
        self.assertTrue({'manga', 'manga_progress', 'manga_read'} <= set(data['kinds']))

    def test_requires_a_connected_device(self):
        status, _ = self.api('sync_pull', token='0' * 64, since=0)
        self.assertEqual(status, 401)
        self.api('disconnect')
        self.assertEqual(self.api('sync_pull', since=0)[0], 401)


if __name__ == '__main__':
    unittest.main()
