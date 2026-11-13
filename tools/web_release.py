"""Prepara y comprueba las subidas de las webs de Yoma (web/<sitio> → htdocs).

    python -I tools/web_release.py estado    tv.yoma.site
    python -I tools/web_release.py paquete   tv.yoma.site
    python -I tools/web_release.py publicado tv.yoma.site

- estado: qué difiere entre esta carpeta y lo publicado. Los archivos públicos
  de texto (HTML, CSS, JS, JSON…) se comparan descargándolos del sitio real. El
  resto (PHP, .htaccess, private/, imágenes, fuentes) se compara con el último
  commit marcado como publicado en web/desplegado.json.
- paquete: crea dist/sitios/actualizacion/<sitio>-<commit>.zip solo con eso,
  listo para descomprimir en htdocs. Antes comprueba que ready.json esté al día.
- publicado: tras subir el paquete, comprueba el sitio real (salud, estado y
  archivos públicos) y, si todo responde, marca el commit como publicado.

Nunca incluye ni lee configuración privada (*.local.php) ni datos del
servidor (data/, feeds/, downloads/). Resuelve la comprobación de InfinityFree
y su certificado incompleto igual que la app.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_catalog_maintenance import aes_decrypt_hex, tls_context  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / 'web'
STATE = WEB / 'desplegado.json'
OUT = ROOT / 'dist/sitios/actualizacion'
SITES = ('tv.yoma.site', 'api.yoma.site', 'yoma.site', 'shi.yoma.site')
# Se comparan descargándolos. Las imágenes y fuentes no: el alojamiento puede
# guardar otra codificación de la misma imagen; esas se siguen por Git.
PUBLIC = {'.html', '.css', '.js', '.json', '.webmanifest', '.txt', '.svg'}
SERVER_DATA = {'data', 'downloads', 'feeds'}
USER_AGENT = 'Mozilla/5.0 Yoma web release check'


class ReleaseError(Exception):
    pass


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def same_text(data):
    return hashlib.sha256(data.replace(b'\r\n', b'\n')).digest()


def private(path):
    """No se publica nunca desde aquí: configuración y datos del servidor."""
    parts = path.split('/')
    return path.endswith('.local.php') or bool(SERVER_DATA & set(parts)) or path == 'desplegado.json'


def fetchable(path):
    parts = path.split('/')
    return Path(path).suffix.lower() in PUBLIC and 'private' not in parts and not private(path)


class Site:
    """Cliente del sitio real con la comprobación de InfinityFree resuelta."""

    def __init__(self, host):
        self.host = host
        self.cookie = ''
        self.context = tls_context()

    def request(self, path, data=None, headers=None):
        for _ in range(3):
            sent = {'User-Agent': USER_AGENT, **(headers or {})}
            if self.cookie:
                sent['Cookie'] = '__test=' + self.cookie
            url = f'https://{self.host}/' + urllib.parse.quote(path, safe='/?=&')
            request = urllib.request.Request(url, data=data, headers=sent, method='POST' if data is not None else 'GET')
            try:
                response = urllib.request.urlopen(request, timeout=60, context=self.context)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                status, body = response.status, response.read(20 * 1024 * 1024)
            if b'slowAES.decrypt' in body:
                values = re.findall(r'toNumbers\("([a-fA-F0-9]+)"\)', body.decode('utf-8', 'replace'))
                if len(values) != 3:
                    raise ReleaseError(f'{self.host}: el alojamiento cambió su comprobación.')
                self.cookie = aes_decrypt_hex(*values)
                continue
            return status, body
        raise ReleaseError(f'{self.host}: no se pudo superar la comprobación del alojamiento.')


def deployed():
    return json.loads(STATE.read_text(encoding='utf-8')) if STATE.is_file() else {}


def tracked(site):
    prefix = f'web/{site}/'
    return [p[len(prefix):] for p in git('ls-files', '--', prefix).splitlines() if not private(p[len(prefix):])]


def check_ready():
    """ready.json de la versión activa de tv debe tener las huellas actuales."""
    current = json.loads((WEB / 'tv.yoma.site/private/current.json').read_text(encoding='utf-8'))['release']
    release = WEB / 'tv.yoma.site/releases' / current
    ready = json.loads((release / 'private/ready.json').read_text(encoding='utf-8'))
    stale = [name for name, digest in ready['files'].items()
             if not private(name) and (release / name).is_file()
             and hashlib.sha256((release / name).read_bytes()).hexdigest() != digest]
    if stale:
        raise ReleaseError('ready.json no está al día: ' + ', '.join(stale[:5]) + ('…' if len(stale) > 5 else ''))


def status(site, out=print):
    """(distintos en el sitio, cambiados desde lo publicado, borrados desde lo publicado)."""
    files = tracked(site)
    client = Site(site)
    differ = []
    for path in files:
        if not fetchable(path):
            continue
        code, body = client.request(path)
        local = (WEB / site / path).read_bytes()
        # Solo cuenta un cambio real: CRLF y LF sirven igual.
        if code != 200 or same_text(body) != same_text(local):
            differ.append(path)
        time.sleep(0.2)
    base = deployed().get(site)
    changed, removed = [], []
    if base:
        for line in git('diff', '--name-status', base, 'HEAD', '--', f'web/{site}/').splitlines():
            state, name = line.split('\t')[0], line.split('\t')[-1]
            rel = name[len(f'web/{site}/'):]
            if private(rel) or fetchable(rel):
                continue
            (removed if state.startswith('D') else changed).append(rel)
        # Lo que aún no está en un commit también cuenta.
        for line in git('status', '--porcelain', '--', f'web/{site}/').splitlines():
            rel = line[3:].strip().strip('"')[len(f'web/{site}/'):]
            if rel and not private(rel) and not fetchable(rel) and rel not in changed:
                changed.append(rel)
    else:
        changed = [p for p in files if not fetchable(p)]
        out(f'{site}: sin commit publicado registrado; se incluyen todos los archivos no públicos.')
    return differ, sorted(changed), sorted(removed)


def build(site, out=print):
    if site == 'tv.yoma.site':
        check_ready()
    differ, changed, removed = status(site, out)
    files = sorted(set(differ) | set(changed))
    if site == 'tv.yoma.site' and any(f.startswith('releases/') for f in files):
        current = json.loads((WEB / 'tv.yoma.site/private/current.json').read_text(encoding='utf-8'))['release']
        ready = f'releases/{current}/private/ready.json'
        if ready not in files:
            files.append(ready)
    if not files:
        out(f'{site}: el sitio ya coincide con esta carpeta. No hay nada que subir.')
        return None
    head = git('rev-parse', '--short', 'HEAD').strip()
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / f'{site}-{head}.zip'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(files):
            assert not private(name)
            archive.write(WEB / site / name, name)
    out(f'{site}: {len(files)} archivos en {target.relative_to(ROOT)}')
    for name in sorted(files):
        out(f'  + {name}')
    for name in removed:
        out(f'  - {name} (ya no existe aquí; puedes borrarlo del servidor)')
    out('Descomprímelo en htdocs del sitio y después ejecuta: '
        f'python -I tools/web_release.py publicado {site}')
    return target


def health(site, out=print):
    client = Site(site)
    problems = []

    def expect(label, ok):
        out(f"  {'bien' if ok else 'FALLA'}: {label}")
        if not ok:
            problems.append(label)

    if site == 'tv.yoma.site':
        current = json.loads((WEB / site / 'private/current.json').read_text(encoding='utf-8'))['release']
        code, body = client.request('release-health.php')
        data = json.loads(body or b'{}') if code in (200, 503) else {}
        expect(f'release-health.php responde con la versión {current}', code == 200 and data.get('release') == current)
        code, body = client.request('actions.php?action=state')
        expect('actions.php devuelve el estado', code == 200 and b'"csrf"' in body)
    elif site == 'api.yoma.site':
        code, body = client.request('index.php')
        expect('la página de estado indica ok', code == 200 and json.loads(body).get('ok') is True)
        code, body = client.request('yomashi-api.php', b'{"action":"ping"}', {'Content-Type': 'application/json'})
        expect('el puente responde al ping', code == 200 and json.loads(body).get('service') == 'yoma-api')
    else:
        code, body = client.request('')
        expect('la portada responde', code == 200 and b'<html' in body.lower())
    return problems


def main(argv=None):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('accion', choices=['estado', 'paquete', 'publicado'])
    parser.add_argument('sitio', choices=SITES)
    args = parser.parse_args(argv)
    try:
        if args.accion == 'estado':
            differ, changed, removed = status(args.sitio)
            print(f'{args.sitio}: {len(differ)} archivos públicos distintos, {len(changed)} cambiados y '
                  f'{len(removed)} borrados desde lo publicado.')
            for name in differ:
                print(f'  * {name}')
            for name in changed:
                print(f'  + {name}')
            for name in removed:
                print(f'  - {name}')
        elif args.accion == 'paquete':
            build(args.sitio)
        else:
            print(f'Comprobando {args.sitio}…')
            problems = health(args.sitio)
            differ, _, _ = status(args.sitio)
            if differ:
                problems.append('archivos públicos distintos: ' + ', '.join(differ[:5]))
                print('  FALLA: siguen distintos ' + ', '.join(differ[:10]))
            if problems:
                print('No se marca como publicado. Revisa lo anterior y vuelve a subir lo que falte.')
                return 1
            state = deployed()
            state[args.sitio] = git('rev-parse', 'HEAD').strip()
            STATE.write_bytes((json.dumps(state, indent=2, sort_keys=True) + '\n').encode('utf-8'))
            print(f'{args.sitio}: publicado y comprobado. Registrado en web/desplegado.json; haz commit de ese archivo.')
    except ReleaseError as error:
        print(error)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
