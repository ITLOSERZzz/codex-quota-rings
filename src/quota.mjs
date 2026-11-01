// These functions are also embedded unchanged in the desktop renderer.
export function normalizeQuota(response, observedAt = Date.now()) {
  const invalid = { status: 'unavailable', observedAt, five: null, week: null, resetCards: null };
  if (!response || typeof response !== 'object') return invalid;
  const byId = response.rateLimitsByLimitId;
  const legacy = response.rateLimits;
  // A model-specific bucket is never a substitute for the general Codex bucket.
  const bucket = byId && Object.hasOwn(byId, 'codex') ? byId.codex
    : legacy && (!legacy.limitId || legacy.limitId === 'codex') ? legacy : null;
  const result = { ...invalid, status: 'ok' };
  if (bucket && typeof bucket === 'object') {
    for (const window of [bucket.primary, bucket.secondary]) {
      if (!window || typeof window.usedPercent !== 'number' || !Number.isFinite(window.usedPercent)) continue;
      const key = window.windowDurationMins === 300 ? 'five' : window.windowDurationMins === 10080 ? 'week' : null;
      if (!key) continue;
      const resetsAt = typeof window.resetsAt === 'number' && Number.isFinite(window.resetsAt) && window.resetsAt > 0
        ? window.resetsAt * 1000 : null;
      result[key] = {
        remaining: Math.max(0, Math.min(100, 100 - window.usedPercent)),
        resetsAt,
        expired: resetsAt !== null && resetsAt <= observedAt,
      };
    }
  }
  const count = response.rateLimitResetCredits?.availableCount;
  // The API's count is authoritative. The returned detail array can be capped.
  if (Number.isSafeInteger(count) && count >= 0) result.resetCards = count;
  if (!result.five && !result.week && result.resetCards === null) result.status = 'unavailable';
  return result;
}

export function quotaColor(percent, dark = true) {
  if (typeof percent !== 'number' || !Number.isFinite(percent)) return dark ? '#858585' : '#737373';
  const p = Math.max(0, Math.min(100, percent));
  const stops = [[0, 0], [10, 5], [30, 30], [50, 57], [100, 142]];
  const index = stops.findIndex(([value]) => value >= p);
  const [a, hueA] = stops[Math.max(0, index - 1)];
  const [b, hueB] = stops[Math.max(0, index)];
  const hue = hueA + (hueB - hueA) * (a === b ? 0 : (p - a) / (b - a));
  return `hsl(${hue.toFixed(2)} 68% ${dark ? 63 : 38}%)`;
}

export function quotaIsFresh(snapshot, now = Date.now(), maxAgeMs = 45000) {
  return snapshot?.status === 'ok' && typeof snapshot.observedAt === 'number'
    && snapshot.observedAt <= now + 5000 && now - snapshot.observedAt <= maxAgeMs;
}
