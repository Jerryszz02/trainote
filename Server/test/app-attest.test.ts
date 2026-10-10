import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign, X509Certificate, type KeyObject } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import * as asn1 from "asn1js";
import cborLibrary from "cbor";
import { AppleAppAttestVerifier } from "../src/app-attest.js";
const { decodeAllSync, encode } = cborLibrary;

// All private keys and certificate chains in this file are generated locally.
// No Apple/device/user health data or production signing material is used.
const appID = "ABCDEFGHIJ.com.example.synthetic";
const now = Date.parse("2026-10-03T10:00:00.000Z");
const challenge = Buffer.alloc(32, 0x32);
const sha256 = (input: Buffer): Buffer => createHash("sha256").update(input).digest();
const oid = (value: string): asn1.ObjectIdentifier => new asn1.ObjectIdentifier({ value });
const int = (value: number): asn1.Integer => new asn1.Integer({ value });
const seq = (value: asn1.BaseBlock[]): asn1.Sequence => new asn1.Sequence({ value });
const set = (value: asn1.BaseBlock[]): asn1.Set => new asn1.Set({ value });
const oct = (value: Buffer): asn1.OctetString => new asn1.OctetString({ valueHex: value });
const context = (tag: number, value: asn1.BaseBlock[]): asn1.Constructed => new asn1.Constructed({ idBlock: { tagClass: 3, tagNumber: tag }, value });
const bytes = (value: asn1.BaseBlock): Buffer => Buffer.from(value.toBER(false));
const parse = (value: Buffer): asn1.BaseBlock => asn1.fromBER(value).result;
const ecdsa = (): asn1.Sequence => seq([oid("1.2.840.10045.4.3.2")]);
const digest = (): asn1.Sequence => seq([oid("2.16.840.1.101.3.4.2.1"), new asn1.Null()]);
const name = (value: string): asn1.Sequence => seq([set([seq([oid("2.5.4.3"), new asn1.Utf8String({ value })])])]);
const keyPair = (): { publicKey: KeyObject; privateKey: KeyObject } => generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const extension = (id: string, value: asn1.BaseBlock, critical = false): asn1.Sequence => seq([
  oid(id), ...(critical ? [new asn1.Boolean({ value: true })] : []), oct(bytes(value)),
]);
let serial = 1;
interface Certificate {
  name: string;
  key: ReturnType<typeof keyPair>;
  der: Buffer;
  pem: string;
  issuer: asn1.Sequence;
  serial: asn1.Integer;
}
function certificate(
  commonName: string, key: ReturnType<typeof keyPair>, issuer?: Certificate,
  options: { ca?: boolean; pathLength?: number; expires?: number; starts?: number; extensions?: asn1.BaseBlock[]; noDigitalSignature?: boolean } = {},
): Certificate {
  const certificateSerial = int(serial++);
  const issuerName = name(issuer?.name ?? commonName);
  const constraints = seq(options.ca ? [new asn1.Boolean({ value: true }), int(options.pathLength ?? 0)] : []);
  const keyUsage = new asn1.BitString({ unusedBits: options.ca ? 1 : 7, valueHex: Buffer.from([options.ca ? 6 : options.noDigitalSignature ? 0 : 128]) });
  const tbs = seq([
    context(0, [int(2)]), certificateSerial, ecdsa(), issuerName,
    seq([new asn1.UTCTime({ valueDate: new Date(options.starts ?? now - 86_400_000) }), new asn1.UTCTime({ valueDate: new Date(options.expires ?? now + 86_400_000) })]),
    name(commonName), parse(key.publicKey.export({ type: "spki", format: "der" })),
    context(3, [seq([extension("2.5.29.19", constraints, true), extension("2.5.29.15", keyUsage, true), ...(options.extensions ?? [])])]),
  ]);
  const signature = sign("sha256", bytes(tbs), issuer?.key.privateKey ?? key.privateKey);
  const der = bytes(seq([tbs, ecdsa(), new asn1.BitString({ unusedBits: 0, valueHex: signature })]));
  return { name: commonName, key, der, pem: new X509Certificate(der).toString(), issuer: issuerName, serial: certificateSerial };
}
const root = certificate("Synthetic Root", keyPair(), undefined, { ca: true, pathLength: 1 });
const intermediate = certificate("Synthetic Intermediate", keyPair(), root, { ca: true, pathLength: 0 });
const attestedKey = keyPair();
const point = (key: KeyObject): Buffer => {
  const jwk = key.export({ format: "jwk" });
  return Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, "base64url"), Buffer.from(jwk.y!, "base64url")]);
};
const keyID = sha256(point(attestedKey.publicKey)).toString("base64");
const defaultExtensions = (): Map<string, unknown> => new Map<string, unknown>([
  ["apple_validation_category_01", Buffer.from([4, 0, 0, 0])], ["apple_bundle_version_01", "17"],
]);

interface ReceiptOptions {
  appID?: string; created?: number; expires?: number; kind?: string; environment?: string;
  wrongKey?: boolean; badSignature?: boolean; badDigest?: boolean; signedAttributes?: boolean;
  duplicateField?: boolean; omitField?: number; noMarker?: boolean; badSignerID?: boolean;
  signerExpired?: boolean; unknownCritical?: boolean; includeRoot?: boolean; differentRoot?: boolean;
  berContent?: boolean;
}
function receipt(attestation: Certificate, options: ReceiptOptions = {}): Buffer {
  const issuer = options.differentRoot ? certificate("Rogue Intermediate", keyPair(), certificate("Rogue Root", keyPair(), undefined, { ca: true, pathLength: 1 }), { ca: true }) : intermediate;
  const signer = certificate("Synthetic Receipt Signing", keyPair(), issuer, {
    expires: options.signerExpired ? now - 1_000 : undefined,
    extensions: [
      ...(options.noMarker ? [] : [extension("1.2.840.113635.100.12.15", new asn1.Null())]),
      ...(options.unknownCritical ? [extension("1.2.3.4.5", new asn1.Null(), true)] : []),
    ],
  });
  const attributes: [number, Buffer][] = [
    [2, Buffer.from(options.appID ?? appID)], [3, options.wrongKey ? signer.der : attestation.der],
    [6, Buffer.from(options.kind ?? "ATTEST")], [7, Buffer.from(options.environment ?? "production")],
    [12, Buffer.from(new Date(options.created ?? now - 1_000).toISOString())],
    [21, Buffer.from(new Date(options.expires ?? now + 86_400_000).toISOString())],
  ];
  if (options.duplicateField) attributes.push([2, Buffer.from(appID)]);
  const payload = bytes(set(attributes.filter(([type]) => type !== options.omitField).map(([type, value]) => seq([int(type), int(1), oct(value)]))));
  const signedAttributes = [
    seq([oid("1.2.840.113549.1.9.3"), set([oid("1.2.840.113549.1.7.1")])]),
    seq([oid("1.2.840.113549.1.9.4"), set([oct(options.badDigest ? Buffer.alloc(32) : sha256(payload))])]),
  ];
  const signature = sign("sha256", options.signedAttributes ? bytes(set(signedAttributes)) : payload, signer.key.privateKey);
  if (options.badSignature) signature[signature.length - 1]! ^= 1;
  const signerInfo = seq([
    int(1), seq([signer.issuer, options.badSignerID ? int(999_999) : signer.serial]), digest(),
    ...(options.signedAttributes ? [context(0, signedAttributes)] : []), ecdsa(), oct(signature),
  ]);
  const content = options.berContent
    ? new asn1.OctetString({ idBlock: { isConstructed: true }, lenBlock: { isIndefiniteForm: true }, value: [oct(payload.subarray(0, 37)), oct(payload.subarray(37))] })
    : oct(payload);
  return bytes(seq([oid("1.2.840.113549.1.7.2"), context(0, [seq([
    int(1), set([digest()]), seq([oid("1.2.840.113549.1.7.1"), context(0, [content])]),
    context(0, [parse(signer.der), parse(issuer.der), ...(options.includeRoot ? [parse(root.der)] : [])]), set([signerInfo]),
  ])])]));
}
interface AttestationOptions {
  authMutate?: (auth: Buffer) => void;
  extensions?: Map<string, unknown> | null;
  coseMutate?: (cose: Map<number, unknown>) => void;
  badNonce?: boolean; rawChallengeNonce?: boolean; expired?: boolean; future?: boolean;
  wrongUsage?: boolean; noDigitalSignature?: boolean; leafCA?: boolean; unknownCritical?: boolean;
  extraCertificate?: boolean; receipt?: ReceiptOptions;
}
function attestation(options: AttestationOptions = {}): Buffer {
  const keyPoint = point(attestedKey.publicKey);
  const cose = new Map<number, unknown>([[1, 2], [3, -7], [-1, 1], [-2, keyPoint.subarray(1, 33)], [-3, keyPoint.subarray(33)]]);
  options.coseMutate?.(cose);
  const authPrefix = Buffer.concat([sha256(Buffer.from(appID)), Buffer.from([0xc0]), Buffer.alloc(4), Buffer.from("appattest"), Buffer.alloc(7), Buffer.from([0, 32]), Buffer.from(keyID, "base64")]);
  const extensions = options.extensions === null ? Buffer.alloc(0) : encode(options.extensions ?? defaultExtensions());
  const auth = Buffer.concat([authPrefix, encode(cose), extensions]);
  options.authMutate?.(auth);
  const nonce = options.badNonce ? Buffer.alloc(32) : sha256(Buffer.concat([auth, options.rawChallengeNonce ? challenge : sha256(challenge)]));
  const leaf = certificate("Synthetic Attested Key", attestedKey, intermediate, {
    ca: options.leafCA, expires: options.expired ? now - 1_000 : undefined, starts: options.future ? now + 1_000 : undefined,
    noDigitalSignature: options.noDigitalSignature,
    extensions: [
      extension("1.2.840.113635.100.8.2", seq([context(1, [oct(nonce)])])),
      extension("2.5.29.37", seq([oid(options.wrongUsage ? "1.3.6.1.5.5.7.3.1" : "1.2.840.113635.100.4.24")])),
      ...(options.unknownCritical ? [extension("1.2.3.4.5", new asn1.Null(), true)] : []),
    ],
  });
  return encode({ fmt: "apple-appattest", attStmt: { x5c: [leaf.der, intermediate.der, ...(options.extraCertificate ? [root.der, root.der] : [])], receipt: receipt(leaf, options.receipt) }, authData: auth });
}
function verifier(config: Partial<ConstructorParameters<typeof AppleAppAttestVerifier>[0]> = {}): AppleAppAttestVerifier {
  return new AppleAppAttestVerifier({ appID, bundleVersions: ["17"], rootPEM: root.pem, now: () => now, ...config });
}
function assertion(counter: number, clientData: Buffer, options: { extensions?: Map<string, unknown> | null; wrongRP?: boolean; flags?: number; doubleHash?: boolean; wrongKey?: boolean } = {}): Buffer {
  const auth = Buffer.alloc(37);
  sha256(Buffer.from(options.wrongRP ? "OTHERAPP00.example.invalid" : appID)).copy(auth);
  auth[32] = options.flags ?? 0x80;
  auth.writeUInt32BE(counter, 33);
  const authData = Buffer.concat([auth, options.extensions === null ? Buffer.alloc(0) : encode(options.extensions ?? defaultExtensions())]);
  const composite = Buffer.concat([authData, sha256(clientData)]);
  return encode({ authenticatorData: authData, signature: sign("sha256", options.doubleHash ? sha256(composite) : composite, options.wrongKey ? root.key.privateKey : attestedKey.privateKey) });
}
const publicKeyPEM = attestedKey.publicKey.export({ type: "spki", format: "pem" }).toString();
const clientData = Buffer.from(JSON.stringify({ challenge: "synthetic-onetime-challenge", method: "POST", path: "/v1/installation/session", installationID: "synthetic" }));
const invalidProof = { message: "Invalid App Attest proof" };

test("verifies locally generated production attestation and independent CMS receipt", () => {
  const result = verifier().attest(keyID, challenge, attestation());
  assert.equal(result.publicKeyPEM, publicKeyPEM);
  assert.ok(Buffer.from(result.receipt, "base64").length > 128);
});

test("verifies signed-attribute CMS and BER constructed receipt content", () => {
  for (const options of [{ signedAttributes: true }, { berContent: true }, { includeRoot: true }]) {
    assert.equal(verifier().attest(keyID, challenge, attestation({ receipt: options })).publicKeyPEM, publicKeyPEM);
  }
});

test("allows both documented category encodings and exact allowed TestFlight/App Store builds", () => {
  for (const category of [2, 4, Buffer.from([2, 0, 0, 0]), Buffer.from([4, 0, 0, 0])]) {
    const extensions = defaultExtensions();
    extensions.set("apple_validation_category_01", category);
    assert.equal(verifier().attest(keyID, challenge, attestation({ extensions })).publicKeyPEM, publicKeyPEM);
  }
  // Apple's current sample appends its extension dictionary with AT but no ED bit.
  assert.equal(verifier().attest(keyID, challenge, attestation({ authMutate: (auth) => { auth[32] = 0x40; } })).publicKeyPEM, publicKeyPEM);
});

test("development attestation requires explicit server opt-in and retains distribution support", () => {
  for (const category of [3, Buffer.from([3, 0, 0, 0])]) {
    const extensions = defaultExtensions();
    extensions.set("apple_validation_category_01", category);
    const proof = attestation({ extensions });
    for (const allowDevelopmentBuilds of [undefined, false]) {
      assert.throws(() => verifier({ allowDevelopmentBuilds }).attest(keyID, challenge, proof), invalidProof);
    }
    assert.equal(verifier({ allowDevelopmentBuilds: true }).attest(keyID, challenge, proof).publicKeyPEM, publicKeyPEM);
  }
  for (const category of [2, 4]) {
    const extensions = defaultExtensions();
    extensions.set("apple_validation_category_01", category);
    assert.equal(verifier({ allowDevelopmentBuilds: true }).attest(keyID, challenge, attestation({ extensions })).publicKeyPEM, publicKeyPEM);
  }
});

test("development assertions require opt-in on every request including previously registered keys", () => {
  for (const names of [["apple_validation_category_01", "apple_bundle_version_01"], ["validationCategory", "bundleVersion"]]) {
    for (const category of [3, Buffer.from([3, 0, 0, 0])]) {
      const extensions = new Map<string, unknown>([[names[0]!, category], [names[1]!, "17"]]);
      const proof = assertion(1, clientData, { extensions });
      assert.equal(verifier({ allowDevelopmentBuilds: true }).assertion(publicKeyPEM, 0, clientData, proof), 1);
      // Existing public keys cannot bypass a subsequently disabled policy.
      assert.throws(() => verifier({ allowDevelopmentBuilds: false }).assertion(publicKeyPEM, 0, clientData, proof), invalidProof);
      assert.throws(() => verifier().assertion(publicKeyPEM, 0, clientData, proof), invalidProof);
      assert.throws(() => verifier({ allowDevelopmentBuilds: true }).assertion(publicKeyPEM, 1, clientData, proof), invalidProof);
    }
  }
});

test("development opt-in still rejects unapproved categories, versions, and malformed extensions", () => {
  const cases = [
    ...[0, 1, 5, 6, 10, "3", Buffer.from([0, 0, 0, 3]), Buffer.from([3]), null].map(category =>
      new Map<string, unknown>([["apple_validation_category_01", category], ["apple_bundle_version_01", "17"]])),
    ...["18", "17.0", " 17", 17, null].map(version =>
      new Map<string, unknown>([["apple_validation_category_01", 3], ["apple_bundle_version_01", version]])),
    new Map<string, unknown>([["apple_validation_category_01", 3], ["apple_bundle_version_01", "17"], ["validationCategory", 3]]),
  ];
  for (const extensions of cases) {
    const check = verifier({ allowDevelopmentBuilds: true });
    assert.throws(() => check.attest(keyID, challenge, attestation({ extensions })), invalidProof);
    assert.throws(() => check.assertion(publicKeyPEM, 0, clientData, assertion(1, clientData, { extensions })), invalidProof);
  }
});

test("development-signed proofs retain identity, production environment, signature, and nonce checks", () => {
  const extensions = defaultExtensions();
  extensions.set("apple_validation_category_01", 3);
  const check = verifier({ allowDevelopmentBuilds: true });
  for (const options of [
    { authMutate: (auth: Buffer) => { auth[0]! ^= 1; } },
    { authMutate: (auth: Buffer) => { Buffer.from("appattestdevelop").copy(auth, 37); } },
    { badNonce: true }, { expired: true },
    { receipt: { environment: "development" } },
    { receipt: { badSignature: true } }, { receipt: { differentRoot: true } },
  ]) {
    assert.throws(() => check.attest(keyID, challenge, attestation({ ...options, extensions })), invalidProof);
  }
  const proof = attestation({ extensions });
  assert.throws(() => check.attest(keyID, Buffer.alloc(32), proof), invalidProof);
  assert.throws(() => verifier({ allowDevelopmentBuilds: true, appID: "OTHERAPP00.example.invalid" }).attest(keyID, challenge, proof), invalidProof);
  assert.throws(() => check.attest(keyID, challenge, attestation({ extensions: null })), invalidProof);
  for (const options of [{ wrongRP: true }, { wrongKey: true }, { doubleHash: true }, { extensions: null }]) {
    assert.throws(() => check.assertion(publicKeyPEM, 0, clientData, assertion(1, clientData, { extensions, ...options })), invalidProof);
  }
  assert.throws(() => check.assertion(publicKeyPEM, 0, Buffer.from("different request"), assertion(1, clientData, { extensions })), invalidProof);
});

test("rejects forged/mismatched attestation identity, format, certificate, and challenge", async (t) => {
  const cases: [string, AttestationOptions][] = [
    ["wrong RP", { authMutate: (auth) => { auth[0]! ^= 1; } }],
    ["development AAGUID", { authMutate: (auth) => { Buffer.from("appattestdevelop").copy(auth, 37); } }],
    ["nonzero initial counter", { authMutate: (auth) => { auth.writeUInt32BE(1, 33); } }],
    ["wrong credential", { authMutate: (auth) => { auth[55]! ^= 1; } }],
    ["wrong credential length", { authMutate: (auth) => { auth.writeUInt16BE(31, 53); } }],
    ["unexpected flags", { authMutate: (auth) => { auth[32] = 0xc1; } }],
    ["wrong COSE algorithm", { coseMutate: (cose) => { cose.set(3, -8); } }],
    ["wrong COSE coordinate", { coseMutate: (cose) => { cose.set(-2, Buffer.alloc(32)); } }],
    ["wrong nonce", { badNonce: true }], ["unhashed challenge", { rawChallengeNonce: true }],
    ["expired certificate", { expired: true }], ["future certificate", { future: true }],
    ["wrong leaf EKU", { wrongUsage: true }], ["no digital signature usage", { noDigitalSignature: true }],
    ["CA as attested leaf", { leafCA: true }], ["unknown critical extension", { unknownCritical: true }],
    ["duplicate certificate", { extraCertificate: true }], ["missing validation extensions", { extensions: null }],
  ];
  for (const [name, options] of cases) await t.test(name, () => assert.throws(() => verifier().attest(keyID, challenge, attestation(options)), invalidProof));
  const valid = attestation();
  assert.throws(() => verifier().attest(keyID, Buffer.alloc(32), valid), invalidProof);
  assert.throws(() => verifier().attest(Buffer.alloc(32).toString("base64"), challenge, valid), invalidProof);
  assert.throws(() => verifier().attest(keyID.slice(0, -1), challenge, valid), invalidProof);
  assert.throws(() => verifier({ rootPEM: certificate("Unrelated Root", keyPair(), undefined, { ca: true }).pem }).attest(keyID, challenge, valid), invalidProof);
});

test("rejects unapproved and ambiguous signed launch category/version extensions", () => {
  for (const category of [0, 1, 3, 5, 6, 10, "4", Buffer.from([0, 0, 0, 4]), Buffer.from([4]), null]) {
    const extensions = defaultExtensions();
    extensions.set("apple_validation_category_01", category);
    assert.throws(() => verifier().attest(keyID, challenge, attestation({ extensions })), invalidProof);
  }
  for (const version of ["18", "17.0", " 17", 17, null]) {
    const extensions = defaultExtensions();
    extensions.set("apple_bundle_version_01", version);
    assert.throws(() => verifier().attest(keyID, challenge, attestation({ extensions })), invalidProof);
  }
  const extensions = defaultExtensions();
  extensions.set("validationCategory", 4);
  assert.throws(() => verifier().attest(keyID, challenge, attestation({ extensions })), invalidProof);
});

test("independently rejects invalid receipts despite valid attestation signatures", async (t) => {
  const cases: [string, ReceiptOptions][] = [
    ["wrong app ID", { appID: "OTHERAPP00.example.invalid" }], ["wrong key", { wrongKey: true }],
    ["older than five minutes", { created: now - 300_001 }], ["future creation", { created: now + 1 }],
    ["expired receipt", { expires: now }], ["wrong kind", { kind: "RECEIPT" }],
    ["sandbox receipt", { environment: "development" }], ["forged signature", { badSignature: true }],
    ["wrong signed digest", { signedAttributes: true, badDigest: true }], ["duplicate field", { duplicateField: true }],
    ["missing app ID", { omitField: 2 }], ["missing public key", { omitField: 3 }], ["missing timestamp", { omitField: 12 }],
    ["no receipt signing marker", { noMarker: true }], ["wrong signer identifier", { badSignerID: true }],
    ["expired signing cert", { signerExpired: true }], ["unknown critical extension", { unknownCritical: true }],
    ["forged receipt chain", { differentRoot: true }],
  ];
  for (const [name, receipt] of cases) await t.test(name, () => assert.throws(() => verifier().attest(keyID, challenge, attestation({ receipt })), invalidProof));
  assert.ok(verifier().attest(keyID, challenge, attestation({ receipt: { created: now - 300_000 } })));
});

test("assertion binds canonical request bytes and returns strictly increasing counter", () => {
  assert.equal(verifier().assertion(publicKeyPEM, 0, clientData, assertion(1, clientData)), 1);
  assert.equal(verifier().assertion(publicKeyPEM, 8, clientData, assertion(10, clientData)), 10);
  assert.equal(verifier().assertion(publicKeyPEM, 0xffff_fffe, clientData, assertion(0xffff_ffff, clientData)), 0xffff_ffff);
  const extensions = new Map<string, unknown>([["validationCategory", 4], ["bundleVersion", "17"]]);
  assert.equal(verifier().assertion(publicKeyPEM, 0, clientData, assertion(1, clientData, { extensions })), 1);
});

test("rejects replay, forged request/assertion, wrong RP, missing fields, and double hashing", () => {
  const proof = assertion(1, clientData);
  for (const counter of [1, 2, -1, 0.5, NaN, 0xffff_ffff]) assert.throws(() => verifier().assertion(publicKeyPEM, counter, clientData, proof), invalidProof);
  assert.throws(() => verifier().assertion(publicKeyPEM, 0, Buffer.from("different challenge or request"), proof), invalidProof);
  for (const options of [{ extensions: null }, { wrongRP: true }, { flags: 0xc0 }, { doubleHash: true }, { wrongKey: true }]) {
    assert.throws(() => verifier().assertion(publicKeyPEM, 0, clientData, assertion(1, clientData, options)), invalidProof);
  }
  assert.throws(() => verifier().assertion(publicKeyPEM, 0, clientData, assertion(0, clientData)), invalidProof);
});

test("rejects trailing, malformed, duplicate CBOR keys and bounded oversized proofs without detail", () => {
  const proof = attestation();
  for (const data of [Buffer.concat([proof, encode(null)]), Buffer.from([0xa1]), Buffer.alloc(32_769), Buffer.from("patient: synthetic-secret; arbitrary data")]) {
    assert.throws(() => verifier().attest(keyID, challenge, data), invalidProof);
  }
  const duplicate = Buffer.concat([Buffer.from([0xa2]), encode("signature"), encode(Buffer.alloc(8)), encode("signature"), encode(Buffer.alloc(8))]);
  assert.throws(() => verifier().assertion(publicKeyPEM, 0, clientData, duplicate), invalidProof);
  const decoded = decodeAllSync(proof)[0] as { fmt: string };
  decoded.fmt = "forged";
  assert.throws(() => verifier().attest(keyID, challenge, encode(decoded)), invalidProof);
});

test("pinned production root rejects a completely valid synthetic chain", () => {
  const production = new AppleAppAttestVerifier({ appID, bundleVersions: ["17"], now: () => now });
  assert.throws(() => production.attest(keyID, challenge, attestation()), invalidProof);
  const pinned = new X509Certificate(readFileSync(new URL("../../certs/Apple_App_Attestation_Root_CA.pem", import.meta.url)));
  assert.equal(pinned.fingerprint256, "1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32");
});

test("test trust root cannot be injected when NODE_ENV is production", () => {
  const previous = process.env.NODE_ENV;
  try {
    process.env.NODE_ENV = "production";
    assert.throws(() => verifier(), invalidProof);
  } finally {
    if (previous === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = previous;
  }
});
