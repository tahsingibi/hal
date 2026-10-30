#!/usr/bin/env python3
"""Extract L/Lf literal pairs into editable native .strings catalogs.

--write adds missing translations and preserves existing translator edits.
--check validates coverage and printf arguments without modifying resources.
Interpolated strings keep their inline fallback; prefer Lf for new dynamic copy.
"""
import argparse
import collections
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
PAIR = re.compile(r'\bL(?:f)?\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"', re.S)
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(ll|l|z)?([@diuoxXfFeEgGcs])')


def decode(raw):
    raw = re.sub(r'\\u\{([0-9a-fA-F]+)\}', lambda m: chr(int(m[1], 16)), raw)
    return json.loads('"' + raw + '"')


def arguments(value):
    value = value.replace('%%', '')
    return sorted((position or str(i + 1), length or '', kind) for i, (position, length, kind) in enumerate(FORMAT.findall(value)))


def read_strings(path):
    if not path.exists():
        return {}
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    pairs = collections.defaultdict(set)
    for source in sorted((ROOT / 'Sources').rglob('*.swift')):
        for tr, en in PAIR.findall(source.read_text()):
            if '\\(' not in tr + en:
                pairs[decode(en)].add(decode(tr))
    expected = {'tr': {}, 'en': {}}
    for en, translations in pairs.items():
        for tr in translations:
            key = en if len(translations) == 1 else en + ' | ' + tr
            expected['tr'][key] = tr
            expected['en'][key] = en
    errors = []
    for language, entries in expected.items():
        path = ROOT / 'Resources' / (language + '.lproj') / 'Localizable.strings'
        actual = read_strings(path)
        if args.write:
            merged = {key: actual.get(key, value) for key, value in entries.items()}
            path.parent.mkdir(parents=True, exist_ok=True)
            quote = lambda value: json.dumps(value, ensure_ascii=False)
            path.write_text('/* Hâl — ' + language + '. Translator edits are preserved by localize.py --write. */\n\n' + '\n'.join(quote(key) + ' = ' + quote(value) + ';' for key, value in sorted(merged.items())) + '\n')
            actual = read_strings(path)
        for key, value in entries.items():
            if key not in actual:
                errors.append(f'{language}: missing {key!r}')
            elif arguments(value) != arguments(actual[key]):
                errors.append(f'{language}: format arguments differ for {key!r}')
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        print('Run python3 scripts/localize.py --write to add missing entries.', file=sys.stderr)
        return 1
    print(f'Localization verified: {len(expected["en"])} entries × 2 languages; printf arguments match.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
