import { mkdirSync, openSync, closeSync, fsyncSync, writeFileSync, renameSync, readFileSync,
  unlinkSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { APIError, policy } from './contract.js';

export interface Installation {
  keyID: string; publicKeyPEM: string; receipt: string; counter: number; epoch: number;
  consentVersion?: string; consentGrantedAt?: number;
  quotaDay: string; quotaCount: number;
}
interface Operation { digest: string; expires: number; status: 'started' | 'completed' | 'failed' }
export interface State {
  version: 1; installations: Record<string, Installation>; operations: Record<string, Operation>;
}
export interface MetadataStore { state: State; commit(change: (state: State) => void): void }

/** Single-process durable metadata. No request/response body, tokens, IPs, names or measurements. */
export class FileMetadataStore implements MetadataStore {
  state: State;
  private readonly path: string;
  private readonly lock: string;
  constructor(private readonly directory: string) {
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    this.path = join(directory, 'metadata.json');
    this.lock = join(directory, 'process.lock');
    // A crash leaves the lock. An operator verifies that no owner is alive before removing it.
    const lockFD = openSync(this.lock, 'wx', 0o600);
    writeFileSync(lockFD, String(process.pid)); closeSync(lockFD);
    try {
      this.state = existsSync(this.path) ? JSON.parse(readFileSync(this.path, 'utf8')) : emptyState();
      if (this.state.version !== 1 || !this.state.installations || !this.state.operations) throw new Error();
      // A restart must not revive a grant whose revocation failed to persist before a crash.
      // The app re-registers consent from a live local lease before each new report.
      this.commit(state => {
        for (const installation of Object.values(state.installations)) {
          delete installation.consentVersion; delete installation.consentGrantedAt; installation.epoch++;
        }
      });
    } catch { unlinkSync(this.lock); throw new Error('invalid_metadata_store'); }
  }
  commit(change: (state: State) => void): void {
    const next = structuredClone(this.state); change(next);
    const temp = this.path + '.next';
    const fd = openSync(temp, 'w', 0o600);
    try { writeFileSync(fd, JSON.stringify(next)); fsyncSync(fd); } finally { closeSync(fd); }
    renameSync(temp, this.path);
    const directoryFD = openSync(this.directory, 'r');
    try { fsyncSync(directoryFD); } finally { closeSync(directoryFD); }
    this.state = next;
  }
  close() { if (existsSync(this.lock)) unlinkSync(this.lock); }
}
export const emptyState = (): State => ({ version: 1, installations: {}, operations: {} });
export function reserveOperation(store: MetadataStore, keyID: string, requestID: string, bodyHash: string, now: number) {
  store.commit(state => {
    for (const [key, entry] of Object.entries(state.operations)) if (entry.expires <= now) delete state.operations[key];
    const key = `${keyID}:${requestID}`;
    const old = state.operations[key];
    if (old) throw new APIError(409, old.digest === bodyHash ? 'request_already_processed' : 'idempotency_conflict');
    const installation = state.installations[keyID]!;
    const day = new Date(now).toISOString().slice(0, 10);
    if (installation.quotaDay !== day) { installation.quotaDay = day; installation.quotaCount = 0; }
    if (installation.quotaCount >= policy.dailyQuota) throw new APIError(429, 'daily_quota');
    installation.quotaCount++;
    state.operations[key] = { digest: bodyHash, expires: now + policy.idempotencyTTL, status: 'started' };
  });
}
