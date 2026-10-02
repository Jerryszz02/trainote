# Trend module handoff (B)

This module implements section 6 of the approved health analysis plan on the fixed A/D foundation `967fa5351838240b2bb6ca0c5cb8e777530e54c4`. P values in `TrendRules` are engineering defaults, not validated physiological accuracy.

## Consumer entry points

- `TrendCalculator(): TrendCalculating` is a pure value calculator. Inject it directly into `ReportSnapshotBuilder`. It echoes the incoming `inputFingerprint`, emits `TrendResult` and `MetricFact` dependencies, and never reads a stored health snapshot or a system clock.
- `TrendView(model:onOpenManualGoal:onOpenHelp:)` belongs inside F's `NavigationStack`. Optional callbacks open F's existing manual-goal editor and help. No AppShell, Settings, global nutrition summary, schema, or root assembly is changed by B.
- Construct `TrendViewModel(repository:health:calculator:atomicGoalWriter:now:timeZone:)` with A's repository/provider. `now` and `timeZone` are injected for repeatability. Call `reload()` on relevant foreground/food/profile/source changes. The initial formula target always requires explicit adoption. Later automatic adoption occurs only when persisted mode is explicitly `automatic`; normal suggested mode does not write a target on load.
- `TrendGoalWorkflow` recalculates before adoption, compares the displayed proposal ID, rejects stale/manual-mode/reversed requests, and calls one injected atomic writer. Its writer is currently awaiting A's approved public transaction API. There is no two-save fallback. UI target mutation is disabled when no writer is injected.
- `TrendHistory.effective(at:history:)` resolves immutable revisions by effective time, creation time, then stable ID. For day-based reporting, pass the last instant of that local day so a same-day adoption/undo has one final effective value. A missing historic target stays unknown; the mutable current target is never backfilled into past days.

## Atomic writer requirements / open shared contract

A owns the new `applyGoalRevision` operation. It must compare the expected legacy target and latest revision ID inside the transaction, preserve a first legacy-goal baseline, append the supplied immutable revision, project the target to `NutritionGoal`, and commit any supplied preference update in the same save. Failures must leave all values unchanged. Baseline must not pretend the old target was valid before its known update date. Duplicate proposal IDs must be idempotent without overwriting content.

Undo only applies to the latest active generated revision. It appends a restoration revision referring to the original, keeps history, returns to suggested mode and pauses for seven calendar days. This preference change is part of the same transaction, so a new fingerprint cannot silently reapply the undone action. Initial adoption with no previous target has nothing to restore; the final shared transaction must define its policy explicitly.

Additional shared metadata gap: v1 revisions lack a historical profile/configuration snapshot, explicit initial-TDEE reference and its dependencies, evidence fingerprint/reason IDs, and a baseline-reset marker. This implementation reconstructs the initial prior only from the first unrounded generated target while the profile is unchanged. A later profile edit returns `requiresReview` instead of reinterpreting the old prior under a new direction/activity. A/F must supply a single approved baseline-reset/metadata contract to resume adaptive updates after a changed profile. B does not create a second persistence model. Protein/fat customization and voluntary phase tags likewise need one shared preference contract; v1 exposes the approved default distribution and a pause control.

## Deterministic rules and quality policy

- Calculation days use the explicitly supplied analysis timezone. Raw sample timestamps, recorded timezones, sources and IDs are retained. `UTC`/`GMT` aliases are compared as timezones.
- One daily representative: explicit sample reference; otherwise preferred source's first morning sample (04:00–11:59); otherwise that source's median. If no source preference is available, choose manual then a stable source identifier. Never average across sources. A median keeps every contributing sample reference.
- Smooth only usable representatives with elapsed-time EMA (`tau=7 days`). Missing days are absent, never zero. Theil–Sen uses raw representatives and real elapsed days in the last 21 **completed** calendar days; the current incomplete day can inform display/macro weight but cannot count toward the two complete weekly windows.
- Local outlier screen uses at least five nearby representatives within ±10 days and `max(3 kg, 6 × MAD)`. Raw outliers remain visible with `requiresReview`; explicit selection can override the statistical screen. The broad 25–350 kg calculator range, general-fitness BMI 18.5–<30, age 18–78 and target-rate bounds are conservative P policy choices awaiting professional review. Values outside them remain recordable; automatic formulas hold.
- Weight coverage: span at least 14 actual days, 8 days overall, 3 days in each last completed week. Diet: at least 12 explicit confirmations in the last 14 completed days. Editing food invalidates A's confirmation fingerprint. Confirming a day with no logs requires an explicit UI confirmation; it is never inferred from missing data.
- Compare complete-day intake against each day's historic target. Unknown target history holds; >15% difference between mean intake and the mean of those same days' targets holds. Adjust by the sign of target rate minus observed rate, at most `min(100 kcal, 5%)`, no more than once per seven calendar days. Current REE and initial-prior floor hold before further decreases. Watch calories are not added back; average observed intake is labelled an intake reference, never measured TDEE.
- Store full precision; display calories to 10 kcal and macros to 1 g. Protein is determined at review from trend weight and fixed within that proposal, then fat and remaining carbohydrate are derived. A negative carbohydrate budget holds.
- A proposal hashes normalized evidence, local effective day, version, profile and history. It deliberately excludes clock/read bookkeeping from identity; reopening in the same day with unchanged facts does not create another ID. The outer result still carries A's original fingerprint for report consistency.
- All derived weight/energy facts retain manual-record or HealthKit-sample dependencies. New reports must call A's fresh snapshot builder with this calculator; never supply `TrendViewModel.result` as a report cache substitute.

## Fixed review examples

Fixture time is `2026-10-03T12:00:00Z`, analysis timezone UTC. Synthetic adult profile: 70 kg, 175 cm, age 30, male formula parameter, moderate activity, three training days/week.

- Cold-start lose estimate: REE 1,648.75; activity prior 2,638; target 2,242.3 kcal; protein 140 g; fat 62.286111… g; carbohydrate 280.43125 g. Internal 4/4/9 exactly matches the target, within floating-point tolerance.
- Existing target 2,300 kcal, complete diet/history: loss of 0.08 kg/day increases target to 2,400; loss of 0.02 kg/day reduces to 2,200. In-tolerance loss preserves 2,300.
- Sparse/missing/failed inputs return a hold; they do not imply zero intake, zero weight or permission denial.

## Verification artifacts

Dedicated Simulator: `A0F6045D-2E01-42C0-88A1-DB89CB85FF36` (Trainote Trend B, iPhone 17 / iOS 26.5). DerivedData: `/tmp/trainote-trend-b-derived`. Xcode 26.6. Sources and tests are mechanically registered with XcodeGen 2.46.0 in a separate project-only commit; `project.yml` and CI settings are unchanged.

The first scoped run exposed UTC/GMT alias handling; it was corrected and regression-tested. Current runs and exact final counts are recorded in the PR. `TrendPresentationTests` renders empty, populated and accessibility-size screens and attaches PNGs. This is a hosting/render check; F still owns full navigation and interaction UI acceptance. Real device health permission/source behavior and physiological validation remain outside this module's synthetic tests.
