import test from 'node:test';
import assert from 'node:assert/strict';
import { loopbackUrl } from '../src/cdp.mjs';
import { rendererSource } from '../src/renderer.mjs';
import vm from 'node:vm';

test('debug endpoints stay on the chosen loopback port', () => {
  assert.equal(loopbackUrl('ws://127.0.0.1:9333/devtools/page/x', 9333, 'ws:').hostname, '127.0.0.1');
  for (const address of ['ws://example.com:9333/x', 'ws://127.0.0.1:9222/x', 'wss://127.0.0.1:9333/x', 'ws://user:pass@127.0.0.1:9333/x']) {
    assert.throws(() => loopbackUrl(address, 9333, 'ws:'));
  }
});
test('injected source parses without third-party runtime imports', () => {
  const source = rendererSource();
  new vm.Script(source);
  assert(!source.includes('https://'));
  assert(!source.includes('auth.json'));
  assert(!source.includes('thread/resume'));
  assert(!source.includes('turn/start'));
});
