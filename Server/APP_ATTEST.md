# App Attest verification

`src/app-attest.ts` is an offline cryptographic verifier for the iPhone report proxy. It performs no Apple/DeepSeek requests and does not write or log proof data. A failure throws only `Invalid App Attest proof`. Successful verification is one condition for server authorization; it does not establish AI data consent.

## Integration contract

```ts
const verifier = new AppleAppAttestVerifier({
  appID: "<APP_ID_PREFIX>.<BUNDLE_IDENTIFIER>",
  bundleVersions: ["<ALLOWED_CFBundleVersion>"],
});
const { publicKeyPEM, receipt } = verifier.attest(keyID, challengeBytes, attestationBytes);
const nextCounter = verifier.assertion(publicKeyPEM, storedCounter, expectedClientData, assertionBytes);
```

- Configure the **App ID prefix** from the Apple Developer identifier, which is not necessarily the Team ID. Bundle versions are an exact allowlist, with no client override. Production accepts only production AAGUID and signed distribution category `2` (TestFlight) or `4` (App Store).
- `challengeBytes` are the original random server bytes, not an already hashed value. The client supplies `SHA256(challengeBytes)` to `attestKey`.
- `expectedClientData` must be reconstructed by the server from its one-time challenge and canonical request context. It must bind the operation, installation and request body digest where applicable. Do not pass arbitrary client-supplied bytes without comparing them to this expected value. The client supplies `SHA256(expectedClientData)` to `generateAssertion`.
- Issue unpredictable, short-lived, single-use challenges. Atomically consume each challenge and update the counter before granting a session or performing an operation. Concurrent proofs must compare against the latest stored counter. This class deliberately returns the next counter and does not own server state.
- Atomically bind a verified key ID to one installation. Do not allow reassociation to bypass consent revocation, rate limits or quotas. Store only needed public-key/receipt/counter metadata; never health request bodies. A receipt is returned in base64 for its dedicated metadata store, not for logging.
- The `rootPEM` constructor seam is solely for locally generated certificate tests. It is rejected outside `node:test` and whenever `NODE_ENV=production`. Production assembly must omit it; there is no HTTP field, environment variable or simulator flag that configures a trust root. A synthetic key cannot authenticate against the pinned Apple roots.

## Checks implemented

Attestation checks strict bounded CBOR, unique keys, exact fields, the Apple certificate chain and pinned root, certificate signatures/dates/basic constraints/path lengths/key usage/unknown critical extensions, App Attest EKU, nonce extension `1.2.840.113635.100.8.2`, X9.62 public-key hash, RP ID, zero initial counter, production AAGUID, credential length/ID, and matching P-256/ES256 COSE coordinates. No platform trust store or certificate URL from the client is used.

Both attestation and assertion require signed validation-category and bundle-version extensions. Missing fields, unknown categories and unapproved versions fail closed. Category is accepted as a CBOR unsigned integer or the four little-endian bytes shown in Apple's current sample. Attestation uses the `apple_validation_category_01` / `apple_bundle_version_01` names. Assertion accepts that pair or the `validationCategory` / `bundleVersion` pair used in the assertion prose; mixed or duplicate aliases are rejected. An extension dictionary must be present even if Apple's sample omits the WebAuthn ED flag. Other unexpected authenticator flags are rejected.

Assertion checks the RP ID, increasing 32-bit counter, P-256 key and ECDSA signature over `SHA256(authenticatorData || SHA256(expectedClientData))`. Node's `verify("sha256", composite, ...)` performs the outer hash once; hashing the composite before calling it would hash twice. Receipt and assertion signature policies fail closed on unsupported algorithms.

The initial receipt is independently checked before attestation succeeds: CMS SignedData signature (including signed-attribute digest/content-type validation when present), signer identity, Apple G3 certificate chain, receipt-signing marker, app ID, `ATTEST` type, creation no more than five minutes old and not in the future, and matching attested public key from field 3's DER certificate. An included environment must be `production`; an included expiration must be in the future. Duplicate or missing required fields fail. BER constructed receipt content is supported. Initial receipts are not treated as a fraud risk metric; acquiring/refreshing that metric is a separately authorized Apple server integration.

## Pinned public certificates

| Purpose | Source | SHA-256 fingerprint |
| --- | --- | --- |
| Attestation | [Apple App Attestation Root CA](https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem), committed in `certs/Apple_App_Attestation_Root_CA.pem` | `1CB9823BA28BA6AD2D33A006941DE2AE4F513EF1D4E831B9F7E0FA7B6242C932` |
| Receipt | [Apple Root CA G3](https://www.apple.com/certificateauthority/AppleRootCA-G3.cer), public PEM embedded in `src/app-attest.ts` | `63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179` |

Downloaded and fingerprints checked on 2026-10-03. These are public trust anchors, not credentials. The package's compiled `dist/src` module reads the attestation PEM from the package's `certs` directory, so deployment packaging must include that directory. Missing or replaced pins prevent startup/verification. Root rotation requires a reviewed code change.

## Verification performed

Runtime: Node `22.23.1`; locked dependencies: `cbor 10.0.12`, `asn1js 3.0.10`.

```sh
cd Server
npm ci
npm run build
node --test dist/test/app-attest.test.js
```

The focused suite currently passes **47 tests**, including real signatures over locally generated synthetic chains/CMS receipts. It exercises wrong trust roots, certificate dates/usage, production identity and allowed-build checks, wrong nonces and COSE fields, old/future/mismatched receipts, CMS signed attributes and BER, request binding, forged assertions, replay counters, duplicate/trailing/oversized CBOR, generic errors and rejection of synthetic roots by production construction. It does not contact Apple or upload any data.

An additional one-off read-only check decoded Apple's published synthetic example and successfully verified its receipt's CMS signature, pinned G3 chain, app ID, creation timestamp and public key at the sample's timestamp. This is useful interoperability evidence for receipt parsing, not a real-device assertion test.

## Release gates and source discrepancies

The [server validation article](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server), [receipt verification article](https://developer.apple.com/documentation/devicecheck/assessing-fraud-risk), and [attestation validation guide](https://developer.apple.com/documentation/devicecheck/attestation-object-validation-guide) were read on 2026-10-03 via Apple's Markdown documents. The normative steps now require launch category and bundle version. Their availability and wire form have **not** been verified on physical iOS 17 devices. Older proofs without them are rejected; the app must retain local reporting and show the remote path as unavailable. No automatic relaxation is implemented.

The published validation-guide sample is internally inconsistent. Recomputing its normative nonce gives `1d1ce78912897de88cfe9fce5521aab37abfb09dc544833ff115612552cf75f3`; the certificate nonce is `87b7d06d93a4294e46f011e66b6cc400f0bab20729976c619580b42ae60bff6e`, which matches appending the **raw** challenge instead of its hash. Its encoded bundle version is `1` while prose says `1.0`; its category bytes are `01 00 00 00`; and its flags are `0x40` despite an appended extension dictionary. Its separately printed expected public-key hash also differs from the actual X9.62 key hash. This implementation does not weaken the normative nonce/key binding to accept that sample. The tests reproduce the normative algorithm with generated fixtures and reject raw-challenge nonces.

Before enabling real report traffic, record a signed physical-device TestFlight/App Store round trip for each supported OS family, confirm the authoritative extension/signature encoding with Apple if necessary, verify prefix/build allowlists and short-credential/challenge/counter persistence, test revocation/replay against the deployed state store, and review operational certificate revocation/rotation policy. The verifier performs offline chain validation and does not fetch OCSP/CRLs. No signing account, App Attest entitlement, real device or deployment was provisioned by this task. Passing synthetic tests does not discharge these gates or authorize health-data uploads.
