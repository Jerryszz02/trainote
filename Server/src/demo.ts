import { readFileSync } from 'node:fs';
import { policy, renderReport, validateInput } from './contract.js';
import { DeepSeekProvider } from './provider.js';

// Offline contract/provider demonstration, never a listening server or authentication bypass.
const fixture = JSON.parse(readFileSync(new URL('../../../TrainoteTests/Fixtures/ai-report-contract.json', import.meta.url), 'utf8'));
const now = fixture.envelope.input.asOf;
const envelope = validateInput(fixture.envelope, now);
const provider = new DeepSeekProvider('synthetic-not-a-credential', (async () => new Response(JSON.stringify({
  choices: [{ finish_reason: 'stop', message: { content: JSON.stringify(fixture.draft) } }],
}))) as typeof fetch);
const result = renderReport(await provider.generate(envelope.input, new AbortController().signal), envelope.input, now);
process.stdout.write(JSON.stringify({ mode: 'synthetic-offline', schema: policy.schema,
  observations: result.observations.length, recommendations: result.recommendations.length, validated: true }) + '\n');
