import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { controlRequest } from './runtime.mjs';
import { quotaIsFresh } from './quota.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const tools = [
  { name: 'quota_status', title: '查看双环额度状态',
    description: 'Read the desktop helper status, official 5-hour/weekly quota and available reset-card count. Does not start tasks, modify credentials, or estimate quota from tokens.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false } },
  { name: 'quota_installation', title: '查看安装方式',
    description: 'Show local installation instructions for the optional native sidebar mount. This tool only returns instructions; it does not install or restart anything.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false } },
];
const reply = (id, result) => process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, result })}\n`);
const fail = (id, code, message) => process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, error: { code, message } })}\n`);
async function handle(message) {
  if (!message || message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
    fail(message?.id ?? null, -32600, 'Invalid request'); return;
  }
  if (message.id === undefined) return;
  if (message.method === 'initialize') {
    const supported = ['2024-11-05', '2025-03-26', '2025-06-18'];
    reply(message.id, { protocolVersion: supported.includes(message.params?.protocolVersion) ? message.params.protocolVersion : '2025-06-18',
      capabilities: { tools: {} }, serverInfo: { name: 'codex-quota-rings', version: '0.1.5' } });
  } else if (message.method === 'ping') reply(message.id, {});
  else if (message.method === 'tools/list') reply(message.id, { tools });
  else if (message.method === 'tools/call') {
    if (!tools.some(tool => tool.name === message.params?.name)) { fail(message.id, -32602, 'Unknown tool'); return; }
    if (message.params.arguments && Object.keys(message.params.arguments).length) { fail(message.id, -32602, 'This tool takes no arguments'); return; }
    let value;
    if (message.params.name === 'quota_installation') {
      value = { platform: 'Windows 10/11 x64', installScript: path.join(root, 'scripts', 'install.ps1'),
        instructions: 'Download the complete Windows release, extract it, and double-click Install.cmd. After saving work, quit Codex normally and use the Codex 额度 desktop shortcut. Standard MCP plugins cannot mount an always-visible sidebar ring by themselves. Do not force-quit an active Codex session.' };
    } else {
      try {
        value = await controlRequest('status');
        if (Date.now() - value.updatedAt > 15000) value = { running: false, windows: [], reason: 'helper-unresponsive' };
        else for (const window of value.windows || []) if (!quotaIsFresh(window.snapshot)) window.snapshot = null;
      } catch { value = { running: false, windows: [], reason: '请从 Codex 额度快捷方式启动桌面应用。' }; }
    }
    reply(message.id, { content: [{ type: 'text', text: JSON.stringify(value, null, 2) }], structuredContent: value });
  } else fail(message.id, -32601, 'Method not found');
}
let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  buffer += chunk;
  if (Buffer.byteLength(buffer) > 65536) { buffer = ''; fail(null, -32700, 'Request too large'); return; }
  for (;;) {
    const index = buffer.indexOf('\n'); if (index < 0) break;
    const line = buffer.slice(0, index); buffer = buffer.slice(index + 1);
    if (!line.trim()) continue;
    let message;
    try { message = JSON.parse(line); } catch { fail(null, -32700, 'Parse error'); continue; }
    handle(message).catch(() => fail(message.id, -32603, 'Local quota helper unavailable'));
  }
});
