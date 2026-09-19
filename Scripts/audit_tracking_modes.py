#!/usr/bin/env python3
"""Generate/recheck the explicit, reviewed default mode for every bundled exercise."""
import argparse
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Continuous locomotion uses time/distance; cardio-category calisthenics use reps.
CARDIO = {'0685', '0684', '3656', '2138', '0798', '2141', '3666', '2311', '2331'}
STATIC = {'3544', '2135', '3297', '3303', '3299', '3301', '1297', '3665',
          '0020', '3302', '3419', '3300', '3298', '3296', '3315', '3314',
          '0705', '1362', '1366', '3420', '1338', '1355'}
DYNAMIC = {'0464', '3239', '0664', '3663', '1775', '3664', '0500'}
WEIGHTED = {'barbell', 'dumbbell', 'kettlebell', 'cable', 'smith machine', 'leverage machine',
            'ez barbell', 'olympic barbell', 'trap bar', 'weighted', 'sled machine',
            'medicine ball', 'tire', 'hammer'}

def mode(item):
    key, name = item['id'], item['nameEn'].lower()
    if key in CARDIO:
        return 'cardio'
    if key in STATIC or ('stretch' in name and key not in DYNAMIC) or any(
        word in name for word in ['yoga pose', 'wide angle pose', 'reclining big toe pose']
    ):
        return 'duration'
    if item['equipment'] in WEIGHTED:
        return 'strength'
    return 'repetitions'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    exercises = json.loads((ROOT / 'Trainote/Resources/ExerciseCatalog.json').read_text())['exercises']
    expected = {item['id']: mode(item) for item in exercises}
    assert len(exercises) == len(expected) == 1324
    path = ROOT / 'Trainote/Resources/ExerciseTrackingModes.json'
    if args.write:
        path.write_text(json.dumps(expected, indent=2, sort_keys=True) + '\n')
    else:
        assert json.loads(path.read_text()) == expected, 'Tracking-mode audit is stale'
    assert expected['0025'] == 'strength'
    assert expected['0630'] == expected['1374'] == 'repetitions'
    assert expected['2135'] == expected['1708'] == 'duration'
    assert expected['0464'] == expected['3295'] == 'repetitions'
    assert all(expected[key] == 'duration' for key in ['0020', '3302', '3419', '3296', '0705'])
    assert expected['3664'] == expected['1201'] == 'strength'
    assert expected['0685'] == 'cardio'
    print(json.dumps({'total': len(expected), 'modes': dict(Counter(expected.values()))}, ensure_ascii=False))

if __name__ == '__main__':
    main()
