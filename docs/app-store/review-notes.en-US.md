# App Review notes candidate

October 27, 2026 · Review-notes candidate, not submitted. On-device reports and first use are implemented; unsigned Release archiving and local regression checks passed. Physical-device checks remain pending. Copy only the Notes section for submission. No sign-in or review account is needed. The user supplies private review contact details in App Store Connect.

## Notes

Trainote is an offline workout and meal log in English and Simplified Chinese. No account, payment, server or model download is required. Apple Health is an optional, read-only connection; manual recording works without it.

Review steps:
1. On first launch, select a language and read the notice. Not Now keeps the app in a restricted view. Agree and Continue opens the app without requesting HealthKit access or starting AI inference.
2. Start an empty workout from Training, add an exercise, record results and finish. Record a meal from Nutrition. Settings offers JSON export and restore.
3. Open reports from Today. A rule-based report appears first. Choose Generate on-device AI report to load bundled Qwen3-0.6B and generate locally, or cancel. Date changes, ordinary refresh and foregrounding do not start inference. Failures show the rule-based report.
4. Sources distinguish rules from on-device AI. The model selects facts and allowed suggestions already calculated by code; it does not provide medical diagnoses. Reading does not apply suggestions. Changing targets or starting workouts requires explicit confirmation.
5. Turn off Allow on-device AI reports in Settings. Generation stops; manual recording and rules remain available. Report history can be deleted separately.
6. View or withdraw notice acknowledgment in Settings. Withdrawal returns to the restricted view, which supports export, deletion and clearing Health imports. It does not delete all records, change the AI preference or revoke system Health permission.
7. Connect Apple Health separately to open system authorization. Disconnect and delete removes imported caches and dependent reports while retaining manual records and original Apple Health data.

Processing: No advertising, tracking or telemetry. Reports do not contact cloud AI. Qwen3-0.6B and llama.cpp are bundled. Manual records stay on device. Optional Health imports are pruned to 90 days at the next sync and excluded from backups. Report history, notice acknowledgment and permissions are excluded from exported business backups. The privacy policy explains system backups, user exports and external support links separately.

Scope: Everyday fitness information for healthy adults, not medical diagnosis or treatment. Suggestions should not be assumed suitable for children or people with special health needs. Recovery indicators are not a percentage recovered or injury probability. Limited evidence may produce unknown results. AI may miss relevant details.

Rights: Exercise data, anatomy illustrations and the offline push-up demonstration retain their source and license notices in the app. Dataset exercise images/GIFs are not distributed. Bundled notices identify the model and engine versions and licenses.

Public support and privacy email: [shen20060206@163.com](mailto:shen20060206@163.com). The user will supply the private App Review contact name and phone number in App Store Connect.

## Verification boundary

The [implementation evidence](on-device-implementation.md) records unsigned Release archiving, bundled model/license checks, a 348/348 local regression snapshot and 8 UI tests on the large-display iPhone 17 Pro Max Simulator at default text size. After the final English copy fixes, 13 affected unit tests and 6 screenshot scenarios passed on each of two simulators (38 runs). Public privacy/support pages were published and verified. All 28 bilingual screenshots have been recaptured and visually checked; final store selection remains with the publisher. This text is not evidence of physical-device, performance, professional or review acceptance. Check the [release checklist](release-checklist.md). If the real model is absent, offline generation fails or a feature is disabled, update these notes before submission.
