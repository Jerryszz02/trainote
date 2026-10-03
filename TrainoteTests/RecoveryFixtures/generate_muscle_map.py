"""Reproduce the conservative v0 mapping. Only the explicit reviewed IDs are enabled.

Review is of text/engineering scope, not professional or EMG validation. Other catalog
variants remain pending, even when their target strings match. Never edit upstream data.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = json.loads((ROOT / 'Trainote/Resources/ExerciseCatalog.json').read_text())
modes = json.loads((ROOT / 'Trainote/Resources/ExerciseTrackingModes.json').read_text())
# Common movement text and instructions reviewed against the pinned catalog.
# Explicit primary/secondary choices below override misleading generic target fields.
REVIEWED = {
    '0025': ('chest', 'triceps shoulders'), '0027': ('back', 'biceps forearms'),
    '0031': ('biceps', 'forearms'), '0032': ('glutes hamstrings', 'back quads forearms'),
    '0033': ('chest', 'triceps shoulders'), '0042': ('quads glutes', 'core'),
    '0043': ('quads glutes', 'core'), '0047': ('chest', 'shoulders triceps'),
    '0054': ('quads glutes', 'hamstrings'), '0085': ('hamstrings glutes', 'back forearms'),
    '1372': ('calves', ''), '0126': ('forearms', ''), '0125': ('forearms', ''),
    '1411': ('forearms', ''), '1412': ('forearms', ''), '0079': ('forearms', ''),
    '0082': ('forearms', ''), '0104': ('forearms', ''),
    '0178': ('shoulders', 'back'), '0201': ('triceps', ''),
    '0861': ('back', 'biceps forearms'), '1326': ('back biceps', 'forearms'),
    '0267': ('core', ''), '0289': ('chest', 'triceps shoulders'),
    '0294': ('biceps', 'forearms'), '0308': ('chest', 'shoulders'),
    '1760': ('quads glutes', 'core'), '0313': ('biceps', 'forearms'),
    '0314': ('chest', 'shoulders triceps'), '0334': ('shoulders', 'back'),
    '1379': ('calves', ''), '0405': ('shoulders', 'triceps'),
    '0585': ('quads', ''), '0586': ('hamstrings', 'calves'),
    '0599': ('hamstrings', 'calves'), '0652': ('back', 'biceps forearms'),
    '0662': ('chest', 'triceps shoulders core'), '0770': ('quads glutes', 'core'),
}
entries = []
for row in sorted(source['exercises'], key=lambda r: r['id']):
    key = row['id']
    primary, secondary = [], []
    if key in REVIEWED:
        primary, secondary = [part.split() for part in REVIEWED[key]]
        status, reason = 'mapped', 'reviewed-common-movement-v0'
    elif modes[key] in ('duration', 'cardio') or row['bodyPart'] == 'cardio' or 'stretch' in row['nameEn']:
        status, reason = 'notApplicable', 'no-resistance-set-conversion'
    else:
        status, reason = 'pendingReview', 'movement-variant-not-reviewed'
    entries.append(dict(exerciseID=key, name=row['nameEn'], status=status,
                        primary=primary, secondary=secondary, reason=reason))
assert len(entries) == 1324 and len({x['exerciseID'] for x in entries}) == 1324
assert set(REVIEWED) <= {x['exerciseID'] for x in entries}
document = dict(version='exercise-muscles-v0.1', catalogCommit=source['source']['commit'],
                review='Engineering text review only; no professional or EMG validation.', entries=entries)
header = {key: value for key, value in document.items() if key != 'entries'}
text = json.dumps(header, ensure_ascii=False, indent=2)[:-2] + ',\n  "entries": [\n'
text += ',\n'.join('    ' + json.dumps(row, ensure_ascii=False, separators=(',', ': ')) for row in entries)
text += '\n  ]\n}\n'
(ROOT / 'Trainote/Resources/ExerciseMuscleMap.json').write_text(text)
from collections import Counter
print(dict(Counter(e['status'] for e in entries)))
