import fs from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
import { CdpSession, listTargets } from './cdp.mjs';
import { rendererSource } from './renderer.mjs';
import { pipeName, stateDirectory, atomicJson, controlRequest } from './runtime.mjs';

export async function runDaemon({ port, directory = stateDirectory(), pollMs = 15000 } = {}) {
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('INVALID_DEBUG_PORT');
  if (!Number.isInteger(pollMs) || pollMs < 10000 || pollMs > 60000) throw new Error('INVALID_POLL_INTERVAL');
  await fs.mkdir(directory, { recursive: true });
  try { return await controlRequest('status', directory); } catch { /* Claim the named pipe below. */ }
  const sessions = new Map();
  let stopping = false, connectedOnce = false, failures = 0, activeTick = false;
  let status = { version: '0.1.5', running: true, port, updatedAt: Date.now(), windows: [] };
  const source = rendererSource({ pollMs });
  let tickTimer;
  const server = net.createServer(socket => {
    let buffer = '';
    socket.setTimeout(2000, () => socket.destroy());
    socket.on('error', () => {});
    socket.on('data', bytes => {
      buffer += bytes.toString();
      if (buffer.length > 2048) { socket.destroy(); return; }
      if (!buffer.includes('\n')) return;
      let input; try { input = JSON.parse(buffer.split('\n')[0]); } catch { socket.destroy(); return; }
      if (input.command === 'status') socket.end(`${JSON.stringify(status)}\n`);
      else if (input.command === 'stop') { socket.end('{"stopped":true}\n'); stop(); }
      else socket.end('{"error":"unsupported-command"}\n');
    });
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(pipeName(directory), resolve); });
  server.on('error', () => stop());
  async function stop() {
    if (stopping) return;
    stopping = true; clearInterval(tickTimer);
    const cleanup = [...sessions.values()].map(async session => {
      await session.evaluate('window.__CODEX_QUOTA_RINGS_V1__?.dispose(); true', 1500).catch(() => {});
      session.close();
    });
    await Promise.allSettled(cleanup);
    sessions.clear();
    status = { ...status, running: false, windows: [], updatedAt: Date.now() };
    await atomicJson(path.join(directory, 'status.json'), status).catch(() => {});
    server.close();
  }
  async function tick() {
    if (stopping || activeTick) return;
    activeTick = true;
    try {
      const targets = await listTargets(port);
      connectedOnce = true; failures = 0;
      const liveIds = new Set(targets.map(target => target.id));
      for (const [id, session] of sessions) if (!liveIds.has(id)) { session.close(); sessions.delete(id); }
      const windows = [];
      for (const target of targets.slice(0, 32)) {
        if (stopping) break;
        let session = sessions.get(target.id);
        try {
          if (!session) {
            session = await CdpSession.connect(target.webSocketDebuggerUrl, port);
            const eligible = await session.evaluate('Boolean(typeof window.electronBridge?.sendMessageFromView === "function" || window.__codexRoot?._internalRoot?.current)');
            if (!eligible) { session.close(); continue; }
            sessions.set(target.id, session);
          }
          const report = await session.evaluate(source);
          // The report deliberately excludes the account identity, page URL and titles.
          if (report) windows.push({ mounted: report.mounted === true, placement: report.placement || null,
            reason: report.reason || null, snapshot: report.snapshot || null });
        } catch {
          session?.close(); sessions.delete(target.id);
          windows.push({ mounted: false, placement: null, reason: 'renderer-injection-failed', snapshot: null });
        }
      }
      status = { ...status, running: true, updatedAt: Date.now(), windows };
    } catch {
      failures++;
      status = { ...status, updatedAt: Date.now(), windows: [], error: 'desktop-disconnected' };
      if ((connectedOnce && failures >= 4) || failures >= 36) stop();
    } finally {
      activeTick = false;
      if (!stopping) {
        if (status.windows.length) delete status.error;
        await atomicJson(path.join(directory, 'status.json'), status).catch(() => {});
      }
    }
  }
  process.once('SIGINT', stop); process.once('SIGTERM', stop);
  tickTimer = setInterval(tick, 5000);
  await tick();
  return status;
}
