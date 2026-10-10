import { createHash, createPublicKey, timingSafeEqual, verify, X509Certificate, type KeyObject } from "node:crypto";
import { readFileSync } from "node:fs";
import * as asn1 from "asn1js";
import cborLibrary from "cbor";

const SHA256 = "2.16.840.1.101.3.4.2.1";
const DATA = "1.2.840.113549.1.7.1";
const SIGNED_DATA = "1.2.840.113549.1.7.2";
const ECDSA_SHA256 = "1.2.840.10045.4.3.2";
const NONCE = "1.2.840.113635.100.8.2";
const ATTEST_KEY_USAGE = "1.2.840.113635.100.4.24";
const RECEIPT_SIGNING = "1.2.840.113635.100.12.15";
const PRODUCTION_AAGUID = Buffer.concat([Buffer.from("appattest"), Buffer.alloc(7)]);
const MAX_OBJECT_BYTES = 32_768;
const ERROR = "Invalid App Attest proof";

// Public trust anchor, downloaded from Apple's certificate authority on 2026-10-03.
// Receipts use Apple Root CA G3, NOT the private App Attestation Root CA.
const APPLE_RECEIPT_ROOT = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`;

type ASN = asn1.BaseBlock;
type Extension = { critical: boolean; value: Buffer };
export interface AppleAppAttestConfig {
  /** App ID prefix + period + bundle ID; this is not always the Team ID. */
  appID: string;
  /** Exact CFBundleVersion values permitted by the server release policy. */
  bundleVersions: string[];
  /** Explicit server policy: also accept development-signed builds using production App Attest. */
  allowDevelopmentBuilds?: boolean;
  /** Synthetic trust root injection, restricted to node:test; never server configuration. */
  rootPEM?: string;
  now?: () => number;
}

function requireThat(condition: unknown): asserts condition {
  if (!condition) throw new Error(ERROR);
}
function equal(left: Buffer, right: Buffer): boolean {
  return left.length === right.length && timingSafeEqual(left, right);
}
function hash(bytes: Buffer): Buffer { return createHash("sha256").update(bytes).digest(); }
function raw(node: ASN): Buffer { return Buffer.from(node.valueBeforeDecodeView); }
function parse(bytes: Buffer): ASN {
  requireThat(bytes.length > 0 && bytes.length <= MAX_OBJECT_BYTES);
  const decoded = asn1.fromBER(bytes);
  requireThat(decoded.offset === bytes.length && !decoded.result.error);
  return decoded.result;
}
function sequence(node: ASN | undefined): ASN[] {
  requireThat(node instanceof asn1.Sequence);
  return node.valueBlock.value;
}
function set(node: ASN | undefined): ASN[] {
  requireThat(node instanceof asn1.Set);
  return node.valueBlock.value;
}
function tagged(node: ASN | undefined, tag: number): ASN[] {
  requireThat(node instanceof asn1.Constructed && node.idBlock.tagClass === 3 && node.idBlock.tagNumber === tag);
  return node.valueBlock.value;
}
function isTag(node: ASN | undefined, tag: number): boolean {
  return node?.idBlock.tagClass === 3 && node.idBlock.tagNumber === tag;
}
function oid(node: ASN | undefined): string {
  requireThat(node instanceof asn1.ObjectIdentifier);
  return node.valueBlock.toString();
}
function integer(node: ASN | undefined): number {
  requireThat(node instanceof asn1.Integer && !node.valueBlock.isHexOnly);
  const result = node.valueBlock.valueDec;
  requireThat(Number.isSafeInteger(result) && result >= 0);
  return result;
}
function octets(node: ASN | undefined): Buffer {
  requireThat(node instanceof asn1.OctetString);
  return node.idBlock.isConstructed
    ? Buffer.concat(node.valueBlock.value.map(octets))
    : Buffer.from(node.valueBlock.valueHexView);
}
function exactMap(value: unknown, keys: (string | number)[]): Map<unknown, unknown> {
  requireThat(value instanceof Map && value.size === keys.length && keys.every((key) => value.has(key)));
  return value;
}
function buffer(value: unknown, min = 1, max = MAX_OBJECT_BYTES): Buffer {
  requireThat(Buffer.isBuffer(value) && value.length >= min && value.length <= max);
  return value;
}
function cbor(bytes: Buffer): unknown[] {
  requireThat(bytes.length > 0 && bytes.length <= MAX_OBJECT_BYTES);
  return cborLibrary.decodeAllSync(bytes, { preferMap: true, preventDuplicateKeys: true, max_depth: 12 }) as unknown[];
}
function certificateParts(cert: X509Certificate): { issuer: Buffer; serial: Buffer; extensions: Map<string, Extension> } {
  const top = sequence(parse(cert.raw));
  requireThat(top.length === 3);
  const tbs = sequence(top[0]);
  requireThat(integer(tagged(tbs[0], 0)[0]) === 2); // X.509 v3
  requireThat(tbs[1] instanceof asn1.Integer && tbs[3] !== undefined);
  const extensions = new Map<string, Extension>();
  const wrapper = tbs.find((node) => isTag(node, 3));
  requireThat(wrapper !== undefined);
  for (const item of sequence(tagged(wrapper, 3)[0])) {
    const fields = sequence(item);
    requireThat(fields.length === 2 || fields.length === 3);
    const name = oid(fields[0]);
    requireThat(!extensions.has(name));
    const critical = fields.length === 3;
    if (critical) requireThat(fields[1] instanceof asn1.Boolean && fields[1].valueBlock.value);
    extensions.set(name, { critical, value: octets(fields.at(-1)) });
  }
  const signatureOID = oid(sequence(top[1])[0]);
  const tbsSignatureOID = oid(sequence(tbs[2])[0]);
  requireThat(signatureOID === tbsSignatureOID && [ECDSA_SHA256, "1.2.840.10045.4.3.3", "1.2.840.10045.4.3.4"].includes(signatureOID));
  return { issuer: raw(tbs[3]), serial: raw(tbs[1]), extensions };
}
function checkCertificate(cert: X509Certificate, isCA: boolean, caBelow: number, now: number): void {
  requireThat(Number.isFinite(now) && Date.parse(cert.validFrom) <= now && now <= Date.parse(cert.validTo) && cert.ca === isCA);
  const { extensions } = certificateParts(cert);
  // Critical extensions that this validator does not process cannot be ignored.
  for (const [name, extension] of extensions) {
    requireThat(!extension.critical || ["2.5.29.19", "2.5.29.15", "2.5.29.37"].includes(name));
  }
  const constraints = extensions.get("2.5.29.19");
  const usage = extensions.get("2.5.29.15");
  requireThat(constraints !== undefined && constraints.critical && usage !== undefined);
  const basic = sequence(parse(constraints.value));
  requireThat(basic.length <= 2);
  const ca = basic[0] instanceof asn1.Boolean && basic[0].valueBlock.value;
  requireThat(Boolean(ca) === isCA);
  if (basic.length === 2) requireThat(isCA && integer(basic[1]) >= caBelow);
  const bits = parse(usage.value);
  requireThat(bits instanceof asn1.BitString && bits.valueBlock.valueHexView.length > 0);
  requireThat(((bits.valueBlock.valueHexView[0] ?? 0) & (isCA ? 0x04 : 0x80)) !== 0);
}
function checkChain(leaf: X509Certificate, certificates: X509Certificate[], root: X509Certificate, now: number): void {
  requireThat(certificates.length <= 5 && !leaf.raw.equals(root.raw));
  requireThat(new Set([leaf, ...certificates].map((cert) => cert.fingerprint256)).size === certificates.length + 1);
  const used = new Set<string>();
  let current = leaf;
  for (let depth = 0; depth < 5; depth++) {
    requireThat(!used.has(current.fingerprint256));
    used.add(current.fingerprint256);
    checkCertificate(current, depth > 0, Math.max(0, depth - 1), now);
    if (current.raw.equals(root.raw)) {
      requireThat(current.checkIssued(root) && current.verify(root.publicKey));
      requireThat(certificates.every((cert) => used.has(cert.fingerprint256)));
      return;
    }
    const issuers = [...certificates.filter((cert) => !cert.raw.equals(root.raw)), root]
      .filter((cert) => !used.has(cert.fingerprint256) && current.checkIssued(cert) && current.verify(cert.publicKey));
    requireThat(issuers.length === 1);
    current = issuers[0]!;
  }
  throw new Error(ERROR);
}
function point(key: KeyObject): Buffer {
  requireThat(key.asymmetricKeyType === "ec" && key.asymmetricKeyDetails?.namedCurve === "prime256v1");
  const jwk = key.export({ format: "jwk" });
  requireThat(jwk.kty === "EC" && jwk.crv === "P-256" && typeof jwk.x === "string" && typeof jwk.y === "string");
  const x = Buffer.from(jwk.x, "base64url"), y = Buffer.from(jwk.y, "base64url");
  requireThat(x.length === 32 && y.length === 32);
  return Buffer.concat([Buffer.from([4]), x, y]);
}
function algorithm(node: ASN | undefined, expected: string): void {
  const fields = sequence(node);
  requireThat((fields.length === 1 || (fields.length === 2 && fields[1] instanceof asn1.Null)) && oid(fields[0]) === expected);
}
function utf8(bytes: Buffer): string { return new TextDecoder("utf-8", { fatal: true }).decode(bytes); }
function timestamp(bytes: Buffer): number {
  const text = utf8(bytes);
  requireThat(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(text));
  const millis = Date.parse(text);
  requireThat(Number.isFinite(millis) && new Date(millis).toISOString() === text.replace(/(?<!\.\d{3})Z$/, ".000Z"));
  return millis;
}

/** No network, logs, credentials, counters, or request-body persistence live here. */
export class AppleAppAttestVerifier {
  private readonly appID: string;
  private readonly rpID: Buffer;
  private readonly versions: ReadonlySet<string>;
  private readonly allowDevelopmentBuilds: boolean;
  private readonly root: X509Certificate;
  private readonly receiptRoot: X509Certificate;
  private readonly now: () => number;

  constructor(config: AppleAppAttestConfig) {
    requireThat(/^[A-Z0-9]{10}\.[A-Za-z0-9.-]+$/.test(config.appID));
    requireThat(config.bundleVersions.length > 0 && config.bundleVersions.length <= 20 && config.bundleVersions.every((version) => /^[A-Za-z0-9.-]{1,64}$/.test(version)));
    requireThat(config.allowDevelopmentBuilds === undefined || typeof config.allowDevelopmentBuilds === "boolean");
    // This seam is solely for synthetic certificate tests, never a production setting.
    requireThat(config.rootPEM === undefined || (Boolean(process.env.NODE_TEST_CONTEXT) && process.env.NODE_ENV !== "production"));
    this.appID = config.appID;
    this.rpID = hash(Buffer.from(config.appID));
    this.versions = new Set(config.bundleVersions);
    this.allowDevelopmentBuilds = config.allowDevelopmentBuilds === true;
    this.root = new X509Certificate(config.rootPEM ?? readFileSync(new URL("../../certs/Apple_App_Attestation_Root_CA.pem", import.meta.url)));
    this.receiptRoot = new X509Certificate(config.rootPEM ?? APPLE_RECEIPT_ROOT);
    if (config.rootPEM === undefined) {
      requireThat(this.root.fingerprint256 === "1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32");
      requireThat(this.receiptRoot.fingerprint256 === "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79");
    }
    this.now = config.now ?? Date.now;
  }

  attest(keyID: string, challenge: Buffer, object: Buffer): { publicKeyPEM: string; receipt: string } {
    try {
      requireThat(/^[A-Za-z0-9+/]{43}=$/.test(keyID));
      const keyHash = Buffer.from(keyID, "base64");
      requireThat(keyHash.length === 32 && keyHash.toString("base64") === keyID);
      buffer(challenge, 16, 128);
      const objects = cbor(buffer(object));
      requireThat(objects.length === 1);
      const decoded = exactMap(objects[0], ["fmt", "attStmt", "authData"]);
      requireThat(decoded.get("fmt") === "apple-appattest");
      const statement = exactMap(decoded.get("attStmt"), ["x5c", "receipt"]);
      const x5c = statement.get("x5c");
      requireThat(Array.isArray(x5c) && x5c.length >= 2 && x5c.length <= 4);
      const certs = x5c.map((value) => new X509Certificate(buffer(value, 128, 8_192)));
      const leaf = certs[0]!;
      const now = this.now();
      checkChain(leaf, certs.slice(1), this.root, now);
      const auth = buffer(decoded.get("authData"), 88, 4_096);
      requireThat(equal(auth.subarray(0, 32), this.rpID) && auth.readUInt32BE(33) === 0);
      requireThat((auth[32]! & 0x7f) === 0x40 && equal(auth.subarray(37, 53), PRODUCTION_AAGUID));
      requireThat(auth.readUInt16BE(53) === 32 && equal(auth.subarray(55, 87), keyHash));
      const suffix = cbor(auth.subarray(87));
      requireThat(suffix.length === 2);
      const cose = exactMap(suffix[0], [1, 3, -1, -2, -3]);
      requireThat(cose.get(1) === 2 && cose.get(3) === -7 && cose.get(-1) === 1);
      const keyPoint = point(leaf.publicKey);
      requireThat(equal(hash(keyPoint), keyHash));
      requireThat(equal(keyPoint, Buffer.concat([Buffer.from([4]), buffer(cose.get(-2), 32, 32), buffer(cose.get(-3), 32, 32)])));
      this.checkExtensions(suffix[1], false);
      const { extensions } = certificateParts(leaf);
      const nonce = extensions.get(NONCE), keyUsage = extensions.get("2.5.29.37");
      requireThat(nonce !== undefined && keyUsage !== undefined);
      requireThat(sequence(parse(keyUsage.value)).some((value) => oid(value) === ATTEST_KEY_USAGE));
      const nonceSequence = sequence(parse(nonce.value));
      requireThat(nonceSequence.length === 1);
      const nonceValue = tagged(nonceSequence[0], 1);
      requireThat(nonceValue.length === 1 && equal(octets(nonceValue[0]), hash(Buffer.concat([auth, hash(challenge)]))));
      const receipt = buffer(statement.get("receipt"), 128);
      this.checkReceipt(receipt, leaf.publicKey, now);
      return { publicKeyPEM: leaf.publicKey.export({ format: "pem", type: "spki" }).toString(), receipt: receipt.toString("base64") };
    } catch {
      // Do not leak parser errors, certificate details, challenges, or attacker-controlled data.
      throw new Error(ERROR);
    }
  }

  /** Caller supplies its canonical expected clientData including the one-time challenge,
   * and atomically consumes that challenge + commits the returned counter before use. */
  assertion(publicKeyPEM: string, counter: number, clientData: Buffer, object: Buffer): number {
    try {
      requireThat(Number.isInteger(counter) && counter >= 0 && counter < 0xffff_ffff);
      buffer(clientData, 1, 8_192);
      const objects = cbor(buffer(object));
      requireThat(objects.length === 1);
      const decoded = exactMap(objects[0], ["signature", "authenticatorData"]);
      const auth = buffer(decoded.get("authenticatorData"), 38, 4_096);
      requireThat(equal(auth.subarray(0, 32), this.rpID) && (auth[32]! & 0x7f) === 0);
      const next = auth.readUInt32BE(33);
      requireThat(next > counter);
      const extensions = cbor(auth.subarray(37));
      requireThat(extensions.length === 1);
      this.checkExtensions(extensions[0], true);
      const key = createPublicKey(publicKeyPEM);
      point(key);
      // Node's ECDSA verifier hashes this composite once, producing Apple's nonce.
      // Passing hash(composite) to verify("sha256") would incorrectly hash it twice.
      requireThat(verify("sha256", Buffer.concat([auth, hash(clientData)]), key, buffer(decoded.get("signature"), 8, 80)));
      return next;
    } catch {
      throw new Error(ERROR);
    }
  }

  private checkExtensions(value: unknown, assertion: boolean): void {
    requireThat(value instanceof Map);
    const names = assertion && value.has("validationCategory")
      ? ["validationCategory", "bundleVersion"] : ["apple_validation_category_01", "apple_bundle_version_01"];
    const extensions = exactMap(value, names);
    const rawCategory = extensions.get(names[0]);
    const category = Buffer.isBuffer(rawCategory) && rawCategory.length === 4 ? rawCategory.readUInt32LE() : rawCategory;
    // Development signing is an explicit policy choice, never an authentication bypass.
    // This check runs for registration AND each assertion, including previously registered keys.
    requireThat(category === 2 || category === 4 || (category === 3 && this.allowDevelopmentBuilds));
    const version = extensions.get(names[1]);
    requireThat(typeof version === "string" && this.versions.has(version));
  }

  private checkReceipt(receipt: Buffer, attestedKey: KeyObject, now: number): void {
    const contentInfo = sequence(parse(receipt));
    requireThat(contentInfo.length === 2 && oid(contentInfo[0]) === SIGNED_DATA);
    const wrapper = tagged(contentInfo[1], 0);
    requireThat(wrapper.length === 1);
    const signedData = sequence(wrapper[0]);
    requireThat(signedData.length === 5 && integer(signedData[0]) === 1);
    const digests = set(signedData[1]);
    requireThat(digests.length === 1);
    algorithm(digests[0], SHA256);
    const encapsulated = sequence(signedData[2]);
    requireThat(encapsulated.length === 2 && oid(encapsulated[0]) === DATA);
    const content = tagged(encapsulated[1], 0);
    requireThat(content.length === 1);
    const payload = octets(content[0]);
    const certificateNodes = tagged(signedData[3], 0);
    requireThat(certificateNodes.length >= 2 && certificateNodes.length <= 5);
    const certificates = certificateNodes.map((node) => new X509Certificate(raw(node)));
    const signers = set(signedData[4]);
    requireThat(signers.length === 1);
    const signer = sequence(signers[0]);
    requireThat((signer.length === 5 || signer.length === 6) && integer(signer[0]) === 1);
    const identifier = sequence(signer[1]);
    requireThat(identifier.length === 2 && identifier[0] !== undefined && identifier[1] instanceof asn1.Integer);
    const matches = certificates.filter((cert) => {
      const parts = certificateParts(cert);
      return equal(parts.issuer, raw(identifier[0]!)) && equal(parts.serial, raw(identifier[1]!));
    });
    requireThat(matches.length === 1);
    const leaf = matches[0]!;
    checkChain(leaf, certificates.filter((cert) => cert !== leaf), this.receiptRoot, now);
    requireThat(certificateParts(leaf).extensions.has(RECEIPT_SIGNING));
    algorithm(signer[2], SHA256);
    let signedBytes = payload;
    let signatureIndex = 4;
    if (isTag(signer[3], 0)) {
      requireThat(signer.length === 6);
      const attributes = new Map<string, ASN[]>();
      for (const attribute of tagged(signer[3], 0)) {
        const fields = sequence(attribute);
        requireThat(fields.length === 2 && !attributes.has(oid(fields[0])));
        attributes.set(oid(fields[0]), set(fields[1]));
      }
      const contentType = attributes.get("1.2.840.113549.1.9.3");
      const digest = attributes.get("1.2.840.113549.1.9.4");
      requireThat(contentType?.length === 1 && oid(contentType[0]) === DATA);
      requireThat(digest?.length === 1 && equal(octets(digest[0]), hash(payload)));
      signedBytes = raw(signer[3]!);
      requireThat(signedBytes[0] === 0xa0 && signedBytes[1] !== 0x80);
      signedBytes[0] = 0x31; // CMS signs the DER SET OF, not the IMPLICIT [0] tag.
      signatureIndex = 5;
    } else requireThat(signer.length === 5);
    algorithm(signer[signatureIndex - 1], ECDSA_SHA256);
    requireThat(verify("sha256", signedBytes, leaf.publicKey, octets(signer[signatureIndex])));
    const fields = new Map<number, Buffer>();
    const attributes = set(parse(payload));
    requireThat(attributes.length <= 32);
    for (const attribute of attributes) {
      const values = sequence(attribute);
      requireThat(values.length === 3 && integer(values[1]) === 1);
      const type = integer(values[0]);
      requireThat(!fields.has(type));
      fields.set(type, octets(values[2]));
    }
    const app = fields.get(2), key = fields.get(3), kind = fields.get(6), created = fields.get(12);
    requireThat(app !== undefined && key !== undefined && kind !== undefined && created !== undefined);
    requireThat(utf8(app) === this.appID && utf8(kind) === "ATTEST");
    const createdAt = timestamp(created);
    requireThat(createdAt <= now && createdAt >= now - 5 * 60_000);
    // Apple sends a DER certificate in field 3 (not an X9.62 point).
    const receiptKey = new X509Certificate(key).publicKey;
    requireThat(equal(point(receiptKey), point(attestedKey)));
    const environment = fields.get(7), expires = fields.get(21);
    if (environment !== undefined) requireThat(utf8(environment) === "production");
    if (expires !== undefined) requireThat(timestamp(expires) > now);
  }
}
