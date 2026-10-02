import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { AppleAppAttestVerifier } from './app-attest.js';
import { DeepSeekProvider } from './provider.js';
import { FileMetadataStore } from './store.js';
import { httpServer, ReportService } from './service.js';

function required(name: string) {
  const value = process.env[name]; if (!value) throw new Error(`missing_configuration:${name}`); return value;
}
// Configuration is deployment-owned. There is deliberately no development-auth or fake-provider flag.
try {
  const directory = required('REPORT_STATE_DIR');
  const appID = required('APPLE_APP_ID');
  if (!/^[A-Z0-9]{10}\.[A-Za-z0-9.-]+$/.test(appID)) throw new Error('invalid_app_id');
  const versions = required('APPLE_BUNDLE_VERSIONS').split(',');
  if (!versions.length || versions.some(v => !/^[0-9.]{1,32}$/.test(v))) throw new Error('invalid_bundle_versions');
  const provider = new DeepSeekProvider(required('DEEPSEEK_API_KEY'));
  const verifier = new AppleAppAttestVerifier({ appID, bundleVersions: versions });
  const port = Number(process.env.PORT ?? '8787');
  if (!Number.isSafeInteger(port) || port < 1 || port > 65535) throw new Error('invalid_port');
  const store = new FileMetadataStore(directory);
  const enabled = () => process.env.REPORTS_ENABLED === 'true' && process.env.AI_DISCLOSURE_CONFIRMED === 'true' &&
    !existsSync(join(directory, 'DISABLED'));
  const service = new ReportService({ store, provider, enabled, verifier });
  const server = httpServer(service);
  // TLS terminates at an approved local reverse proxy; never trust X-Forwarded-For from callers.
  server.listen(port, '127.0.0.1');
  const switchCheck = setInterval(() => { if (!enabled()) service.disable(); }, 1000);
  const stop = () => { clearInterval(switchCheck); service.disable(); server.close(() => { store.close(); }); };
  process.once('SIGTERM', stop); process.once('SIGINT', stop);
} catch {
  // Configuration/provider errors can carry credentials; log only this fixed message.
  process.stderr.write('Report service failed closed: check deployment configuration.\n'); process.exitCode = 1;
}
