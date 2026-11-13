"""Convierte cada prueba fallida de Flutter en un aviso de GitHub Actions.

    flutter test --file-reporter json:build/test-report.json
    python3 -I tools/report_failed_tests.py build/test-report.json

Los avisos se ven en la ejecución sin abrir el registro completo.
"""
import json
import sys
from pathlib import Path


def failures(lines):
    suites, tests, errors, out = {}, {}, {}, []
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        kind = event.get('type')
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite'].get('path') or ''
        elif kind == 'testStart':
            test = event['test']
            tests[test['id']] = (test['name'], suites.get(test.get('suiteID'), ''))
        elif kind == 'error':
            errors.setdefault(event['testID'], event.get('error', ''))
        elif kind == 'testDone' and not event.get('hidden') and event.get('result') != 'success':
            name, path = tests.get(event['testID'], ('(prueba desconocida)', ''))
            out.append((path, name, errors.get(event['testID'], '')))
    return out


def main(argv):
    report = Path(argv[1] if len(argv) > 1 else 'build/test-report.json')
    if not report.is_file():
        print(f'No hay informe de pruebas en {report}.')
        return 0
    found = failures(report.read_text(encoding='utf-8', errors='replace').splitlines())
    for path, name, error in found:
        relative = path.replace('\\', '/')
        for folder in ('/integration_test/', '/test/'):
            if folder in relative:
                relative = relative[relative.rindex(folder) + 1:]
                break
        detail = ' '.join(str(error).split())[:300]
        print(f'::error file={relative},title=Prueba fallida::{name} — {detail}')
    print(f'Pruebas fallidas: {len(found)}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
