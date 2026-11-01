import { runDaemon } from './daemon.mjs';
import { controlRequest, stateDirectory } from './runtime.mjs';
import { quotaIsFresh } from './quota.mjs';

const [command, ...args] = process.argv.slice(2);
try {
  if (command === 'daemon') {
    const value = args.find(value => value.startsWith('--port='));
    if (!value) throw new Error('INVALID_DEBUG_PORT');
    await runDaemon({ port: Number(value.slice(7)) });
  } else if (command === 'status') {
    const result = await controlRequest('status');
    const now = Date.now();
    for (const window of result.windows || []) if (!quotaIsFresh(window.snapshot, now)) window.snapshot = null;
    console.log(JSON.stringify(result, null, 2));
  } else if (command === 'stop') {
    console.log(JSON.stringify(await controlRequest('stop')));
  } else {
    console.log('Codex Quota Rings\n  node src/cli.mjs status\n  node src/cli.mjs stop\n  node src/cli.mjs daemon --port=PORT\nState: ' + stateDirectory());
  }
} catch (error) {
  if (error.message === 'HELPER_NOT_RUNNING' && ['status', 'stop'].includes(command)) {
    console.log(JSON.stringify(command === 'stop' ? { stopped: true, running: false }
      : { version: '0.1.5', running: false, windows: [] }));
  } else {
  // Avoid logging upstream exception messages, which can include private request data.
  const known = new Set(['INVALID_DEBUG_PORT', 'INVALID_POLL_INTERVAL', 'HELPER_NOT_RUNNING', 'CONTROL_TIMEOUT']);
  console.error(known.has(error.message) ? error.message : 'QUOTA_HELPER_FAILED');
  process.exitCode = 1;
  }
}
