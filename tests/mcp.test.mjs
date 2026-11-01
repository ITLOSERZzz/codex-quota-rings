import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('plugin initializes, lists read-only tools, and works without a running helper', async () => {
  const server = spawn(process.execPath, [fileURLToPath(new URL('../src/mcp-server.mjs', import.meta.url))], {
    windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, CODEX_QUOTA_STATE_DIR: process.cwd() + '/test-results/no-helper' },
  });
  const replies = new Map(); let buffer = '', stderr = '';
  server.stdout.setEncoding('utf8'); server.stderr.setEncoding('utf8'); server.stderr.on('data', text => stderr += text);
  server.stdout.on('data', chunk => { buffer += chunk; for (;;) { const index = buffer.indexOf('\n'); if (index < 0) break;
    const message = JSON.parse(buffer.slice(0, index)); buffer = buffer.slice(index + 1); replies.get(message.id)?.(message); } });
  function request(id, method, params) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('MCP timeout')), 5000);
      replies.set(id, message => { clearTimeout(timer); resolve(message); });
      server.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
    });
  }
  try {
    const init = await request(1, 'initialize', { protocolVersion: '2025-06-18' });
    assert.equal(init.result.serverInfo.name, 'codex-quota-rings');
    const tools = (await request(2, 'tools/list')).result.tools;
    assert.equal(tools.length, 2); assert(tools.every(tool => tool.annotations.readOnlyHint));
    const status = (await request(3, 'tools/call', { name: 'quota_status', arguments: {} })).result;
    assert.equal(status.structuredContent.running, false);
    assert.equal((await request(4, 'tools/call', { name: 'turn/start', arguments: {} })).error.code, -32602);
    assert.equal(stderr, '');
  } finally { server.stdin.end(); server.kill(); }
});
