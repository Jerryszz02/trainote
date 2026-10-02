import { randomBytes, randomUUID } from 'node:crypto';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { z } from 'zod';
import { APIError, digest, hash, policy, renderReport, uuid, validateInput } from './contract.js';
import { reserveOperation, type MetadataStore } from './store.js';
import type { ReportProvider } from './provider.js';

export interface AttestVerifier {
  attest(keyID: string, challenge: Buffer, object: Buffer): { publicKeyPEM: string; receipt: string };
  assertion(publicKeyPEM: string, counter: number, clientData: Buffer, object: Buffer): number;
}
const key = z.string().regex(/^[A-Za-z0-9+/]{43}=$/);
const binary = z.string().min(4).max(100_000).regex(/^[A-Za-z0-9+/]+={0,2}$/);
const intent = z.strictObject({ method: z.enum(['POST', 'PUT', 'DELETE']),
  path: z.enum(['/v1/reports', '/v1/consent']), bodyHash: hash });
const challengeSchema = z.strictObject({ keyID: key, purpose: z.enum(['attest', 'session']), intent: intent.optional() });
const attestSchema = z.strictObject({ keyID: key, challengeID: uuid, attestation: binary });
const sessionSchema = z.strictObject({ keyID: key, challengeID: uuid, assertion: binary });
const consentSchema = z.strictObject({ consentVersion: z.literal(policy.consent), grantedAt: z.number().int().nonnegative() });
type Intent = z.infer<typeof intent>;
interface Challenge { keyID: string; purpose: string; nonce: string; expires: number; epoch: number; intent?: Intent }
interface Session { keyID: string; expires: number; epoch: number; intent: Intent }
export function clientData(challengeID: string, nonce: string, intent: Intent): Buffer {
  return Buffer.from(`trainote-session-v1\n${challengeID}\n${nonce}\n${intent.method}\n${intent.path}\n${intent.bodyHash}`, 'utf8');
}
function parse<T>(schema: z.ZodType<T>, data: unknown): T {
  const result = schema.safeParse(data);
  if (!result.success) throw new APIError(400, 'invalid_contract');
  return result.data;
}
function decode(value: string) {
  const bytes = Buffer.from(value, 'base64');
  if (bytes.toString('base64') !== value) throw new APIError(400, 'invalid_encoding');
  return bytes;
}

export class ReportService {
  private challenges = new Map<string, Challenge>();
  private sessions = new Map<string, Session>();
  private rates = new Map<string, { count: number; until: number }>();
  private jobs = new Map<string, { keyID: string; controller: AbortController }>();
  private storageFault = false;
  private revokedKeys = new Set<string>();
  private readonly clock: () => number;
  constructor(private readonly options: {
    store: MetadataStore; verifier: AttestVerifier; provider: ReportProvider;
    enabled: () => boolean; clock?: () => number; timeoutMS?: number;
  }) { this.clock = options.clock ?? Date.now; }

  /** Emergency switch is checked at admission and before returning any model result. */
  disable() {
    for (const { controller } of this.jobs.values()) controller.abort();
    // Keep removal possible while the switch stays off, including multi-second App Attest handshakes.
    for (const [id, s] of this.sessions) if (s.intent.method !== 'DELETE' || s.intent.path !== '/v1/consent') this.sessions.delete(id);
    for (const [id, c] of this.challenges) if (c.intent?.method !== 'DELETE' || c.intent?.path !== '/v1/consent') this.challenges.delete(id);
  }
  private persist(change: Parameters<MetadataStore['commit']>[0]) {
    try { this.options.store.commit(change); }
    catch (error) { if (!(error instanceof APIError)) this.storageFault = true; throw error; }
  }
  private sweep(now: number) {
    for (const [id, c] of this.challenges) if (c.expires <= now) this.challenges.delete(id);
    for (const [id, s] of this.sessions) if (s.expires <= now) this.sessions.delete(id);
    for (const [ip, r] of this.rates) if (r.until <= now) this.rates.delete(ip);
  }
  private rate(ip: string, now: number) {
    this.sweep(now);
    const current = this.rates.get(ip) ?? { count: 0, until: now + 60_000 };
    if (current.count >= 60 || this.rates.size >= 10_000 && !this.rates.has(ip)) throw new APIError(429, 'request_limit');
    current.count++; this.rates.set(ip, current);
  }
  private takeChallenge(id: string, keyID: string, purpose: string): Challenge {
    const challenge = this.challenges.get(id);
    this.challenges.delete(id); // Consume before any verification, including failures.
    if (!challenge || challenge.keyID !== keyID || challenge.purpose !== purpose || challenge.expires <= this.clock() ||
        challenge.epoch !== (this.options.store.state.installations[keyID]?.epoch ?? 0)) throw new APIError(401, 'invalid_challenge');
    return challenge;
  }
  private authenticate(token: string | undefined, method: string, path: string, body: Buffer): Session {
    const key = digest(token ?? '');
    const session = this.sessions.get(key); this.sessions.delete(key);
    const installation = session && this.options.store.state.installations[session.keyID];
    if (!session || !installation || session.expires <= this.clock() || session.epoch !== installation.epoch ||
        session.intent.method !== method || session.intent.path !== path || session.intent.bodyHash !== digest(body)) {
      throw new APIError(401, 'invalid_session');
    }
    return session;
  }
  async handle(method: string, path: string, body: Buffer, token?: string, ip = 'local', signal?: AbortSignal) {
    const now = this.clock(); this.rate(ip, now);
    if (method === 'GET' && path === '/healthz') return { status: 200, body: { status: 'ok', version: '1' } };
    if (body.byteLength > policy.requestBytes) throw new APIError(413, 'request_too_large');
    let data: unknown;
    try { data = body.length ? JSON.parse(body.toString('utf8')) : {}; } catch { throw new APIError(400, 'invalid_json'); }
    if (path === '/v1/installations/challenge' && method === 'POST') {
      const request = parse(challengeSchema, data);
      if (!this.options.enabled() && !(request.intent?.method === 'DELETE' && request.intent.path === '/v1/consent')) throw new APIError(503, 'reports_disabled');
      if ((request.purpose === 'session') !== !!request.intent) throw new APIError(400, 'invalid_intent');
      if (request.intent && !((request.intent.path === '/v1/reports' && request.intent.method === 'POST') ||
          (request.intent.path === '/v1/consent' && ['PUT', 'DELETE'].includes(request.intent.method)))) throw new APIError(400, 'invalid_intent');
      if (this.challenges.size >= 10_000) throw new APIError(429, 'challenge_limit');
      const installation = this.options.store.state.installations[request.keyID];
      if (request.purpose === 'session' && !installation) throw new APIError(401, 'unknown_installation');
      if (request.purpose === 'attest' && installation) throw new APIError(409, 'installation_exists');
      const challengeID = randomUUID(), challenge = randomBytes(32).toString('base64');
      this.challenges.set(challengeID, { keyID: request.keyID, purpose: request.purpose,
        nonce: challenge, expires: now + policy.challengeTTL, epoch: installation?.epoch ?? 0, intent: request.intent });
      return { status: 200, body: { challengeID, challenge, expiresAt: now + policy.challengeTTL } };
    }
    if (path === '/v1/installations/attest' && method === 'POST') {
      const request = parse(attestSchema, data);
      const challenge = this.takeChallenge(request.challengeID, request.keyID, 'attest');
      if (this.options.store.state.installations[request.keyID]) throw new APIError(409, 'installation_exists');
      if (Object.keys(this.options.store.state.installations).length >= 100_000) throw new APIError(429, 'installation_limit');
      let verified;
      try { verified = this.options.verifier.attest(request.keyID, decode(challenge.nonce), decode(request.attestation)); }
      catch { throw new APIError(401, 'invalid_attestation'); }
      this.persist(state => {
        state.installations[request.keyID] = { keyID: request.keyID, ...verified, counter: 0,
          epoch: 0, quotaDay: '', quotaCount: 0 };
      });
      return { status: 201, body: { registered: true } };
    }
    if (path === '/v1/session' && method === 'POST') {
      const request = parse(sessionSchema, data);
      const challenge = this.takeChallenge(request.challengeID, request.keyID, 'session');
      const installation = this.options.store.state.installations[request.keyID];
      if (!installation || !challenge.intent) throw new APIError(401, 'unknown_installation');
      let counter: number;
      try { counter = this.options.verifier.assertion(installation.publicKeyPEM, installation.counter,
        clientData(request.challengeID, challenge.nonce, challenge.intent), decode(request.assertion)); }
      catch { throw new APIError(401, 'invalid_assertion'); }
      if (counter <= installation.counter) throw new APIError(401, 'invalid_counter');
      this.persist(state => { state.installations[request.keyID]!.counter = counter; });
      if (this.sessions.size >= 10_000) throw new APIError(429, 'session_limit');
      const token = randomBytes(32).toString('base64url');
      this.sessions.set(digest(token), { keyID: request.keyID, expires: now + policy.sessionTTL,
        epoch: installation.epoch, intent: challenge.intent });
      return { status: 200, body: { token, expiresAt: now + policy.sessionTTL } };
    }
    if (!((path === '/v1/consent' && ['PUT', 'DELETE'].includes(method)) ||
          (path === '/v1/reports' && method === 'POST'))) throw new APIError(404, 'not_found');
    const session = this.authenticate(token, method, path, body);
    if (path === '/v1/consent' && method === 'DELETE') {
      parse(z.strictObject({}), data);
      this.revokedKeys.add(session.keyID);
      for (const [key, s] of this.sessions) if (s.keyID === session.keyID) this.sessions.delete(key);
      for (const [key, c] of this.challenges) if (c.keyID === session.keyID) this.challenges.delete(key);
      for (const job of this.jobs.values()) if (job.keyID === session.keyID) job.controller.abort();
      this.persist(state => {
        const installation = state.installations[session.keyID]!;
        delete installation.consentVersion; delete installation.consentGrantedAt; installation.epoch++;
      });
      return { status: 200, body: { revoked: true } };
    }
    if (!this.options.enabled() || this.storageFault) throw new APIError(503, 'reports_disabled');
    if (path === '/v1/consent') {
      const consent = parse(consentSchema, data);
      if (consent.grantedAt > now + 60_000) throw new APIError(400, 'invalid_consent_date');
      this.persist(state => {
        state.installations[session.keyID]!.consentVersion = consent.consentVersion;
        state.installations[session.keyID]!.consentGrantedAt = consent.grantedAt;
      });
      this.revokedKeys.delete(session.keyID);
      return { status: 200, body: { consentVersion: consent.consentVersion } };
    }
    if (this.revokedKeys.has(session.keyID) || this.options.store.state.installations[session.keyID]!.consentVersion !== policy.consent) throw new APIError(403, 'consent_required');
    if (signal?.aborted) throw new APIError(499, 'cancelled');
    const request = validateInput(data, now);
    if ([...this.jobs.values()].some(j => j.keyID === session.keyID) || this.jobs.size >= 20) throw new APIError(429, 'report_busy');
    try { reserveOperation(this.options.store, session.keyID, request.requestID, digest(body), now); }
    catch (error) { if (!(error instanceof APIError)) this.storageFault = true; throw error; }
    const controller = new AbortController();
    const cancel = () => controller.abort(); signal?.addEventListener('abort', cancel, { once: true });
    const operation = `${session.keyID}:${request.requestID}`;
    this.jobs.set(operation, { keyID: session.keyID, controller });
    const timeout = setTimeout(cancel, this.options.timeoutMS ?? policy.timeoutMS);
    try {
      const cancelled = new Promise<never>((_, reject) => controller.signal.addEventListener('abort',
        () => reject(new APIError(504, 'report_cancelled_or_timed_out')), { once: true }));
      const draft = await Promise.race([this.options.provider.generate(request.input, controller.signal), cancelled]);
      if (controller.signal.aborted || !this.options.enabled() || this.storageFault || this.revokedKeys.has(session.keyID) ||
          this.options.store.state.installations[session.keyID]!.epoch !== session.epoch ||
          this.options.store.state.installations[session.keyID]!.consentVersion !== policy.consent) throw new APIError(403, 'consent_changed');
      const report = renderReport(draft, request.input, this.clock());
      this.persist(state => { state.operations[operation]!.status = 'completed'; });
      return { status: 200, body: report };
    } catch (error) {
      this.persist(state => { state.operations[operation]!.status = 'failed'; });
      if (error instanceof APIError) throw error;
      throw new APIError(502, 'provider_unavailable');
    } finally {
      clearTimeout(timeout); signal?.removeEventListener('abort', cancel); this.jobs.delete(operation);
    }
  }
}

export function httpServer(service: ReportService) {
  return createServer({ requestTimeout: 30_000, headersTimeout: 10_000, maxHeaderSize: 8192 },
    async (req: IncomingMessage, res: ServerResponse) => {
      const controller = new AbortController();
      res.on('close', () => { if (!res.writableEnded) controller.abort(); });
      let size = 0;
      const chunks: Buffer[] = [];
      try {
        if (req.method !== 'GET' && req.headers['content-type'] !== 'application/json') throw new APIError(400, 'content_type_required');
        if (req.headers['content-encoding']) throw new APIError(400, 'compressed_body_unsupported');
        for await (const chunk of req) {
          size += chunk.length;
          if (size > policy.requestBytes) throw new APIError(413, 'request_too_large');
          chunks.push(chunk);
        }
        const authorization = req.headers.authorization;
        const token = authorization?.startsWith('Bearer ') ? authorization.slice(7) : undefined;
        const result = await service.handle(req.method ?? '', req.url ?? '', Buffer.concat(chunks), token,
          req.socket.remoteAddress ?? 'unknown', controller.signal);
        res.writeHead(result.status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
        res.end(JSON.stringify(result.body));
      } catch (error) {
        const safe = error instanceof APIError ? error : new APIError(500, 'internal_error');
        res.writeHead(safe.status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
        res.end(JSON.stringify({ error: safe.code }));
      }
      // No access/body/error-object logging. Reverse-proxy logging must follow the same policy.
    });
}
