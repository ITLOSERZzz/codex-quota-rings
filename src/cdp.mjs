export function loopbackUrl(value, port, protocol = 'http:') {
  const url = new URL(value);
  if (url.protocol !== protocol || !['127.0.0.1', '[::1]', 'localhost'].includes(url.hostname)
    || Number(url.port) !== port || url.username || url.password) throw new Error('UNTRUSTED_DEBUG_ENDPOINT');
  return url;
}

export async function listTargets(port) {
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('INVALID_DEBUG_PORT');
  const response = await fetch(`http://127.0.0.1:${port}/json/list`, {
    signal: AbortSignal.timeout(3000), redirect: 'error',
  });
  if (!response.ok || Number(response.headers.get('content-length') || 0) > 1048576) throw new Error('DEBUG_ENDPOINT_UNAVAILABLE');
  const text = await response.text();
  if (text.length > 1048576) throw new Error('DEBUG_RESPONSE_TOO_LARGE');
  const list = JSON.parse(text);
  if (!Array.isArray(list)) throw new Error('INVALID_DEBUG_RESPONSE');
  return list.filter(target => target.type === 'page' && typeof target.id === 'string'
    && typeof target.webSocketDebuggerUrl === 'string').map(target => {
    loopbackUrl(target.webSocketDebuggerUrl, port, 'ws:');
    return target;
  });
}

export class CdpSession {
  #socket; #next = 0; #pending = new Map();
  constructor(socket) {
    this.#socket = socket;
    socket.addEventListener('message', event => {
      let message;
      try { message = JSON.parse(String(event.data)); } catch { return; }
      const pending = this.#pending.get(message.id);
      if (!pending) return;
      this.#pending.delete(message.id); clearTimeout(pending.timer);
      if (message.error) pending.reject(new Error('CDP_REQUEST_FAILED'));
      else pending.resolve(message.result);
    });
    socket.addEventListener('close', () => this.#rejectAll());
    socket.addEventListener('error', () => this.#rejectAll());
  }
  static async connect(url, port) {
    loopbackUrl(url, port, 'ws:');
    const socket = new WebSocket(url);
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { socket.close(); reject(new Error('DEBUG_CONNECT_TIMEOUT')); }, 4000);
      socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
      socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('DEBUG_CONNECT_FAILED')); }, { once: true });
    });
    return new CdpSession(socket);
  }
  #rejectAll() {
    for (const pending of this.#pending.values()) { clearTimeout(pending.timer); pending.reject(new Error('DEBUG_DISCONNECTED')); }
    this.#pending.clear();
  }
  request(method, params = {}, timeoutMs = 12000) {
    if (this.#socket.readyState !== WebSocket.OPEN) return Promise.reject(new Error('DEBUG_DISCONNECTED'));
    return new Promise((resolve, reject) => {
      const id = ++this.#next;
      const timer = setTimeout(() => { this.#pending.delete(id); reject(new Error('CDP_TIMEOUT')); }, timeoutMs);
      this.#pending.set(id, { resolve, reject, timer });
      try { this.#socket.send(JSON.stringify({ id, method, params })); }
      catch { clearTimeout(timer); this.#pending.delete(id); reject(new Error('DEBUG_DISCONNECTED')); }
    });
  }
  async evaluate(expression, timeoutMs = 12000) {
    const result = await this.request('Runtime.evaluate', {
      expression, awaitPromise: true, returnByValue: true, userGesture: false,
    }, timeoutMs);
    if (result.exceptionDetails) throw new Error('RENDERER_ADAPTER_UNAVAILABLE');
    return result.result?.value;
  }
  close() { this.#socket.close(); this.#rejectAll(); }
}
