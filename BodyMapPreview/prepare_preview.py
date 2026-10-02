#!/usr/bin/env python3
"""Generate an isolated preview project under ignored build/, without editing project.yml/pbxproj."""
import argparse
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--xcodegen", default=str(root / ".xcodegen/xcodegen/bin/xcodegen"))
args = parser.parse_args()
out = root / "build/body-map/preview"
out.mkdir(parents=True, exist_ok=True)


def source(path):
    return str(root / path)


spec = {
    "name": "BodyMapPreview",
    "options": {"deploymentTarget": {"iOS": "17.0"}, "developmentLanguage": "zh-Hans"},
    "settings": {"base": {"SWIFT_VERSION": "5.9", "TARGETED_DEVICE_FAMILY": "1",
                          "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGNING_ALLOWED": "NO"}},
    "targets": {
        "BodyMapPreview": {
            "type": "application", "platform": "iOS",
            "sources": [source("BodyMapPreview/App.swift"), source("BodyMapPreview/PerformanceProbe.swift"),
                        source("Trainote/Features/Recovery/BodyMap"),
                        source("Trainote/Services/Analysis/Contracts/BodyMapPresentation.swift"),
                        source("Trainote/Services/Analysis/Contracts/BodyMapFixtures.swift"),
                        {"path": source("Trainote/Resources/BodyMap/body-map-v1.json"), "buildPhase": "resources"}],
            "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "com.jerryszz.trainote.bodymap-preview",
                                  "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                                  "INFOPLIST_KEY_CFBundleDisplayName": "BodyMap Preview"}},
            "scheme": {"testTargets": ["BodyMapTests", "BodyMapUITests"]},
        },
        "BodyMapTests": {
            "type": "bundle.unit-test", "platform": "iOS",
            "sources": [source("TrainoteTests/BodyMapTests.swift")],
            "dependencies": [{"target": "BodyMapPreview"}],
            "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "com.jerryszz.trainote.bodymap-preview.tests",
                                  "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) BODY_MAP_PREVIEW"}},
        },
        "BodyMapUITests": {
            "type": "bundle.ui-testing", "platform": "iOS",
            "sources": [source("BodyMapPreview/Tests")],
            "dependencies": [{"target": "BodyMapPreview"}],
            "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "com.jerryszz.trainote.bodymap-preview.uitests",
                                  "TEST_TARGET_NAME": "BodyMapPreview"}},
        },
    },
}
path = out / "preview-spec.json"
path.write_text(json.dumps(spec, indent=2) + "\n")
subprocess.run([args.xcodegen, "generate", "--spec", str(path)], check=True)
print(out / "BodyMapPreview.xcodeproj")
