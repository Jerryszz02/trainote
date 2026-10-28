#!/usr/bin/env python3
"""Xcode build phase: verified model is an offline app resource, never fetched here."""
import hashlib, json, os, pathlib, shutil, sys
root=pathlib.Path(os.environ['SRCROOT'])
m=json.loads((root/'Models/manifest.json').read_text())['model']
source=root/'Models'/m['filename']
destination=pathlib.Path(os.environ['TARGET_BUILD_DIR'])/os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH']/m['filename']
if not source.exists():
    if os.environ.get('TRAINOTE_RULES_ONLY_BUILD')=='YES':
        if destination.exists(): destination.unlink()
        print('Explicit rules-only development build: no bundled model.')
        sys.exit(0)
    sys.exit('error: Missing on-device model. Run Scripts/on-device-ai/prepare.py before Release builds.')
h=hashlib.sha256()
with source.open('rb') as f:
    for chunk in iter(lambda:f.read(8*1024*1024),b''): h.update(chunk)
if h.hexdigest()!=m['sha256']: sys.exit('error: On-device model SHA-256 mismatch')
destination.parent.mkdir(parents=True,exist_ok=True)
shutil.copyfile(source,destination)
print('Verified and bundled',m['filename'])
