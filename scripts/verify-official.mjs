import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { normalizeQuota } from '../src/quota.mjs';

// Optional read-only diagnostic. The mounted rings use the DESKTOP's own client,
// not this separate CLI diagnostic, so different CLI accounts cannot affect them.
const executable = process.argv[2];
if (!executable) throw new Error('Pass the installed official codex.exe path.');
const child = spawn(executable, ['app-server', '--stdio'], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
const pending = new Map(); let next = 0;
child.stderr.resume();
const lines = createInterface({ input: child.stdout });
lines.on('line', text => {
  let message; try { message = JSON.parse(text); } catch { return; }
  const request = pending.get(message.id); if (!request) return;
  clearTimeout(request.timer); pending.delete(message.id);
  if (message.error) request.reject(new Error('OFFICIAL_READ_FAILED')); else request.resolve(message.result);
});
function request(method, params) {
  return new Promise((resolve, reject) => {
    const id = ++next;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('OFFICIAL_READ_TIMEOUT')); }, 20000);
    pending.set(id, { resolve, reject, timer });
    child.stdin.write(JSON.stringify({ id, method, params }) + '\n');
  });
}
try {
  await request('initialize', { clientInfo: { name: 'quota-rings-readonly-check', version: '0.1.5' }, capabilities: { experimentalApi: true } });
  child.stdin.write('{"method":"initialized"}\n');
  const account = await request('account/read', { refreshToken: false });
  const limits = await request('account/rateLimits/read', {});
  const parsed = normalizeQuota(limits);
  console.log(JSON.stringify({ officialProtocol: true, authenticated: account.account?.type === 'chatgpt',
    validResponse: parsed.status === 'ok', fiveHourProvided: parsed.five !== null, weeklyProvided: parsed.week !== null,
    resetCardCountProvided: parsed.resetCards !== null }));
} catch {
  console.error('Official read-only verification did not complete. No credentials or raw responses were logged.');
  process.exitCode = 1;
} finally {
  for (const item of pending.values()) clearTimeout(item.timer);
  lines.close(); child.stdin.end(); child.kill();
}
