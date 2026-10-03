"""Generate an ignored standalone UI harness; never changes the production app entry point."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--xcodegen', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
output = root / 'build/recovery-preview'
output.mkdir(parents=True, exist_ok=True)
# Reuse the exact current persistence declaration while excluding the production @main App.
app = (root / 'Trainote/App/TrainoteApp.swift').read_text()
persistence = 'import Foundation\nimport SwiftData\n' + app[app.index('enum PersistenceController'):app.index('private struct PersistenceErrorView')]
(output / 'PersistenceController.swift').write_text(persistence)
project = {
    'name': 'TrainoteRecoveryPreview',
    'options': {'deploymentTarget': {'iOS': '17.0'}, 'developmentLanguage': 'zh-Hans'},
    'settings': {'base': {'SWIFT_VERSION': '5.9', 'TARGETED_DEVICE_FAMILY': '1'}},
    'targets': {
        'TrainoteRecoveryPreview': {
            'type': 'application', 'platform': 'iOS',
            'sources': [
                {'path': str(root / 'Trainote'), 'excludes': ['App/TrainoteApp.swift', 'Resources']},
                {'path': str(root / 'Trainote/Resources'), 'buildPhase': 'resources'},
                {'path': str(output / 'PersistenceController.swift')},
                {'path': str(root / 'TrainoteTests/RecoveryFixtures/RecoveryPreview.swift')},
            ],
            'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'com.jerryszz.trainote.recovery-preview',
                'GENERATE_INFOPLIST_FILE': True, 'INFOPLIST_KEY_UILaunchScreen_Generation': True,
                'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) RECOVERY_PREVIEW'}},
            'scheme': {'testTargets': ['RecoveryPageUITests']},
        },
        'RecoveryPageUITests': {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(root / 'TrainoteTests/RecoveryFixtures/RecoveryPageUITests.swift')}],
            'dependencies': [{'target': 'TrainoteRecoveryPreview'}],
            'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'com.jerryszz.trainote.recovery-preview.tests',
                'GENERATE_INFOPLIST_FILE': True, 'TEST_TARGET_NAME': 'TrainoteRecoveryPreview',
                'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) RECOVERY_PREVIEW_TESTS'}},
        },
    },
}
(output / 'project.json').write_text(json.dumps(project, indent=2))
subprocess.run([args.xcodegen, 'generate', '--spec', str(output / 'project.json')], check=True)
