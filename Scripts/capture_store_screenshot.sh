#!/bin/bash
# Capture the currently displayed Simulator UI without seeding or changing app data.
set -euo pipefail
if [[ $# -ne 4 || ! "$2" =~ ^(zh-Hans|en-US)$ || ! "$4" =~ ^[a-z0-9-]+$ ]]; then
  echo 'Usage: bash Scripts/capture_store_screenshot.sh SIMULATOR_UDID zh-Hans|en-US OUTPUT_DIRECTORY image-name' >&2
  exit 2
fi
simulator="$1"
locale="$2"
out="$3/$locale"
name="$4"
mkdir -p "$out"
if [[ -e "$out/$name.png" || -e "$out/$name.json" ]]; then
  echo 'Capture already exists; use a new image name or output directory.' >&2
  exit 2
fi
xcrun simctl status_bar "$simulator" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
trap 'xcrun simctl status_bar "$simulator" clear >/dev/null 2>&1 || true' EXIT
xcrun simctl io "$simulator" screenshot --type=png "$out/$name.png"
python3 - "$simulator" "$locale" "$out/$name.json" <<'PY'
import datetime, json, pathlib, subprocess, sys
simulator, locale, output = sys.argv[1:]
root = pathlib.Path(__file__).resolve().parent if '__file__' in globals() else pathlib.Path.cwd()
metadata = {
  'capturedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
  'simulatorUDID': simulator, 'localeExpected': locale,
  'repositoryHead': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
  'repositoryDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True)),
  'devices': json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json'], text=True)),
  'warning': 'Repository HEAD does not prove the installed binary. Record installed app build and package provenance in the capture manifest; manually verify screen language and synthetic data.'
}
pathlib.Path(output).write_text(json.dumps(metadata, indent=2) + '\n')
PY
