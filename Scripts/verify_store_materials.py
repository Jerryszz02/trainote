#!/usr/bin/env python3
"""Offline checks for copyable store fields, page links and optional PNG captures."""
import argparse
import re
import struct
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIELD_LIMITS = [
    ('metadata.zh-Hans.md', {'名称': (30, False), '副标题': (30, False), '推广文本': (170, False), '描述': (4000, False), '关键词': (100, True)}),
    ('metadata.en-US.md', {'Name': (30, False), 'Subtitle': (30, False), 'Promotional Text': (170, False), 'Description': (4000, False), 'Keywords': (100, True)}),
    ('review-notes.zh-Hans.md', {'中文 Notes': (4000, True)}),
    ('review-notes.en-US.md', {'Notes': (4000, True)}),
]
# Apple Dynamic Island medium and large portrait sizes, verified 2026-10-26.
MEDIUM = {(1179, 2556), (1206, 2622)}
LARGE = {(1260, 2736), (1290, 2796), (1320, 2868)}


def sections(text):
    result = {}
    for match in re.finditer(r'^## ([^\n]+)\n(.*?)(?=^## |\Z)', text, re.M | re.S):
        result[match[1]] = match[2].strip()
    return result


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links = set(), []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if 'id' in values:
            self.ids.add(values['id'])
        if tag == 'a' and 'href' in values:
            self.links.append(values['href'])


def png_info(path):
    # Inspect PNG chunks directly; no image dependency or image modification.
    with path.open('rb') as stream:
        if stream.read(8) != b'\x89PNG\r\n\x1a\n':
            raise ValueError(f'{path}: not PNG')
        size, alpha = None, False
        while header := stream.read(8):
            if len(header) != 8:
                raise ValueError(f'{path}: truncated PNG')
            length, kind = struct.unpack('>I4s', header)
            data = stream.read(length)
            crc = stream.read(4)
            if len(data) != length or len(crc) != 4:
                raise ValueError(f'{path}: truncated chunk')
            if kind == b'IHDR':
                width, height, _, color, *_ = struct.unpack('>IIBBBBB', data)
                size, alpha = (width, height), color in (4, 6)
            if kind == b'tRNS':
                alpha = True
            if kind == b'IEND':
                break
        if not size:
            raise ValueError(f'{path}: missing IHDR')
        return size, alpha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--screenshots', type=Path)
    args = parser.parse_args()
    errors = []
    for filename, fields in FIELD_LIMITS:
        values = sections((ROOT / 'docs/app-store' / filename).read_text())
        for field, (limit, byte_limit) in fields.items():
            value = values.get(field, '')
            count = len(value.encode('utf-8')) if byte_limit else len(value)
            print(f'{filename} / {field}: {count}/{limit} {"bytes" if byte_limit else "characters"}')
            if not value or count > limit:
                errors.append(f'{filename}: {field} missing or exceeds limit')
    for page in (ROOT / 'docs/index.html', ROOT / 'docs/privacy/index.html', ROOT / 'docs/support/index.html'):
        parsed = Links()
        parsed.feed(page.read_text())
        if page != ROOT / 'docs/index.html' and not {'zh', 'en'} <= parsed.ids:
            errors.append(f'{page}: missing language anchor')
        for href in parsed.links:
            if '://' in href or href.startswith(('mailto:', 'tel:')):
                continue
            target, _, anchor = href.partition('#')
            destination = page if not target else (page.parent / target).resolve()
            if destination.is_dir():
                destination /= 'index.html'
            if not destination.is_file():
                errors.append(f'{page}: missing local link {href}')
                continue
            if anchor:
                linked = Links()
                linked.feed(destination.read_text())
                if anchor not in linked.ids:
                    errors.append(f'{page}: missing anchor {href}')
    for source, bundled in (
        ('Models/QWEN-LICENSE.txt', 'Trainote/Resources/OnDeviceAI/QWEN-LICENSE.txt'),
        ('Packages/TrainoteLlama/LICENSE.txt', 'Trainote/Resources/OnDeviceAI/LLAMA-LICENSE.txt'),
    ):
        if not (ROOT / bundled).is_file() or (ROOT / source).read_bytes() != (ROOT / bundled).read_bytes():
            errors.append(f'{bundled}: missing or differs from source license')
    if args.screenshots:
        for locale in ('zh-Hans', 'en-US'):
            files = sorted(args.screenshots.glob(f'**/{locale}/*.png'))
            sizes = {}
            for file in files:
                try:
                    size, alpha = png_info(file)
                    sizes[size] = sizes.get(size, 0) + 1
                    if size not in MEDIUM | LARGE or alpha:
                        errors.append(f'{file}: invalid portrait size {size} or alpha={alpha}')
                except (ValueError, struct.error) as error:
                    errors.append(str(error))
            if not any(size in MEDIUM for size in sizes):
                errors.append(f'{locale}: missing Dynamic Island medium capture')
            if any(count > 10 for count in sizes.values()):
                errors.append(f'{locale}: more than ten images for a size')
    if errors:
        raise SystemExit('\n'.join(errors))
    print('Store text and local-page checks passed. Public URLs and capture content require separate verification.')


if __name__ == '__main__':
    main()
