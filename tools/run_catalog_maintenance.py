"""Avanza la cola del catálogo de tv.yoma.site llamando a maintenance.php.

La usa la tarea programada «Mantenimiento del catálogo» de GitHub
(.github/workflows/catalog-maintenance.yml). Cada llamada procesa un trabajo:
revisar el horario (cada 12 horas), leer el listado de capítulos de un anime o
recorrer una página del directorio.

    YOMA_MAINTENANCE_TOKEN=<token> python -I tools/run_catalog_maintenance.py --steps 12

- El token se genera en la web (Administración → Actualización externa) y solo
  se lee de la variable de entorno. Nunca se imprime.
- Resuelve la comprobación de JavaScript de InfinityFree (cookie __test), igual
  que la app.
- Sin token no hace nada y termina bien, para que la tarea no falle mientras no
  esté configurada.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_URL = 'https://tv.yoma.site/maintenance.php'
USER_AGENT = 'Mozilla/5.0 Yoma catalog maintenance'


class MaintenanceError(Exception):
    pass


def allowed_url(url):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme == 'https' and parts.hostname == 'tv.yoma.site':
        return True
    # Solo para las pruebas: un servidor en este mismo equipo.
    return parts.scheme == 'http' and parts.hostname == '127.0.0.1'


def aes_decrypt_hex(key, iv, cipher):
    """AES-128-CBC sin relleno, como el slowAES de la comprobación del alojamiento."""
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    except ImportError:
        openssl = shutil.which('openssl')
        if not openssl:
            raise MaintenanceError('Falta openssl para resolver la comprobación del alojamiento.')
        result = subprocess.run([openssl, 'enc', '-d', '-aes-128-cbc', '-K', key, '-iv', iv, '-nopad'],
                                input=bytes.fromhex(cipher), capture_output=True, timeout=20)
        if result.returncode != 0:
            raise MaintenanceError('No se pudo resolver la comprobación del alojamiento.')
        return result.stdout.hex()
    decryptor = Cipher(algorithms.AES(bytes.fromhex(key)), modes.CBC(bytes.fromhex(iv))).decryptor()
    return (decryptor.update(bytes.fromhex(cipher)) + decryptor.finalize()).hex()


class Runner:
    def __init__(self, url, token):
        if not allowed_url(url):
            raise MaintenanceError('Dirección de mantenimiento no permitida.')
        self.url = url
        self.token = token
        self.cookie = ''

    def call(self):
        """Un paso de mantenimiento: (estado HTTP, respuesta JSON)."""
        for _ in range(3):
            headers = {'User-Agent': USER_AGENT, 'Content-Type': 'application/json', 'Accept': 'application/json',
                       'Authorization': 'Bearer ' + self.token}
            if self.cookie:
                headers['Cookie'] = '__test=' + self.cookie
            request = urllib.request.Request(self.url, data=b'{}', headers=headers, method='POST')
            try:
                response = urllib.request.urlopen(request, timeout=90)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                status, body = response.status, response.read(2 * 1024 * 1024)
            if b'slowAES.decrypt' in body:
                values = re.findall(r'toNumbers\("([a-fA-F0-9]+)"\)', body.decode('utf-8', 'replace'))
                if len(values) != 3:
                    raise MaintenanceError('El alojamiento cambió su comprobación.')
                self.cookie = aes_decrypt_hex(*values)
                if not re.fullmatch('[a-f0-9]{32}', self.cookie):
                    raise MaintenanceError('El alojamiento devolvió una comprobación no válida.')
                continue
            try:
                return status, json.loads(body)
            except ValueError:
                raise MaintenanceError(f'Respuesta no válida del servidor (HTTP {status}).')
        raise MaintenanceError('No se pudo superar la comprobación del alojamiento.')


def problem(message, out=print):
    """Un fallo. En GitHub Actions también va a los avisos de la ejecución,
    que se ven sin abrir el registro. Los mensajes nunca contienen el token."""
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        out('::error title=Mantenimiento del catálogo::' + ' '.join(message.split()))
    out(message)


def describe(result):
    if result.get('skipped'):
        return f"sin trabajo: {result.get('reason', '')}".strip()
    if result.get('updated_slug'):
        return f"listado actualizado: {result['updated_slug']}"
    if result.get('failed_slug'):
        return f"falló (queda en cola): {result['failed_slug']}"
    if 'anime' in result:
        return f"horario revisado: {result['anime']} animes"
    if result.get('updated_kind'):
        return f"directorio: {result['updated_kind']}"
    if result.get('restarted'):
        return 'directorio: se reinició una partición'
    return 'paso completado'


def run(runner, steps, pause, sleep=time.sleep, out=print):
    """Devuelve 0 si todo fue bien; 1 si el servidor rechazó el acceso o no respondió."""
    done = 0
    for step in range(1, steps + 1):
        try:
            status, data = runner.call()
        except (OSError, MaintenanceError) as error:
            problem(f'Paso {step}: {error}', out)
            return 1
        if status in (401, 403, 405) or not data.get('ok'):
            problem(f"Paso {step}: el servidor no aceptó el mantenimiento (HTTP {status}): {data.get('message', '')}", out)
            return 1
        result = data.get('result') or {}
        remaining = result.get('remaining')
        out(f"Paso {step}: {describe(result)}" + (f' · pendientes: {remaining}' if remaining is not None else ''))
        done += 1
        if result.get('skipped') and not remaining:
            break
        if step < steps:
            sleep(pause)
    out(f'Pasos realizados: {done}.')
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--steps', type=int, default=12, help='trabajos por ejecución (1–40)')
    parser.add_argument('--pause', type=float, default=3.0, help='segundos entre trabajos')
    args = parser.parse_args(argv)
    token = os.environ.get('YOMA_MAINTENANCE_TOKEN', '').strip()
    if not token:
        print('Sin YOMA_MAINTENANCE_TOKEN: no se hace nada.')
        return 0
    if not re.fullmatch('[a-f0-9]{64}', token):
        problem('YOMA_MAINTENANCE_TOKEN no tiene el formato esperado: pega solo los 64 caracteres '
                'del token, sin «Authorization: Bearer».')
        return 1
    steps = max(1, min(40, args.steps))
    try:
        runner = Runner(os.environ.get('YOMA_MAINTENANCE_URL') or DEFAULT_URL, token)
    except MaintenanceError as error:
        problem(str(error))
        return 1
    return run(runner, steps, max(2.5, args.pause))


if __name__ == '__main__':
    sys.exit(main())
