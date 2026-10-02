# Trend module handoff (B)

Built from the approved A/D base `967fa5351838240b2bb6ca0c5cb8e777530e54c4`, then ordinarily merged the approved fixed foundation `28500cfaba534d2d09a1415f8c6d1cb1d904a10e` and its precise-backup-date patch `59766ea61bb063c1f5898f5ac31ab2b3dc91842f`. P values in `TrendRules` are engineering defaults, not validated physiological accuracy.

## Consumer entry points

- `TrendCalculator(): TrendCalculating` is a pure value calculator. Inject it directly into `ReportSnapshotBuilder`. It echoes the incoming `inputFingerprint`, emits `TrendResult` and `MetricFact` dependencies, and never reads a stored health snapshot or a system clock.
- `TrendView(model:onOpenManualGoal:onOpenHelp:)` belongs inside F's `NavigationStack`. Optional callbacks open F's manual-goal editor and help. B does not change AppShell, Settings, global nutrition summary, schema or root assembly.
- Construct `TrendViewModel(repository:health:calculator:now:timeZone:)` with A's repository/provider. The optional `atomicGoalWriter` is a testing override with the **official** `(ApplyGoalRevisionRequest) throws -> GoalRevisionApplicationResult` signature; production defaults to `repository.applyGoalRevision`. No additional writer adapter is needed.
- Call `reload()` on relevant foreground/food/profile/source changes. `now` and `timeZone` are injected for repeatability. The initial formula target always requires explicit adoption. Later automatic adoption requires persisted `automatic` mode and an adopted baseline in the current configuration cycle.
- `TrendHistory.effective(at:history:)` resolves immutable revisions by effective time, creation time, then stable ID. For day-based reporting, pass the last instant of that local day so a same-day adoption/undo has one final effective value. Unknown history stays unknown; never backfill from the mutable current target.

## Atomic target workflow

`TrendGoalWorkflow` recalculates before adoption, compares the displayed proposal ID, validates the captured `GoalRevisionState` against input targets/latest revision/history fingerprint, and calls `applyGoalRevision` once. A performs the in-transaction state check and creates the first legacy baseline. B does not create a duplicate baseline or call `appendGoalRevision` for target mutations.

Applications use the actual confirmation timestamp, not midnight: first adoption must follow the old `NutritionGoal.updatedAt`. Proposal identity remains keyed by the effective local day and normalized evidence. A same-clock or stale-state request is rejected instead of inventing a future application time. F's manual goal editor must also use A's atomic API once history exists.

Undo only applies to the latest active generated revision with a real predecessor. It appends a manual restoration revision with `reversesRevisionID` and **no proposal ID**, preserving original history. Review pauses for seven calendar days from the durable undo timestamp; the original proposal can never be reapplied. Preferences remain unchanged. The UI says “撤销并暂停 7 天” and explains that subsequent reviews follow the original mode. No second preference write is needed. A first target with no previous value has no invented undo; the UI offers the existing manual-goal route instead.

Successful persistence and display refresh are separate outcomes. `saveWeight`, `saveProfile`, `adopt` and `undo` return whether their write succeeded. Forms close after a successful write even if the following read fails; a weight form owns one stable UUID. A failed post-commit read says “已保存，但显示尚未刷新” and disables stale target actions until reload succeeds. Save failure is reported separately and never presented as a successful update.

## Configuration cycles and baseline reset

The coordinator approved using existing `profile.updatedAt` as the configuration-cycle boundary, without a second model or schema change. The cycle's initial baseline is its earliest non-reversed generated revision with `createdAt >= profile.updatedAt`; manual revisions and prior cycles do not become a new formula baseline.

A changed profile waits seven calendar days and shows the next review date. Afterwards the page offers “采用新的初始目标”. Even when automatic mode remains selected, the new initial estimate requires explicit adoption. Its full-precision target preserves the new cycle's initial prior (`initial calories / direction multiplier`). Later reviews keep that prior fixed and only update the current REE bound. All old goal history stays unchanged. This avoids an indefinite `requiresReview` state and avoids reinterpreting an old loss/maintenance/gain target under a new profile.

The first version uses the approved default protein/fat distribution and supports pausing. Optional coefficient preferences and voluntary phase tags would need one shared A/F contract if exposed later; no duplicate persistence is introduced by this module.

## Deterministic rules and quality policy

- Calculation days use the supplied analysis timezone. Raw timestamps, recorded timezones, sources and IDs are retained; UTC/GMT aliases compare as timezones.
- One daily representative: explicit sample reference; otherwise preferred source's first morning sample (04:00–11:59); otherwise its median. Without an available source preference, choose manual then a stable source ID. Never average across sources. A median retains every contributing reference.
- Smooth usable representatives with elapsed-time EMA (`tau=7 days`). Missing days are absent, never zero. Theil–Sen uses raw representatives and real elapsed days in the last 21 completed calendar days. Today's unfinished day can inform display/macro weight but cannot count toward completed weekly windows.
- Local outlier screen: at least five nearby representatives within ±10 days, threshold `max(3 kg, 6 × MAD)`. Raw outliers remain visible with `requiresReview`; explicit selection can override the statistical screen. Calculator range 25–350 kg, BMI 18.5–<30, age 18–78 and target-rate bounds are conservative P policy choices awaiting professional review. Other values remain recordable while formulas hold.
- Weight coverage: at least 14 actual days' span, 8 observed days, 3 in each last completed week. Diet: at least 12 explicit confirmations in the last 14 completed days. Food edits invalidate confirmation. A no-log day's zero intake requires explicit UI confirmation.
- Compare mean complete-day intake with the mean target for those same historical days. Unknown target history or >15% difference holds. Adjust by the sign of target rate minus observed rate, at most `min(100 kcal, 5%)`, no more than once per seven calendar days. The floor is `max(current REE, configuration-cycle initial prior × 80%)`; later weight changes never replace that initial prior.
- Watch calories are not added back. Average observed intake is an intake reference, never measured TDEE. Full target precision is retained; display calories to 10 kcal/macros to 1 g. Protein is fixed within each proposal, then fat/remaining carbohydrate are derived. Negative carbohydrate budget holds.
- Proposal IDs hash normalized evidence, local day, version, profile and history, excluding clock/read bookkeeping. Reopening unchanged facts produces the same ID; the outer result still carries A's original fingerprint for report consistency.
- Weight/energy facts retain manual-record or HealthKit-sample dependencies. New reports call A's fresh snapshot builder with this calculator; never reuse `TrendViewModel.result` as a new-report snapshot. A real-builder regression confirms removed health samples and their derived energy facts disappear even while the old cache remains.

## Fixed review examples

Fixture clock: `2026-10-03T12:00:00Z`, UTC. Synthetic adult: 70 kg, 175 cm, age 30, male formula parameter, moderate activity, 3 training days/week.

- Cold-start loss: REE 1,648.75; prior 2,638; target 2,242.3 kcal; protein 140 g; fat 62.286111… g; carbohydrate 280.43125 g. Internal 4/4/9 matches within floating-point tolerance.
- Existing target 2,300 with complete history: loss of 0.08 kg/day increases to 2,400; loss of 0.02 kg/day reduces to 2,200; in-tolerance loss holds.
- Maintenance baseline prior 2,638, current target 2,238 after weekly decrements, recent weight 73 kg + 0.02 kg/day: proposal is 2,138. The fixed initial floor is 2,110.4; it is not replaced by the larger prior estimated from current weight.
- Missing/failed inputs produce holds, not zero intake/weight or inferred permission denial.

## Verification and remaining integration

Dedicated Simulator: `A0F6045D-2E01-42C0-88A1-DB89CB85FF36` (Trainote Trend B, iPhone 17/iOS 26.5). DerivedData: `/tmp/trainote-trend-b-derived`; Xcode 26.6. XcodeGen 2.46.0 registration is committed separately; project.yml and CI thresholds are unchanged.

Exact final checks are in the PR. Tests cover pure calculations, real repository adoption/undo/automatic cadence, profile cycles, stale state, actual read-only save rollback, post-commit read failure, fresh report rebuilding and empty/populated/accessibility-size render attachments. Hosting/render checks do not replace F's full navigation/interaction acceptance. The precise-date backup correction is included. Main coordinates latest-head CI, final integration and any physical-device/scientific validation. No module-specific shared DTO/transaction blocker remains.
