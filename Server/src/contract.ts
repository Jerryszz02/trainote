import { createHash, randomUUID } from 'node:crypto';
import { z } from 'zod';

export const policy = Object.freeze({
  schema: 1, prompt: 'report-selection-v1', knowledge: 'health-evidence-v1',
  consent: 'ai-report-v1', model: 'deepseek-flash', requestBytes: 128 * 1024,
  responseBytes: 32 * 1024, timeoutMS: 25_000, dailyQuota: 5, reportTTL: 6 * 3600_000,
  challengeTTL: 120_000, sessionTTL: 120_000, idempotencyTTL: 10 * 60_000,
});
export class APIError extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}
export const digest = (data: string | Buffer): string => createHash('sha256').update(data).digest('hex');
export const id = z.string().regex(/^[A-Za-z0-9_.:-]{1,128}$/);
const calculationVersion = z.string().regex(/^[A-Za-z0-9_.:+-]{1,128}$/);
const factID = z.string().regex(/^f[0-9]{1,3}$/);
const actionID = z.string().regex(/^a[0-9]{1,2}$/);
export const hash = z.string().regex(/^[a-f0-9]{64}$/);
export const uuid = z.string().uuid();
const timestamp = z.number().int().nonnegative().max(9e15);
export const units = z.enum(['kilograms', 'centimeters', 'kilocalories', 'grams', 'seconds',
  'milliseconds', 'beatsPerMinute', 'count', 'percent', 'score', 'kilogramsPerWeek', 'percentPerWeek', 'none']);
const quality = z.enum(['missing', 'insufficientHistory', 'partial', 'estimated', 'unknownExercise',
  'unknownRIR', 'unknownSetRole', 'stale', 'readFailed', 'sourceConflict', 'requiresReview']);
const muscle = z.enum(['chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms', 'core',
  'glutes', 'quads', 'hamstrings', 'calves']);
export const action = z.enum(['keepPlan', 'reduceSets', 'increaseRIR', 'swapTrainingDay', 'rest',
  'lightActivity', 'choosePlan', 'reviewNutrition']);
export const factSchema = z.strictObject({
  id: factID, metric: id, value: z.number().min(-1e12).max(1e12).nullable(), unit: units,
  window: z.strictObject({ start: timestamp, end: timestamp }), quality: z.array(quality).max(12),
});
export const candidateSchema = z.strictObject({
  actionID, action, muscleIDs: z.array(muscle).max(11), reasonFactIDs: z.array(factID).max(100),
});
export const inputSchema = z.strictObject({
  schemaVersion: z.literal(1), reportType: z.enum(['today', 'trend', 'recovery', 'weekly']),
  asOf: timestamp, inputFingerprint: hash, facts: z.array(factSchema).max(100),
  candidates: z.array(candidateSchema).max(12), goalDirection: z.enum(['maintain', 'lose', 'gain']).nullable(),
  knowledgeVersion: z.literal(policy.knowledge), calculationVersions: z.array(calculationVersion).min(1).max(8),
  missingData: z.array(id).max(32),
});
export const envelopeSchema = z.strictObject({
  schemaVersion: z.literal(1), requestID: uuid, reportType: inputSchema.shape.reportType,
  inputFingerprint: hash, consentVersion: z.literal(policy.consent), input: inputSchema,
});
export type ReportInput = z.infer<typeof inputSchema>;
export type Envelope = z.infer<typeof envelopeSchema>;
export type Fact = z.infer<typeof factSchema>;
export const draftSchema = z.strictObject({
  observations: z.array(z.strictObject({ evidenceID: factID,
    kind: z.enum(['recorded', 'limited', 'missing']) })).max(3),
  actionIDs: z.array(actionID).max(3),
});
export type Draft = z.infer<typeof draftSchema>;
export const kindFor = (fact: Fact): 'recorded' | 'limited' | 'missing' =>
  fact.value === null ? 'missing' : fact.quality.length ? 'limited' : 'recorded';
export const summaryFor = (input: ReportInput): string => input.facts.some(f => f.value !== null)
  ? '根据当前记录，可查看以下事实与候选建议。' : '当前记录不足，补充记录后再看变化。';
export const observationText = (fact: Fact): string => fact.value === null
  ? `暂无可用记录：{{fact:${fact.id}}}。`
  : `${fact.quality.length ? '记录仍有缺失或估计：' : '记录值：'}{{fact:${fact.id}}}。`;
export const actionText: Record<z.infer<typeof action>, string> = {
  keepPlan: '可保持原训练计划。', reduceSets: '可按规则候选减少工作组。',
  increaseRIR: '可按规则候选增加保留次数。', swapTrainingDay: '可考虑调换训练日。',
  rest: '可考虑休息。', lightActivity: '可考虑轻活动。',
  choosePlan: '先选择训练模板或目标。', reviewNutrition: '可复核当前营养目标与执行记录。',
};
export function validateInput(raw: unknown, now: number): Envelope {
  const parsed = envelopeSchema.safeParse(raw);
  if (!parsed.success) throw new APIError(400, 'invalid_contract');
  const envelope = parsed.data, input = envelope.input;
  const factIDs = new Set(input.facts.map(f => f.id));
  if (envelope.reportType !== input.reportType || envelope.inputFingerprint !== input.inputFingerprint ||
      input.asOf > now + 60_000 || input.asOf < now - 24 * 3600_000 ||
      factIDs.size !== input.facts.length || new Set(input.candidates.map(c => c.actionID)).size !== input.candidates.length ||
      input.facts.some(f => f.window.start > f.window.end || f.window.end > input.asOf + 60_000) ||
      input.candidates.some(c => c.reasonFactIDs.some(id => !factIDs.has(id)))) {
    throw new APIError(400, 'invalid_facts');
  }
  return envelope;
}
export function renderReport(raw: unknown, input: ReportInput, now: number) {
  const parsed = draftSchema.safeParse(raw);
  if (!parsed.success) throw new APIError(502, 'invalid_provider_output');
  const draft = parsed.data;
  const observations = draft.observations.map(o => {
    const fact = input.facts.find(f => f.id === o.evidenceID);
    if (!fact || o.kind !== kindFor(fact)) throw new APIError(502, 'invalid_provider_facts');
    return { text: observationText(fact), evidenceIDs: [fact.id] };
  });
  const recommendations = draft.actionIDs.map(actionID => {
    const candidate = input.candidates.find(c => c.actionID === actionID);
    if (!candidate) throw new APIError(502, 'invalid_provider_action');
    return { text: actionText[candidate.action], actionID };
  });
  if (new Set(draft.actionIDs).size !== draft.actionIDs.length ||
      new Set(draft.observations.map(o => o.evidenceID)).size !== draft.observations.length) {
    throw new APIError(502, 'invalid_provider_duplicates');
  }
  return { reportID: randomUUID(), inputFingerprint: input.inputFingerprint, model: policy.model,
    promptVersion: policy.prompt, schemaVersion: 1, summary: summaryFor(input), observations,
    recommendations, generatedAt: now, validUntil: Math.min(now + policy.reportTTL, input.asOf + 24 * 3600_000),
    isLocalFallback: false };
}
