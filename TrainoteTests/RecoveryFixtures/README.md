# Recovery C handoff

Based on official `main` at `b24cd108222134d3cd3ba1d4169031cebc6226b3`, incorporated by an ordinary two-parent merge after the foundation PR was merged. PR #8 targets `main`; the temporary foundation branch is no longer its base. This module does not wire AppShell, Settings, AI transport, the shared schema or D's renderer. F owns production navigation and candidate generation.

## Consumer assembly

```swift
let control = RecoveryCalibrationControl()
let recovery = try RecoveryService(calibration: control)
// Within the parent's NavigationStack:
RecoveryView(repository: foundation.repository, healthData: foundation.healthData,
             calculator: recovery, onShowMethods: { /* F's offline methods page */ },
             resetCalibration: { control.reset(at: .now) })
```

`RecoveryService: RecoveryCalculating` reads the current local reset boundary and calls the pure `RecoveryCalculator(mapping:calibrationResetAt:)`. Pass the service to A's `ReportSnapshotBuilder` so **each new report** recalculates from its newly read snapshot; never pass an old result to a report generator. Use the same service/control for the UI and reports. A module load failure should show an analysis-unavailable state without interrupting recording.

Request 90 days of input for calibration; current muscle scores use the most recent 28 days. The repository also reads manual check-ins within the requested window. `RecoveryResult` and `BodyMapPresentation` are A's formal types; `result.bodyMapPresentation(selected:)` is the renderer adapter. Nil is unknown. Untrained muscles never inherit another muscle's score or receive a synthetic 100.

F's candidate rules must exclude a muscle when `hasPain || hasMovementLimitation` regardless of score, and consider `significantSoreness` an instruction to reduce local volume. The feedback constraint persists within the supplied manual record history until explicitly answered false; nil never clears it. F can read influence codes, coverage and `systemicState` without parsing localized UI labels. Unknown local load must not become an unrestricted keep-plan candidate. This module does not create or mutate recommended workout plans.

Facts:
- `recovery.<muscle>.score`: unrounded readiness; `load`: residual weighted sets; `lastLoad`: latest session weighted sets; `tau`: seconds.
- `recovery.unallocatedRecords`: workout records with invalid/unreviewed/unsupported set data or unallocated external resistance activity. Any such workout in the 28-day local window makes complete local readiness unknown. Known load facts remain inspectable.
- `recovery.<muscle>.soreness`: 0 none / 1 mild / 2 significant; `pain`, `movementLimitation`: 0 false / 1 true. A missing fact means unanswered, never false.
- `recovery.feeling` / `sleepFeeling`: 0 tired/poor, 1 normal, 2 good; optional.
- `recovery.systemic.<metric>.latest/baseline/deviationPercent/sustainedDeviation`; sleep also has `endTimeShift` in seconds. The latter compares sleep-window end times, not sleep architecture.
- `recovery.systemic.externalWorkout`: most recent imported workout duration in seconds, with duplicate/coverage quality. It is activity context and never creates muscle sets.

Every derived fact carries raw manual/sample dependencies or resolvable `metricFact` dependencies. Baseline/latest/deviation facts include all selected source samples, not just today's. HRV/sleep never subtract from local muscle scores. Imported resistance/core/cross-training with no confirmed local set association makes local readiness unknown and excludes affected calibration pairs; those coverage dependencies are retained too. The reset boundary is reflected in calculationVersion to invalidate derived report reuse.

### Existing DTO limits and suggested single-owner follow-up

The foundation currently encodes HRV/RHR date, source, product, definition and context in stable fact IDs (`health.<metric>.<date>|<source>|<product>|<definition>|<context>`). C groups by the full suffix and source version, never combines definitions/devices/contexts, and refuses to establish a shared baseline from an unknown ID shape. Suggested A-owned future DTO improvement: optional explicit `seriesID` or typed `definition/productType/measurementContext` on MetricFact, then coordinate consumers. C does not define a competing shared model.

The model can only distinguish equipment/technique using the existing catalog ID and tracking mode. Calibration additionally fixes set order, exact weight and RIR; actual machine identity/tempo/technique changes are not measured. No claim of validated comparability or physiological accuracy is made.

## P parameters and evidence boundary

The source plan section 7 formula is unchanged: primary 1, secondary 0.5, same muscle uses max; RIR 0/1/2/3/4/5+ = 1.25/1.15/1.05/1/0.85/0.70; missing RIR = 1 with quality flag; unknown historical role = working prior; warmups excluded. F = sum(load × exp(-hours/tau)); R = 100 × exp(-F/6); tau starts at 36 h. Raw score is preserved, displayed rounded to 5; displayed 80+ ready, 50–75 moderate, below 50 low. Soreness can cap the state; pain/limitation overrides state and color without rewriting the base score.

Additional explicit v0 engineering choices, requiring coordinator/professional review before release:
- A recent local window is 28 days; absent local history is unknown. Invalid completed sessions and unsupported/unreviewed movements create a coverage gap, never zero load.
- Whole-body baseline: at least 14 distinct valid days in the 28 days before the latest observation, excluding the latest three evaluation days. Source/product/definition/context/version streams stay separate; latest must be today/yesterday. Three consecutive days of sleep <85%, RHR >110% or HRV <80% of baseline plus current subjective fatigue gives systemic low. A one-day deviation alone never lowers a muscle score.
- Calibration requires at least **6 fit pairs plus 4 later holdout pairs**. It uses later repetitions at the same catalog ID, strength mode, set order, exact weight and RIR 0–4 relative to the preceding three comparable performances; no e1RM formula, changed mode, missing RIR, unknown set role or duration conversion. Pretraining feedback within 24 h must answer soreness, pain=false and limitation=false. Multiple sets in one workout form one pair. Unallocated preceding training excludes calibration.
- The most recent four outcomes are never used to select the fitted candidate in that evaluation. Holdout MSE must improve by at least 5% and more than 1 squared point versus both 36 h and the current parameter. Evaluate at most once per 7 days, change tau at most 10%, clamp 24–72 h. Replaying current input makes edits/deletions invalidate parameters. Synthetic tests verify gates, not forecasting accuracy.
- Reset stores only a versioned timestamp in UserDefaults, no derived values. `control.reset(at:)` excludes earlier observations/load from calibration only; raw training and base readiness remain. `control.clear()` is the hook for delete-all. There is no persisted health-dependent calibration/cache to register for disconnect. Eligibility uses currently supplied external-training coverage, so each new report must recompute; any future persisted health-dependent derivative would require A's invalidator hook.

All parameters are engineering initial values. Main/secondary weights are not EMG ratios; scores are not measured tissue recovery. F's methods/help flow should present these boundaries rather than repeating disclaimers in every daily row.

## Mapping

`generate_muscle_map.py` reproduces `ExerciseMuscleMap.json` from the pinned MIT text catalog without changing it. All 1,324 IDs are explicit: **38 mapped common movements, 1,175 pending review, 111 not applicable**. The 38 were checked against pinned names/instructions at the coarse 11-muscle level; this is engineering text review, not professional anatomical/biomechanical validation. Complex/unreviewed variants remain unknown rather than inheriting a mapping by a matching word. Common compound movements have explicit overrides (e.g. squat quads+glutes); unsupported or stabilizer targets are not forced into an unrelated muscle.

Expand the explicit reviewed table and regenerate only after reviewing each added movement. Status, support scope and this count are intentionally visible. Duration/cardio/stretch modes have no conversion to resistance sets. External aggregate strength duration also never becomes sets. A possible duplicate ID is not a confirmed association, so v0 keeps an external resistance record as a coverage gap even when it may overlap a local workout. A future confirmed-association contract must have one shared owner.

## Verification

Test fixtures are synthetic. Dedicated Simulator: `56CCDE13-528E-4012-AABA-D0559816F5AB` (Trainote Recovery C, iOS 26.5). DerivedData: `/tmp/trainote-recovery-c-derived`; Xcode 26.6. After merging official `main` at `b24cd108222134d3cd3ba1d4169031cebc6226b3`, the Simulator Debug build, **57 focused unit tests and 4 UI tests** passed with 0 failures: `/tmp/trainote-recovery-c-main-b24cd10-focused.xcresult` (matching `.log`). The selected suites cover all recovery calculations/workflows, training factories, BodyMap teardown, durable consent and recommendation snapshots; the UI tests cover RIR/history/repeat plus the existing repeated-workout, bodyweight/duration and cardio-confirmation regressions. The regenerated standalone recovery preview also passed **3 UI tests** with 0 failures: `/tmp/trainote-recovery-c-main-b24cd10-preview.xcresult` (matching `.log`), including clearing the only answer, body rendering/selection, pain override, save/skip and empty state. Populated and pain-state screenshots were inspected. No previous-head CI result is implied for the new merge head.

The merge preserves main's shared contracts, consent store, report builder, foundation handoff, input helpers and BodyMap implementation byte for byte. The history-factory conflict retains C's role/RIR behavior: historical edits preserve them, while a new training copy clears RIR and changes an unknown historical role to working. All C production code and mapping remain identical to the reviewed `b78e3f4` version. The RIR UI test now uses main's verified `UITestTextInput` helper. XcodeGen regenerated the project from the unchanged `project.yml`; the diff against main adds 92 registration lines without removing entries or changing build settings. The complete PR diff contains 24 module/test/resource/handoff/project files, with no shared foundation or renderer changes. The 1,324-entry tracking-mode audit and `git diff --check` passed.

The new external-strength coverage regression was first observed failing (non-nil score and missing dependency), then passed after preserving the unknown load and full eligibility lineage. The coordinator's feedback-clearing P2 is covered at repository/analysis and real UI levels. First empty drafts remain unsaved; clearing an existing record persists nil/empty values; skip leaves persisted state intact.

Coverage includes filtering/invalid times, RIR and historical role priors, unknown versus 100, deduplicated muscle weights, monotonic decay, edit/delete, independent pain/limitation, feedback persistence/prompt skip, temporal holdout rejection/reset, HRV source separation, complete dependencies and fresh-report removal, real RIR/history/repeat UI, and standalone recovery-page UI (body selection, pain override, feedback save/cancel and empty-state skip).

Production navigation/help wiring, final combined CI with the other tasks, physical-device HealthKit behavior, professional review and physiological/forecast validity remain distinct acceptance items. Official main includes the approved sleep/activity normalization, goal transactions, precise-date backup, durable consent, recommendation snapshots and BodyMap teardown fixes. The recovery module requires no additional shared API, DTO or schema change.

Standalone preview: `python3 TrainoteTests/RecoveryFixtures/prepare_preview.py --xcodegen /path/to/xcodegen` then build/test `build/recovery-preview/TrainoteRecoveryPreview.xcodeproj`, scheme `TrainoteRecoveryPreview`, with a dedicated Simulator and DerivedData. All preview state is synthetic and in memory; `RECOVERY_PREVIEW` / `RECOVERY_PREVIEW_TESTS` keep the harness entry point and UI tests outside production. The generator extracts the current persistence declaration mechanically and excludes the production `@main` file.
