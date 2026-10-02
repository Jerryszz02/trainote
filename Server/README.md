# Trainote report proxy v1

This module explains facts and selects already allowed recommendations. It cannot change nutrition targets, execute training plans, calculate new health values, browse, or run model code. It is implemented but **not deployed or enabled for real health data**. The app's default assembly has no remote transport.

## Local verification

Use Node **22.23.1**, pinned in `.nvmrc` (supported Maintenance LTS through April 2027 per the [Node release schedule](https://github.com/nodejs/Release)). Dependencies and transitive dependencies are fixed by `package-lock.json`.

```sh
cd Server
nvm use
npm ci --ignore-scripts --no-fund --no-audit
npm test
npm run demo
```

`demo` uses the checked-in synthetic Swift/TypeScript fixture and a fake DeepSeek HTTP response, validates the real provider parser and report renderer, and prints only counts. It does not listen on a port. `npm test` additionally exercises a local HTTP server, the installation/session/consent/report lifecycle, cryptographic attestation/assertion/receipt fixtures, revocation, timeouts, idempotency and quotas. Test-only trust and providers cannot be selected by production configuration. No credential or real health upload is needed.

After the deployment gates below pass, `npm run build && npm start` starts the production entry point on `127.0.0.1:8787`. It requires an approved TLS reverse proxy; the iOS client accepts HTTPS only and refuses redirects. Package `dist/`, `node_modules/`, `certs/` and `package.json`. Do not run multiple instances against one metadata directory.

## Deployment-owned environment names

| Name | Meaning |
| --- | --- |
| `APPLE_APP_ID` | Exact App ID prefix plus bundle identifier, checked against the signed RP ID |
| `APPLE_BUNDLE_VERSIONS` | Comma-separated exact permitted CFBundleVersion values |
| `DEEPSEEK_API_KEY` | Provider credential in the server secret manager only |
| `REPORT_STATE_DIR` | Dedicated writable directory for technical metadata and process lock |
| `REPORTS_ENABLED` | Must equal `true` to admit reports and consent grants |
| `AI_DISCLOSURE_CONFIRMED` | Must equal `true` after actual provider terms/disclosure approval |
| `PORT` | Optional loopback listener port; default 8787 |
| `NODE_ENV` | Set to `production` in a deployment; never a bypass switch |

Both enable switches default off. Creating `DISABLED` in the state directory rejects new reports immediately and cancels in-flight jobs within a second. Authenticated consent deletion remains available. No endpoint, model, system prompt, trust root, development authentication or fake provider environment option exists. App Attest unsupported/failure uses local reporting.

## Frozen HTTP contract

All POST/PUT/DELETE bodies are strict JSON objects, `Content-Type: application/json`, uncompressed, at most 128 KiB. Unknown fields are rejected. Dates are **integer Unix milliseconds**, not ISO strings or Swift fractional milliseconds. JSON numbers must be finite. No names, food names, notes, raw samples, sources, dependencies or exact locations are accepted. The iOS wire projection of the shared A `ReportInput` is the only report payload. Domain DTOs/schema are unchanged.

`src/contract.ts` and `TrainoteTests/Fixtures/ai-report-contract.json` freeze schema 1, `health-evidence-v1`, `report-selection-v1`, and local consent version `ai-report-v1`. Any disclosure change requires a coordinated consent version change with A/F. The fixture is exercised on both platforms.

| Route | Request | Response |
| --- | --- | --- |
| `GET /healthz` | None | `{status:"ok",version:"1"}` only |
| `POST /v1/installations/challenge` | `{keyID,purpose:"attest"}` or `{keyID,purpose:"session",intent:{method,path,bodyHash}}` | `{challengeID,challenge,expiresAt}`; random 32-byte base64 challenge, 120-second TTL |
| `POST /v1/installations/attest` | `{keyID,challengeID,attestation}`; key and CBOR proof in base64 | `{registered:true}`; verified production App Attest key registered once |
| `POST /v1/session` | `{keyID,challengeID,assertion}`; base64 CBOR proof | `{token,expiresAt}`; random 32-byte base64url credential, 120-second TTL, one use, bound to method/path/exact body hash |
| `PUT /v1/consent` | `{consentVersion,grantedAt}` plus bound Bearer token | `{consentVersion}`; grant date cannot be in the future |
| `DELETE /v1/consent` | `{}` plus bound Bearer token | `{revoked:true}`; immediately aborts jobs and invalidates old authorization/challenges |
| `POST /v1/reports` | `{schemaVersion,requestID,reportType,inputFingerprint,consentVersion,input}` plus bound Bearer token | Shared `ReportResult` with validated references and placeholder text |

Installation key IDs are validated against the attested public key. The server rebuilds assertion client data as these UTF-8 lines, without a trailing newline:

```text
trainote-session-v1
<challengeID>
<base64 challenge>
<uppercase method>
<path>
<lowercase SHA256 hex of the exact request bytes>
```

Challenges bind this intent and installation before proof verification. Each challenge is consumed even on failure; monotonic counters are persisted before granting a session. A registered-key challenge returns 409 so an app that lost the first attestation response can recover via a new valid assertion instead of reusing Apple's one-time attestation. This response does not authorize any operation.

Report inputs have at most 100 facts, 12 eligible candidates, 32 missing-data codes and eight calculation versions. Each fact includes only ID, metric code, nullable value, unit, window and quality flags. Candidate wire fields are actionID, action, muscleIDs and reasonFactIDs. All references must exist; type/fingerprint must agree across the envelope. Input age is at most one day; freshness on the device is separately enforced by A's builder. Metric codes/IDs are bounded ASCII identifiers, never arbitrary user text. Facts with null values remain unknown.

## Provider and output limits

The [current DeepSeek chat-completion API](https://api-docs.deepseek.com/api/create-chat-completion) is fixed to `https://api.deepseek.com/chat/completions`, `deepseek-flash`, non-thinking JSON mode, 1,024 output tokens and no tools. The adapter was tested with synthetic HTTP responses; no real provider request was made. Provider model availability, pricing, data terms and actual JSON behavior must be reconfirmed before enabling a deployment.

The model returns a strict **selection plan**, not free prose or numbers:

```json
{"observations":[{"evidenceID":"trend.weight","kind":"recorded"}],"actionIDs":["plan.choose"]}
```

There are at most three observations and three candidate actions. `kind` must agree with the fact's null/quality state. Duplicate, invented or excluded IDs, unexpected text/numbers, diagnoses and causal claims fail validation. The server projects valid selections into the existing `ReportResult`, using versioned fixed Chinese explanations. Text such as `{{fact:trend.weight}}` is resolved from the exact local fact table by the card; no model arithmetic is trusted. This is a deliberately constrained first report format. Richer explanatory prose requires a new validated contract, not relaxing a text filter.

Fixed knowledge references N02/R03/R05 from the approved evidence document preserve the distinctions between trend, local readiness and systemic measurements. They do not establish physiological validity of the product's P parameters. Knowledge is versioned and never fetched at report time.

Provider work has a 25-second deadline, even for a non-cooperative provider, with 32 KiB response cap. Client auth plus report transmission shares a 30-second interaction budget. Redirects, truncated provider output, tool calls and malformed content fail closed. Client validation independently checks schema, fingerprint, model/prompt version, exact explanation templates, fact/action IDs and expiry. Failure yields a local report from existing facts, without caching the failed remote output.

## Quotas, storage and cancellation

- Engineering defaults: five newly reserved reports per attested key per UTC day, one active report per key, twenty globally, sixty incoming requests per source socket address per minute. The server ignores forwarded IP headers. Approved edge rate limiting must account for the shared proxy address; do not increase limits without a cost check.
- Idempotency reserves requestID plus body hash for ten minutes before provider work. Repeating an ID returns **409** (`request_already_processed` or `idempotency_conflict`) and does not repeat provider work or quota consumption. No completed health body is kept to replay it. If a success response was lost, the client shows local fallback; a user-initiated new attempt obtains a fresh snapshot and a new requestID. Failures consume the reserved quota.
- Durable state contains public keys/receipts, counters, consent technical metadata, UTC quota counters and request digests/status/expiry. Request digests expire after ten minutes and are swept every minute and at startup. No report, fact value or request/response body is persisted. Short credentials/challenges exist only in bounded memory; the service has no content/access/error-object logger. Deployment proxy logs and vendor retention are separate responsibilities.
- Atomic file replacement with fsync and a single-process lock prevents concurrent state writers. Directories/files use 0700/0600 permissions. An unexpected storage error blocks report grants/results in memory. Revocation first cancels jobs and invalidates sessions even if persistence fails. On every restart, all server grants are durably cleared before listening; the app must present its still-valid local consent again. Counters and quotas remain durable. A crash leaves a process lock: an operator must verify the process is gone before removing that specific lock. Do not copy/reset state to reset quotas or revive revoked grants.
- Closing AI persists a local revocation marker, cancels current work, rejects future requests, and sends only signed DELETE until acknowledged. Offline removal stays pending across restarts and is retried on foreground; re-enabling cannot bypass it. Cancelling an already transmitted request cannot retract provider-side processing. Provider deletion/retention obligations remain a terms-dependent release gate.

Error responses contain only a fixed `error` code: 400 invalid contract/facts, 401 proof/session, 403 consent, 409 idempotency/registration, 413 size, 429 request/concurrency/quota, 502 provider/validation, 503 disabled/storage fault, 504 timeout/cancellation. The app handles all with local fallback; it does not automatically retry reports.

## Release conditions still open

1. Explicit provider API terms, retention/deletion arrangements, processing region, disclosure wording and user consent approval. The app must show remote reporting as unavailable until these are settled.
2. Approved budget, account secret management, domain/TLS, single-process durable hosting, edge logging/rate policy, monitoring using technical counters only, recovery procedure and deployment authorization. No resources were provisioned or deployed.
3. Production App Attest capability, correct App ID prefix/build allowlist, signed physical TestFlight/App Store device tests, and supported-OS proof formats. [App Attest verification notes](APP_ATTEST.md) detail current Apple example inconsistencies and the strict handling of new extensions. Missing extensions fail closed, including potentially older iOS 17 devices. No entitlement or shared Xcode configuration is changed by this task.
4. Real DeepSeek synthetic-data round trip and measured cost/latency after credentials are authorized. Local tests prove contract and cancellation behavior, not provider availability or physiological accuracy.
5. Coordinator integration with B/C/F and the separately pending A boundary fixes, current-head iOS CI, full app acceptance and real-device health disconnection checks.

For F's concrete app assembly, card and cleanup sequence see [the client handoff](../Trainote/Services/AIReports/README.md).
