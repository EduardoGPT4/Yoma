"""Copia los tokens de diseño de la app (lib/design/yoma_tokens.dart) a la web.

Escribe en cada hoja de estilo de web/ un bloque `--yoma-*` con los mismos
nombres que en Flutter (background → --yoma-background, surfaceHigh →
--yoma-surface-high, radios → --yoma-radius-*). Los nombres propios de cada
sitio (--bg, --surface2, --muted…) apuntan a ese bloque.

    python -I tools/generate_web_tokens.py           # escribe
    python -I tools/generate_web_tokens.py --check   # solo comprueba

test/unit/yoma_web_tokens_test.dart comprueba lo mismo en `flutter test`.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOKENS = ROOT / 'lib/design/yoma_tokens.dart'
SHEETS = [
    ROOT / 'web/yoma.site/style.css',
    ROOT / 'web/shi.yoma.site/style.css',
    ROOT / 'web/tv.yoma.site/releases/yoma-design-20261111-1/assets/yoma.css',
]
START = '/* yoma-tokens:start · generado por tools/generate_web_tokens.py desde lib/design/yoma_tokens.dart; no editar a mano */'
END = '/* yoma-tokens:end */'


def kebab(name: str) -> str:
    return re.sub(r'(?<=[a-z0-9])([A-Z])', r'-\1', name).lower()


def section(source: str, name: str) -> str:
    match = re.search(r'abstract final class ' + name + r' \{(.*?)\n\}', source, re.S)
    if not match:
        raise SystemExit(f'No se encontró {name} en {TOKENS}')
    return match.group(1)


def block() -> str:
    source = TOKENS.read_text(encoding='utf-8')
    lines = [':root {']
    for name, value in re.findall(r'static const (\w+) = Color\(0x([0-9A-Fa-f]{8})\);', section(source, 'YomaColors')):
        lines.append(f'  --yoma-{kebab(name)}: #{value[2:].lower()};')
    for name, value in re.findall(r'static const double (\w+) = ([0-9.]+);', section(source, 'YomaRadii')):
        lines.append(f'  --yoma-radius-{kebab(name)}: {float(value):g}px;')
    lines.append('}')
    return START + '\n' + '\n'.join(lines) + '\n' + END + '\n'


def apply(text: str, generated: str) -> str:
    if START in text and END in text:
        before = text[:text.index(START)]
        after = text[text.index(END) + len(END):].lstrip('\n')
        return before + generated + '\n' + after
    return generated + '\n' + text


def main() -> int:
    generated = block()
    stale = []
    for sheet in SHEETS:
        current = sheet.read_text(encoding='utf-8')
        updated = apply(current, generated)
        if updated != current:
            stale.append(sheet.relative_to(ROOT).as_posix())
            if '--check' not in sys.argv:
                sheet.write_text(updated, encoding='utf-8', newline='')
    if '--check' in sys.argv and stale:
        print('Tokens desactualizados en:', ', '.join(stale))
        return 1
    print('Actualizados:' if stale else 'Al día.', ', '.join(stale))
    return 0


if __name__ == '__main__':
    sys.exit(main())
