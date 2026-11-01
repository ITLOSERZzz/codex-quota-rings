import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';

export function stateDirectory() {
  // User-profile storage is shared by packaged Codex and the un-packaged task.
  // AppData can present different virtualized views of the same absolute path.
  return process.env.CODEX_QUOTA_STATE_DIR || path.join(os.homedir(), '.codex-quota-rings');
}
export function pipeName(directory = stateDirectory()) {
  const hash = crypto.createHash('sha256').update(path.resolve(directory).toLowerCase()).digest('hex').slice(0, 24);
  return process.platform === 'win32' ? `\\\\.\\pipe\\codex-quota-rings-${hash}` : path.join(directory, 'control.sock');
}
export async function atomicJson(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const temporary = `${file}.${process.pid}.tmp`;
  try { await fs.writeFile(temporary, JSON.stringify(value, null, 2), { mode: 0o600 }); await fs.rename(temporary, file); }
  finally { await fs.unlink(temporary).catch(() => {}); }
}
export async function controlRequest(command, directory = stateDirectory()) {
  if (!['status', 'stop'].includes(command)) throw new Error('INVALID_CONTROL_COMMAND');
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(pipeName(directory));
    let buffer = '';
    socket.setTimeout(2000);
    socket.on('connect', () => socket.write(`${JSON.stringify({ command })}\n`));
    socket.on('data', data => {
      buffer += data.toString();
      if (buffer.length > 1048576) { socket.destroy(); reject(new Error('CONTROL_RESPONSE_TOO_LARGE')); return; }
      if (buffer.includes('\n')) {
        try { const result = JSON.parse(buffer.split('\n')[0]); socket.end(); resolve(result); }
        catch { socket.destroy(); reject(new Error('INVALID_CONTROL_RESPONSE')); }
      }
    });
    socket.on('timeout', () => { socket.destroy(); reject(new Error('CONTROL_TIMEOUT')); });
    socket.on('error', () => reject(new Error('HELPER_NOT_RUNNING')));
    socket.on('end', () => { if (!buffer.includes('\n')) reject(new Error('HELPER_NOT_RUNNING')); });
  });
}
