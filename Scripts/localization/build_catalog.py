#!/usr/bin/env python3
"""Build the shipped String Catalog from reviewed module translation sources.

Run with --check in CI to detect missing keys, mismatched placeholders and drift.
The JSON modules are editing inputs, never runtime translation dictionaries.
"""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

def catalog():
    strings = {}
    for source in sorted(HERE.glob("*.json")):
        for key, entry in json.loads(source.read_text()).items():
            assert key not in strings, f"Duplicate key: {key} in {source}"
            assert entry['en'].strip() and entry['zh-Hans'].strip(), key
            def placeholders(s):
                return sorted(re.findall(r'%(?:\d+\$)?(?:lld|ld|d|@|f|g)', s))
            # Positions can differ when the grammar requires a different word order.
            def types(s):
                return sorted(re.sub(r'%\d+\$', '%', p) for p in placeholders(s))
            assert types(entry['en']) == types(entry['zh-Hans']), f"Placeholder mismatch: {key}"
            localizations = {lang: unit(entry[lang]) for lang in ('en', 'zh-Hans')}
            if 'enOne' in entry:
                assert types(entry['enOne']) == types(entry['en']), f"Plural mismatch: {key}"
                localizations['en'] = {'variations': {'plural': {'one': unit(entry['enOne']), 'other': unit(entry['en'])}}}
            strings[key] = {'comment': entry.get('comment', key), 'extractionState': 'manual', 'localizations': localizations}
    # Direct calls are audited. Dynamic enum keys are additionally covered by app tests.
    for source in (ROOT / 'Trainote').rglob('*.swift'):
        for key in re.findall(r'L10n\.(?:text|Message|render)\("([^"\\]+)"', source.read_text()):
            assert key in strings, f"Missing key: {key} in {source.relative_to(ROOT)}"
    return {'sourceLanguage': 'en', 'strings': dict(sorted(strings.items())), 'version': '1.0'}

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--check', action='store_true'); args=parser.parse_args()
    result=catalog(); target=ROOT/'Trainote/Resources/Localizable.xcstrings'
    content=json.dumps(result, ensure_ascii=False, indent=2)+'\n'
    if args.check:
        assert target.read_text() == content, 'Regenerate Localizable.xcstrings with build_catalog.py'
    else: target.write_text(content)
    print(f"Validated {len(result['strings'])} bilingual catalog entries")

if __name__ == '__main__': main()
