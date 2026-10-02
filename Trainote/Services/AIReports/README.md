# AI report consumer handoff (E → F)

Based on the approved fixed A/D commit `967fa5351838240b2bb6ca0c5cb8e777530e54c4`. This module changes no shared schema, calculators, HealthKit reader, global navigation or iOS CI. The coordinator owns synchronization of later A fixes. Default assembly is local-only; no production endpoint, credential, entitlement, real health upload or deployment was added.

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

Pass the analytical evaluation time/window from the current local analysis, not a new `Date.now` each time a View recomputes. A includes `asOf` in its input fingerprint, so changing time deliberately changes analysis identity. Same fresh fingerprint/type/calculation/knowledge/prompt projection reuses the validated local report. Identical in-flight requests coalesce; other concurrent requests show their local report instead of queuing. No background or automatic retry queue exists. `isGenerating`, `failure`, `isRemoteAvailable` and `revocationPending` are available for F's UI.

The card receives the original `ReportInput` alongside the result, inserts values from `MetricFact`, displays missing values as unknown and marks expiry as “待更新”. Supply `factLabel` from B/C's metric-label mapping; the default is “记录指标”. It is accessible SwiftUI text and supports dynamic type. It renders at most three observations/recommendations and a details button. It does not navigate or mutate data by itself. Historical cards must pass `isHistory: true`; their candidate text is explanatory only and must not be directly applied. Current cards must also revalidate any user action in F's rule layer before applying a new plan snapshot.

## Candidate and fact contract

- A's `ReportInput`, `ReportResult` and `ReportGenerating` are unchanged. `LocalReportGenerator` and the private freshly scoped remote generator implement `ReportGenerating`. The remote projection is transport-only, not a second domain model.
- Fact/candidate IDs, metric/missing codes and calculation versions must be stable ASCII identifiers (`A-Z`, `a-z`, digits, `.`, `_`, `:`, `-`, length ≤128); facts ≤100 and eligible candidates ≤12. Do not put translated/user-entered labels into these identifiers. Display labels stay local.
- Current projection treats nonempty `exclusionCodes` as **actively excluded** and removes those candidates before provider selection. F should supply only rule-approved candidates with empty `exclusionCodes`. If F intends this field to mean hypothetical exclusion conditions instead, coordinate that single semantic definition with A before enabling real transport; do not invent a parallel candidate DTO.
- Candidate reasons must refer to included fact IDs. The shared builder resolves health dependencies; report transport drops source IDs, sample UUIDs, dependency metadata and allowed numeric ranges. The model can rank allowed actions but cannot choose a new parameter value. F owns parameter application.
- Model output is constrained selection JSON. Fixed explanation templates prevent free numbers, diagnoses and unsupported causal claims. Invalid facts/IDs/actions/fingerprint/expiry/schema/model/prompt fail independently on server and client. P parameters remain versioned engineering defaults, not demonstrated physiological accuracy.

## Consent, foreground and deletion order

1. Health connection and AI sharing remain independent. F's approved AI disclosure grants `LocalConsentStore.aiConsentVersion` only after affirmative choice. Without a current matching lease, no health refresh or network operation is started for AI. Disclosure expansion requires a coordinated new version.
2. Close AI with `try await reports.closeAI()`. Local revocation happens first; its hook synchronously cancels tasks and clears the current card, persists the pending marker in device-only Keychain, then authenticates server DELETE. Calling `consent.revoke(.aiReports)` directly also invokes the hook, but `closeAI` allows UI to await/surface remote failure.
3. On app startup/foreground, call `try await reports.resumePendingRevocation()` **before requesting reports**. Offline deletion remains pending and blocks re-enable traffic until acknowledged. Do not silently clear the marker. If storing a marker failed, startup reconciles against local revoked consent and marks deletion again. Server restarts clear active grants; each new report re-registers only the current valid local lease.
4. Historical remote reports remain available read-only via `reports.history()` after AI closes. `try reports.deleteAIReports()` independently cancels work and deletes all cached reports, without changing manual data, health consent or health caches. Reports contain reconstructible derived data and never enter user JSON backups or system backup.
5. Disconnect health using **A's `try await healthData.disconnectAndDelete()`**, not just `consent.revoke(.healthData)`. A stops readers, clears samples/anchors, invokes the registered persistent report cache, then the in-memory service. Health-derived history and current cards are removed; manual-only reports remain. A write failure must be surfaced for retry. Reopening cache while health is disconnected filters health-dependent history again.
6. Device keys and the pending deletion marker use `AfterFirstUnlockThisDeviceOnly` Keychain, synchronizable false. Short server credentials live only in memory. They are never in the app's JSON exports. No app log contains health request/response bodies.

Transport cancellation cannot retract a request already received by the provider. The help/disclosure owned by F must accurately describe the actual vendor arrangement; daily cards need no repetitive disclaimer.

## Verification and remaining conditions

Focused XCTest suites `AIReportTests` and `AIReportTransportTests` cover the shared synthetic fixture, no consent/no network, null values, input minimization, injection and wrong output, fresh retries, same-fingerprint reuse, coalescing, late response cancellation, independent history deletion, real health cache invalidation, revoked-input rejection, pending removal across restart, canonical request binding and unsupported App Attest. The server suite checks real synthetic certificate/signature chains plus the full API lifecycle. See [server runbook](../../../../Server/README.md) for commands, fixed limits, exact endpoints and release gates.

True physical-device signing/App Attest, iOS 17 extension compatibility, provider terms and real synthetic vendor round trip, credentials/budget and deployment remain unverified external conditions. No real-health chain is enabled by passing local tests. F and the coordinator retain the final app integration, current-head CI and joint acceptance work.
