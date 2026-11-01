import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeQuota, quotaColor, quotaIsFresh } from '../src/quota.mjs';

const now = 1800000000000;
const window = (duration, used = 25, reset = now / 1000 + 3600) => ({ windowDurationMins: duration, usedPercent: used, resetsAt: reset });
test('uses duration, including primary-only weekly responses and reversed windows', () => {
  const value = normalizeQuota({ rateLimits: { primary: window(10080), secondary: window(300, 72) } }, now);
  assert.equal(value.five.remaining, 28); assert.equal(value.week.remaining, 75);
  const weeklyOnly = normalizeQuota({ rateLimits: { primary: window(10080) } }, now);
  assert.equal(weeklyOnly.five, null); assert.equal(weeklyOnly.week.remaining, 75);
});
test('model-specific and general buckets are never combined', () => {
  const value = normalizeQuota({ rateLimits: { limitId: 'model', primary: window(300, 99) },
    rateLimitsByLimitId: { codex: { primary: window(10080, 10) }, model: { primary: window(300, 99) } } }, now);
  assert.equal(value.five, null); assert.equal(value.week.remaining, 90);
  assert.equal(normalizeQuota({ rateLimits: { limitId: 'model', primary: window(300) } }, now).five, null);
});
test('null, strings, booleans and missing percentages stay unknown', () => {
  for (const used of [null, undefined, '0', false, true, NaN, Infinity]) {
    assert.equal(normalizeQuota({ rateLimits: { primary: { ...window(300), usedPercent: used } } }, now).five, null);
  }
  assert.equal(normalizeQuota(null, now).status, 'unavailable');
});
test('quota is remaining capacity and clamps overage', () => {
  assert.equal(normalizeQuota({ rateLimits: { primary: window(300, 120) } }, now).five.remaining, 0);
  assert.equal(normalizeQuota({ rateLimits: { primary: window(300, -4) } }, now).five.remaining, 100);
});
test('reset card count is authoritative, with zero distinct from unavailable', () => {
  for (const count of [0, 2, 12]) assert.equal(normalizeQuota({ rateLimitResetCredits: { availableCount: count, credits: [] } }, now).resetCards, count);
  for (const count of [null, '2', -1, 1.5, undefined]) assert.equal(normalizeQuota({ rateLimitResetCredits: { availableCount: count, credits: [{}, {}] } }, now).resetCards, null);
});
test('missing reset time never becomes the Unix epoch, expired windows stay marked expired', () => {
  assert.equal(normalizeQuota({ rateLimits: { primary: window(300, 1, null) } }, now).five.resetsAt, null);
  assert.equal(normalizeQuota({ rateLimits: { primary: window(300, 1, now / 1000 - 1) } }, now).five.expired, true);
});
test('green at full, red at low, continuous independently derived hues', () => {
  assert.equal(quotaColor(100), 'hsl(142.00 68% 63%)');
  assert.equal(quotaColor(5), 'hsl(2.50 68% 63%)');
  assert.equal(quotaColor(0), 'hsl(0.00 68% 63%)');
  const hues = Array.from({ length: 101 }, (_, p) => Number(quotaColor(p).match(/hsl\(([0-9.]+)/)[1]));
  assert(hues.every((value, i) => !i || value >= hues[i - 1]));
  assert(hues.every((value, i) => !i || value - hues[i - 1] < 2));
  assert.notEqual(quotaColor(72), quotaColor(38));
  assert.equal(quotaColor(null), '#858585');
});
test('stale, failed and impossible future snapshots are not current', () => {
  const fresh = { status: 'ok', observedAt: now };
  assert(quotaIsFresh(fresh, now + 44000));
  assert(!quotaIsFresh(fresh, now + 45001));
  assert(!quotaIsFresh({ ...fresh, status: 'error' }, now));
  assert(!quotaIsFresh({ ...fresh, observedAt: now + 6000 }, now));
});
