# AI report consumer handoff (E → F)

Built on the released health foundation at `main` commit `b24cd108222134d3cd3ba1d4169031cebc6226b3`, incorporated by an ordinary merge. PR #7 targets `main`; its unique changes are the report client/card, server, related tests/fixtures/docs, mechanical XcodeGen registration and independent server CI. Shared schemas, calculators, HealthKit reader, global navigation, UI test helpers, `project.yml` and existing iOS CI match that foundation. Default assembly is local-only; no production endpoint, credential, entitlement, real health upload or deployment was added.

## Assembly

Construct a single service when B/C calculators and F recommendations are available:

```swift
let reports = try AIReportAssembly.make(
  foundation: healthFoundation,
  trend: trendCalculator,
  recovery: recoveryCalculator,
  recommendations: recommendationProvider
)
```

The default `proxy: nil` installs **no network transport**. F should keep the AI switch in its approved “待开放” state until provider disclosure, signature, domain, budget and deployment gates have passed. A future approved `ReportProxyConfiguration(approvedBaseURL:)` is deployment configuration, never a user-editable provider URL. The app does not accept a model endpoint, system prompt or provider API key.

`AIReportAssembly.make` creates the real protected, backup-excluded `HealthLocal/AIReports/reports.json` store and registers it with `healthData.addDerivedDataInvalidator` before any report can be cached. It also registers the in-memory service and `.aiReports`/`.healthData` revocation hooks. It uses the same `LocalConsentStore` and repository as A. Keep it alive for the app lifetime; do not rebuild it during SwiftUI view rendering.

Construction performs no network request or permission prompt. A missing subsystem/storage error should preserve ordinary local recording and analysis. If assembly fails, show the locally computed report without claiming remote availability.

## Request and display

```swift
let content = await reports.report(
  type: .today, window: analysisWindow, asOf: analysisAsOf,
  timeZone: analysisTimeZone, localInput: currentLocalReportInput
)
AIReportCard(content: content, factLabel: labelForMetric, onDetails: openReportHelp)
```

`localInput` is optional and is used **only** for the immediate basic report. It is never passed to the transport. If it is unavailable, the basic report says records are insufficient; it does not invent zero or full readiness. A health-derived local input is rejected after explicit health disconnection.

Every new remote report, including an explicit retry, calls A's `ReportSnapshotBuilder.prepare`. It freshly reads the health window and reruns the injected calculators/candidates; the service cannot accept an old prepared snapshot from its caller. It calls `validateBeforeSending` immediately before each request (challenge, attestation, session, consent, report), and rejects leases older than the current generation or preparations older than a minute. Transport stages share a thirty-second budget. A response arriving after cancellation/revocation cannot update the cache or current card.

A’s `RecommendationSnapshot` includes F’s facts, candidates and context in one evaluation. E treats the resulting `ReportInput.inputFingerprint` as an opaque report identity, including template/schedule context; it never compares it to an underlying calculator fingerprint. Changing only that context invalidates both current and reopened report caches, while historical report identities stay unchanged.

Pass the analytical evaluation time/window from the current local analysis, not a new `Date.now` each time a View recomputes. A includes `asOf` in its input fingerprint, so changing time deliberately changes analysis identity. Same fresh fingerprint/type/calculation/knowledge/prompt projection reuses the validated local report. Identical in-flight requests coalesce; other concurrent requests show their local report instead of queuing. No background or automatic retry queue exists. `isGenerating`, `failure`, `isRemoteAvailable` and `revocationPending` are available for F's UI.

The card receives the original `ReportInput` alongside the result, inserts values from `MetricFact`, displays missing values as unknown and marks expiry as “待更新”. Supply `factLabel` from B/C's metric-label mapping; the default is “记录指标”. It is accessible SwiftUI text and supports dynamic type. It renders at most three observations/recommendations and a details button. It does not navigate or mutate data by itself. Historical cards must pass `isHistory: true`; their candidate text is explanatory only and must not be directly applied. Current cards must also revalidate any user action in F's rule layer before applying a new plan snapshot.

## Candidate and fact contract

- A's `ReportInput`, `ReportResult` and `ReportGenerating` are unchanged. `LocalReportGenerator` and the private freshly scoped remote generator implement `ReportGenerating`. The remote projection is transport-only, not a second domain model.
- A's complete fact dependency closure remains local for fresh reads, consent validation and health-derived cache removal. The transport sends calculated summaries and **every candidate reason fact**; raw per-sample health measurements are omitted unless a candidate directly cites them. Measurement-only reports select the latest fact per metric. More than 100 required wire facts fails closed, never silently truncating candidate reasons. The local path can accept up to 4,096 facts.
- Local IDs may contain the source/product/context separators emitted by A. They never become wire identifiers: the projection deterministically assigns `f0…` fact IDs and `a0…` candidate IDs, with an in-memory reverse map. The server accepts only those aliases. The client validates the response against the exact projection, restores original references/placeholders, then validates again against the original `ReportInput`. Metric/missing codes remain bounded ASCII identifiers; calculation versions also permit `+`, including C's `recovery-v0.1+exercise-muscles-v0.1`.
- B’s `weight.representative`, `weight.smoothed`, `energy.initialEstimate` and `weight.targetWeeklyChangePercent` deliberately end at the next local midnight. E recognizes only their `trend.<metric>.<20 hex>` IDs with the matching metric/unit and original manual/HealthKit/empty provenance. Single-day buckets must be 22–26 hours; smoothed windows may span older days, but their endpoint must still be within 26 hours of `asOf`. F’s existing calculation-source recommendation buckets remain supported. Only the transport copy is clipped to `asOf`; local facts, dependencies, IDs and B’s stable bucket semantics stay unchanged. Unknown buckets, future starts and raw future observations (even one second ahead) fail closed.
- F supplies rule-approved candidates. Nonempty `exclusionCodes` describes **constraints on those candidates**, so rest (`no_training_snapshot`), reduce-sets and keep-plan (`no_load_increase`) remain selectable. Constraints, source IDs, sample UUIDs, dependency metadata and numeric parameter ranges remain local. F must revalidate applicability and apply parameters in its rule layer; the model only selects approved actions.
- Model output is constrained selection JSON. Fixed explanation templates prevent free numbers, diagnoses and unsupported causal claims. Invalid facts/IDs/actions/fingerprint/expiry/schema/model/prompt fail independently on server and client. P parameters remain versioned engineering defaults, not demonstrated physiological accuracy.

## Consent, foreground and deletion order

1. Health connection and AI sharing remain independent. F's approved AI disclosure grants `LocalConsentStore.aiConsentVersion` only after affirmative choice. Without a current matching lease, no health refresh or network operation is started for AI. Disclosure expansion requires a coordinated new version.
2. Close AI with `try await reports.closeAI()`. Local revocation happens first; its hook synchronously cancels tasks and clears the current card, persists the pending marker in device-only Keychain, then authenticates server DELETE. Calling `consent.revoke(.aiReports)` directly also invokes the hook, but `closeAI` allows UI to await/surface remote failure.
3. On app startup/foreground, call `try await reports.resumePendingRevocation()` **before requesting reports**. Offline deletion remains pending and blocks re-enable traffic until acknowledged. Do not silently clear the marker. If storing a marker failed, startup reconciles against local revoked consent and marks deletion again. Server restarts clear active grants; each new report re-registers only the current valid local lease.
4. Historical remote reports remain available read-only via `reports.history()` after AI closes. `try reports.deleteAIReports()` independently cancels work and deletes all cached reports, without changing manual data, health consent or health caches. Reports contain reconstructible derived data and never enter user JSON backups or system backup.
5. Disconnect health using **A's `try await healthData.disconnectAndDelete()`**, not just `consent.revoke(.healthData)`. A stops readers, clears samples/anchors, invokes the registered persistent report cache, then the in-memory service. Health-derived history and current cards are removed; manual-only reports remain. A write failure must be surfaced for retry. Reopening cache while health is disconnected filters health-dependent history again.
6. On `attestKey` failure, only DeviceCheck `serverUnavailable` retains the unregistered key for the next explicit attempt. Any other attestation error clears its persisted identifier; a replacement is generated only on the next explicit report request. This follows [Apple’s App Attest lifecycle](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity). A save failure fails the current request closed. Registered keys and pending deletion markers are preserved.
7. Device keys and the pending deletion marker use `AfterFirstUnlockThisDeviceOnly` Keychain, synchronizable false. Short server credentials live only in memory. They are never in the app's JSON exports. No app log contains health request/response bodies.

Transport cancellation cannot retract a request already received by the provider. The help/disclosure owned by F must accurately describe the actual vendor arrangement; daily cards need no repetitive disclaimer.

## Verification and remaining conditions

Focused XCTest suites `AIReportTests`, `AIReportRealContractTests`, `AIReportTrendBoundaryTests` and `AIReportTransportTests` cover the shared synthetic fixture, no consent/no network, null values, input minimization, injection and wrong output, fresh retries, same-fingerprint reuse, coalescing, late response cancellation, independent history deletion, real health cache invalidation, revoked-input rejection, pending removal across restart, canonical request binding and unsupported App Attest. Real-contract regression data is synthetic output captured using C `2d2703ef28033d952d0d61a3b950003afe5e97f2` and F `274c82e89918e6d8e06aba3205798c16993ffdde`; no C/F production sources were changed or copied into this branch. The 28-day scenario contains 84 sleep/RHR/SDNN samples, normalized by the real A repository/builder into a 131-fact closure with 47 actual C summaries. Runtime regression tests replay those summaries through the current A builder, assert fresh reads and revoked-lease rejection, and test source-ID removal, reference restoration and F rest/reduce constraints.

B day-bucket regressions use actual synthetic `TrendCalculator` output captured from F’s fixed `a7e418c6749e6930255370cc9beb4ba737e92594` tree (without merging B/F implementations). Ten examples cover no readings, 28-day health history, UTC/Shanghai/Kiritimati/Kathmandu, New York spring/fall including the repeated hour, Lord Howe’s half-hour transition and the final 30 seconds of a day. Tests preserve every fact/value/dependency locally, round-trip opaque references, retain local fallback and reject future raw health dependencies. The original boundary was reproduced as failing before the fix.

The server suite checks real synthetic certificate/signature chains plus the full API lifecycle. See [server runbook](../../../../Server/README.md) for commands, fixed limits, exact endpoints and release gates.

True physical-device signing/App Attest, iOS 17 extension compatibility, provider terms and real synthetic vendor round trip, credentials/budget and deployment remain unverified external conditions. No real-health chain is enabled by passing local tests. F and the coordinator retain the final app integration, current-head CI and joint acceptance work.

### Local evidence (2026-10-03)

- Xcode 26.6 / iOS 26.5, dedicated simulator `8BE88433-EB6D-4C10-A418-79DBE52DA3DE` (`Trainote AI Reports E`); own DerivedData `/tmp/trainote-ai-reports-e-derived`.
- After ordinarily merging released `main` at `b24cd10`: **37 report unit tests and one UI regression passed, zero failures**. The selected UI test is `DailyUseUpgradeUITests.testFoodPortionRecentAndWeeklyReport`; its helper exactly matches the released foundation. Result: `/tmp/trainote-e-main-integration.xcresult`. Command: `xcodebuild -project Trainote.xcodeproj -scheme Trainote -destination 'platform=iOS Simulator,id=8BE88433-EB6D-4C10-A418-79DBE52DA3DE' -derivedDataPath /tmp/trainote-ai-reports-e-derived -resultBundlePath /tmp/trainote-e-main-integration.xcresult -only-testing:TrainoteTests/AIReportTests -only-testing:TrainoteTests/AIReportTransportTests -only-testing:TrainoteTests/AIReportRealContractTests -only-testing:TrainoteTests/AIReportTrendBoundaryTests -only-testing:TrainoteUITests/DailyUseUpgradeUITests/testFoodPortionRecentAndWeeklyReport CODE_SIGNING_ALLOWED=NO test`.
- Before that merge, **153 unit tests passed**, including the real service revocation/restart regression, in `/tmp/trainote-e-consent-restart-units.xcresult`. The main merge changed only the shared UI helper relative to E; report production code, report tests and fixtures were unchanged.
- The unchanged server previously passed Node 22.23.1 `npm test`: **65 tests, zero failures**, including 47 cryptographic App Attest cases and synthetic full HTTP/provider lifecycle. `npm run demo` validated the shared fixture offline. `npm audit --omit=dev --audit-level=moderate` reported zero known production dependency vulnerabilities; this is not a complete security audit. CI must verify the new PR head before merge.
- `git diff --check` passed. XcodeGen 2.46.0 registered sources/resources/tests mechanically in separate commits. Original iOS CI and `project.yml` are unchanged; the new server CI is independent.
- The coordinator separately reported passing actual B/C/E/F composition checks: nine report unit tests and one report UI test. Those are coordinator-provided evidence, not tests run in E's standalone branch. Current-head CI and final joint acceptance remain with the coordinator.
- A full local UI-suite run, signed physical devices, provider calls and deployed-service behavior are not established by these selected tests.
