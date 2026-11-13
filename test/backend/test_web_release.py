"""tools/web_release.py sin red: qué entra en un paquete y qué nunca."""
import json
import sys
import unittest
import zipfile
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import web_release as tool  # noqa: E402


class TestWebRelease(unittest.TestCase):
    def test_private_configuration_and_server_data_never_travel(self):
        for path in ['private/config.local.php', 'releases/x/private/access.local.php', 'data/season.json',
                     'releases/x/data/catalog.json.gz', 'feeds/horario.ics', 'desplegado.json']:
            self.assertTrue(tool.private(path), path)
        for path in ['private/ready.json', 'assets/app.js', 'index.php']:
            self.assertFalse(tool.private(path), path)

    def test_only_public_text_is_compared_with_the_live_site(self):
        self.assertTrue(tool.fetchable('releases/x/assets/app.js'))
        self.assertTrue(tool.fetchable('index.html'))
        for path in ['index.php', '.htaccess', 'releases/x/private/ready.json', 'img/yoma.jpg', 'assets/font.woff2']:
            self.assertFalse(tool.fetchable(path), path)

    def test_line_endings_do_not_count_as_a_change(self):
        self.assertEqual(tool.same_text(b'a\r\nb\r\n'), tool.same_text(b'a\nb\n'))
        self.assertNotEqual(tool.same_text(b'a\nb\n'), tool.same_text(b'a\nc\n'))

    def test_ready_json_matches_the_active_release(self):
        tool.check_ready()

    def test_the_package_holds_only_what_changed_plus_ready_json(self):
        release = json.loads((tool.WEB / 'tv.yoma.site/private/current.json').read_text(encoding='utf-8'))['release']
        changed = [f'releases/{release}/private/mal.php']
        out = []
        with mock.patch.object(tool, 'status', return_value=([], changed, ['private/viejo.php'])), \
                mock.patch.object(tool, 'OUT', ROOT / 'build/test-web-release'):
            target = tool.build('tv.yoma.site', out.append)
        try:
            with zipfile.ZipFile(target) as archive:
                self.assertEqual(sorted(archive.namelist()), sorted(changed + [f'releases/{release}/private/ready.json']))
            self.assertTrue(any('private/viejo.php' in line for line in out))
        finally:
            target.unlink()

    def test_nothing_to_upload_builds_nothing(self):
        out = []
        with mock.patch.object(tool, 'status', return_value=([], [], [])):
            self.assertIsNone(tool.build('yoma.site', out.append))
        self.assertIn('No hay nada que subir', out[0])


if __name__ == '__main__':
    unittest.main()
