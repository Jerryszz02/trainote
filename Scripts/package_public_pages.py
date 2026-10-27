#!/usr/bin/env python3
"""Build a new, allowlisted static Pages directory. Does not deploy or call a network."""
import argparse
import hashlib
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]



def package(destination):
    # Never merge into a directory that may contain stale or unrelated files.
    if destination.exists() or destination.is_symlink():
        raise ValueError('Output must be a new directory; existing paths are not overwritten.')
    if not (ROOT / 'docs/index.html').is_file():
        raise ValueError('Missing source page: index.html')
    for section in ('privacy', 'support'):
        if not (ROOT / 'docs' / section / 'index.html').is_file():
            raise ValueError(f'Missing source page: {section}/index.html')
    destination.mkdir(parents=True)
    shutil.copyfile(ROOT / 'docs/index.html', destination / 'index.html')
    for section in ('privacy', 'support'):
        (destination / section).mkdir()
        shutil.copyfile(ROOT / 'docs' / section / 'index.html', destination / section / 'index.html')
    return sorted(file.relative_to(destination) for file in destination.rglob('*') if file.is_file())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        files = package(args.output.expanduser().absolute())
    except ValueError as error:
        parser.error(str(error))
    for file in files:
        digest = hashlib.sha256((args.output.expanduser().absolute() / file).read_bytes()).hexdigest()
        print(f'{file}  sha256={digest}')
    print('Static artifact only. No Pages settings, publication or deployment was changed.')


if __name__ == '__main__':
    main()
