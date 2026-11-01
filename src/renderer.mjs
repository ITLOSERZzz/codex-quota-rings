import { normalizeQuota, quotaColor, quotaIsFresh } from './quota.mjs';

// No dependencies, remote scripts, cookies, credentials, or transcript access.
export function mountQuotaRings(options, core) {
  const KEY = '__CODEX_QUOTA_RINGS_V1__';
  const previous = window[KEY];
  if (previous?.version === options.version) { previous.heartbeat(); return previous.report(); }
  previous?.dispose();
  if (typeof window.electronBridge?.sendMessageFromView !== 'function' && !window.__codexRoot?._internalRoot?.current) return { mounted: false, reason: 'unsupported-window' };
  const timers = new Set();
  const abort = new AbortController();
  const host = document.createElement('div');
  host.id = 'codex-quota-rings';
  host.style.cssText = 'position:fixed;z-index:2147483600;width:40px;height:40px;pointer-events:none;display:none;';
  const shadow = host.attachShadow({ mode: 'open' });
  shadow.innerHTML = `<style>
    :host{--bg:#1d1d1d;--fg:#ededed;--muted:#a0a0a0;--line:#333;--track:#383838;--hover:#292929;--warning:#e6b45b;font:13px/1.45 "Segoe UI","Microsoft YaHei",sans-serif;color:var(--fg);color-scheme:dark}
    :host([data-theme="light"]){--bg:#fff;--fg:#222;--muted:#636363;--line:#e3e3e3;--track:#e4e4e4;--hover:#ececec;--warning:#966000;color-scheme:light}
    *{box-sizing:border-box}button{font:inherit;color:inherit}button:focus-visible{outline:2px solid var(--muted);outline-offset:2px}[hidden]{display:none!important}
    .ring{pointer-events:auto;display:grid;place-items:center;width:40px;height:40px;border:0;background:transparent;border-radius:10px;padding:3px;cursor:pointer;-webkit-app-region:no-drag}
    .ring:hover,.action:hover{background:var(--hover)}.gauge{width:34px;height:34px;overflow:visible;transform:rotate(-90deg)}.track{fill:none;stroke:var(--track);stroke-width:2.6}.arc{fill:none;stroke-width:2.6;stroke-linecap:round;transition:stroke .2s linear,stroke-dasharray .2s linear}.dot{display:none;fill:var(--warning)}
    .panel{pointer-events:auto;position:fixed;width:276px;padding:16px 17px 10px;border:1px solid var(--line);border-radius:14px;background:var(--bg);box-shadow:0 10px 32px #0003;-webkit-app-region:no-drag}
    .head,.line,.bottom,.cards{display:flex;align-items:center;justify-content:space-between;gap:12px}.head{font-weight:500}.account{font-size:11px;color:var(--muted);margin:2px 0 18px}.limit{margin-bottom:18px}.line{margin-bottom:8px}.line small{font-size:11px;color:var(--muted);margin-left:6px}.line strong{font-weight:500;font-size:22px;font-variant-numeric:tabular-nums;line-height:1.15}.bar{height:4px;border-radius:3px;background:var(--track);overflow:hidden}.fill{height:100%;border-radius:3px;transition:width .2s linear,background-color .2s linear}.reset{color:var(--muted);font-size:11px;margin-top:7px}.cards{font-size:12px;margin:0 0 13px}.cards span{color:var(--muted)}.cards strong{font-weight:500;font-variant-numeric:tabular-nums}.bottom{gap:4px;border-top:1px solid var(--line);padding-top:7px}.sync{font-size:11px;color:var(--muted);margin-right:auto}.action{display:grid;place-items:center;background:transparent;border:0;border-radius:7px;padding:5px;width:28px;height:28px;color:var(--muted);cursor:pointer}.action svg{width:15px;height:15px;stroke:currentColor;fill:none;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}.warning{color:var(--warning)}
    :host([data-stale]) .track{stroke-dasharray:2 3}:host([data-stale]) .gauge{opacity:.65}:host([data-stale]) .arc{visibility:hidden}
    @media(prefers-reduced-motion:reduce){.arc,.fill{transition:none}}
  </style>
  <button class="ring" type="button" aria-label="Codex 额度，正在同步" aria-expanded="false" aria-controls="quota-panel">
    <svg class="gauge" viewBox="0 0 40 40" aria-hidden="true"><circle class="track" cx="20" cy="20" r="15"/><circle class="track" cx="20" cy="20" r="9"/><circle class="arc five-arc" cx="20" cy="20" r="15" pathLength="100" stroke-dasharray="0 100"/><circle class="arc week-arc" cx="20" cy="20" r="9" pathLength="100" stroke-dasharray="0 100"/><circle class="dot" cx="20" cy="20" r="2"/></svg>
  </button>
  <section class="panel" id="quota-panel" aria-label="Codex 剩余额度" hidden>
    <div class="head"><span>剩余额度</span><button class="action close" aria-label="收起额度" type="button"><svg viewBox="0 0 24 24"><path d="m6 6 12 12M6 18 18 6"/></svg></button></div>
    <div class="account">当前 Codex 账户</div>
    <div class="limit" data-window="five"><div class="line"><span>5 小时<small>外环</small></span><strong>—</strong></div><div class="bar" role="progressbar" aria-label="5小时剩余额度" aria-valuemin="0" aria-valuemax="100"><div class="fill"></div></div><div class="reset">正在同步</div></div>
    <div class="limit" data-window="week"><div class="line"><span>每周<small>内环</small></span><strong>—</strong></div><div class="bar" role="progressbar" aria-label="每周剩余额度" aria-valuemin="0" aria-valuemax="100"><div class="fill"></div></div><div class="reset">正在同步</div></div>
    <div class="cards"><span>剩余重置卡</span><strong>暂不可用</strong></div>
    <div class="bottom"><span class="sync" role="status" aria-live="polite">正在同步</span><button class="action refresh" type="button" aria-label="刷新额度"><svg viewBox="0 0 24 24"><path d="M20 7v5h-5M4 17v-5h5M6 6a8 8 0 0 1 13 3M18 18A8 8 0 0 1 5 15"/></svg></button></div>
  </section>`;
  document.body.append(host);
  const button = shadow.querySelector('.ring');
  const panel = shadow.querySelector('.panel');
  let anchor = null, client = null, snapshot = null, lastSuccess = null, lastAttempt = 0;
  let lastHeartbeat = Date.now(), reason = 'loading', inFlight = null, pinned = false, hoverTimer, disposed = false;
  let currentIdentity = null, pollGeneration = 0, dark = true;
  let bridgeClient = null;
  const bridgePending = new Map();
  const bridgePrefix = `quota-rings:${typeof crypto.randomUUID === 'function' ? crypto.randomUUID() : Date.now() + '-' + Math.random()}:`;
  const bridgeListener = event => {
    if (event.source !== null && event.source !== window) return;
    const data = event.data;
    if (data?.type !== 'mcp-response' || data.hostId !== 'local' || typeof data.message?.id !== 'string' || !data.message.id.startsWith(bridgePrefix)) return;
    // These are solely our namespaced responses. Do not feed them to the app's
    // unrelated request-client promise map, and never intercept other IDs.
    event.stopImmediatePropagation();
    const pending = bridgePending.get(data.message.id);
    if (!pending) return;
    bridgePending.delete(data.message.id); clearTimeout(pending.timeout); timers.delete(pending.timeout);
    if (data.message.error) pending.reject(new Error('bridge-request-failed'));
    else pending.resolve(data.message.result);
  };
  window.addEventListener('message', bridgeListener, { capture: true, signal: abort.signal });
  const listen = (target, name, fn) => target.addEventListener(name, fn, { signal: abort.signal });
  function findClient() {
    if (typeof window.electronBridge?.sendMessageFromView === 'function') {
      bridgeClient ||= { sendRequest(method, params) {
        if (!['account/read', 'account/rateLimits/read'].includes(method) || disposed) return Promise.reject(new Error('readonly'));
        const id = bridgePrefix + (typeof crypto.randomUUID === 'function' ? crypto.randomUUID() : Math.random());
        return new Promise((resolve, reject) => {
          const timeout = setTimeout(() => { bridgePending.delete(id); timers.delete(timeout); reject(new Error('bridge-timeout')); }, 7000);
          timers.add(timeout); bridgePending.set(id, { resolve, reject, timeout });
          Promise.resolve().then(() => window.electronBridge.sendMessageFromView({ type: 'mcp-request', hostId: 'local',
            request: { id, method, ...(params === undefined ? {} : { params }) }, priority: 'background', timeoutMs: 7000, expiresAtMs: Date.now() + 7000,
          })).catch(() => { const pending = bridgePending.get(id); if (!pending) return; bridgePending.delete(id); clearTimeout(timeout); timers.delete(timeout); reject(new Error('bridge-unavailable')); });
        });
      }};
      return bridgeClient;
    }
    const root = window.__codexRoot?._internalRoot?.current;
    if (!root) return null;
    const queue = [root], seen = new WeakSet();
    for (let i = 0; i < queue.length && i < 60000; i++) {
      const value = queue[i];
      if (!value || !['object', 'function'].includes(typeof value) || seen.has(value)) continue;
      seen.add(value);
      try {
        if (value.hostId === 'local' && typeof value.sendRequest === 'function' && value.requestPromises instanceof Map) return value;
        const descriptors = Object.getOwnPropertyDescriptors(value);
        for (const descriptor of Object.values(descriptors)) {
          const child = descriptor.value;
          if (child && ['object', 'function'].includes(typeof child)) queue.push(child);
        }
        if (value instanceof Map) for (const [key, child] of value) queue.push(key, child);
        if (value instanceof Set) for (const child of value) queue.push(child);
      } catch { /* A detached fiber is harmless; try another node. */ }
    }
    return null;
  }
  function findAnchor() {
    const candidates = [...document.querySelectorAll('button[aria-label], [role="button"][aria-label]')];
    return candidates.find(element => {
      if (!/^(Open profile menu|打开个人资料菜单|開啟個人資料選單|打开个人资料|Open settings|打开设置)$/i.test(element.getAttribute('aria-label') || '')) return false;
      const rect = element.getBoundingClientRect();
      return rect.width >= 20 && rect.width <= 350 && rect.height >= 20 && rect.height <= 100
        && rect.left >= 0 && rect.left < 370 && rect.top > innerHeight * 0.45;
    }) || null;
  }
  function updatePosition() {
    if (disposed) return;
    anchor = findAnchor();
    if (!anchor) { host.style.display = 'none'; panel.hidden = true; return; }
    const rect = anchor.getBoundingClientRect();
    const rail = anchor.closest('nav[data-app-navigation-rail]');
    const footer = rail && [...rail.children].find(child => child !== host && child.contains(anchor));
    let left, top;
    if (rail && footer && footer !== anchor) {
      // Own one sibling in the native rail layout. Never move a React-owned control.
      if (host.parentElement !== rail || host.nextElementSibling !== footer) rail.insertBefore(host, footer);
      Object.assign(host.style, { position: 'relative', display: 'block', left: '', top: '', margin: '4px auto', flex: '0 0 40px' });
      host.dataset.placement = 'navigation-rail';
      const placed = host.getBoundingClientRect(); left = placed.left; top = placed.top;
    } else {
      if (host.parentElement !== document.body) document.body.append(host);
      const center = rect.width < 100 ? rect.left + rect.width / 2 : rect.left + 20;
      left = Math.max(3, center - 20); top = Math.max(4, rect.top - 46);
      // Older layouts without a navigation rail use the measured gap above the profile.
      const collision = [...document.querySelectorAll('button,[role="button"]')].some(element => {
        if (element === anchor || element.contains(anchor) || element.closest('#codex-quota-rings')) return false;
        const r = element.getBoundingClientRect();
        return r.width > 0 && r.height > 0 && r.left < left + 36 && r.right > left + 4 && r.top < top + 36 && r.bottom > top + 4;
      });
      Object.assign(host.style, { position: 'fixed', display: collision ? 'none' : 'block', left: `${left}px`, top: `${top}px`, margin: '0', flex: '' });
      host.dataset.placement = collision ? 'blocked' : 'above-profile';
    }
    const rootStyle = getComputedStyle(document.documentElement);
    const rootClass = document.documentElement.className;
    const theme = document.documentElement.getAttribute('data-theme');
    const lightClass = /(^|\s)light(\s|$)/i.test(String(rootClass));
    const darkClass = /(^|\s)dark(\s|$)/i.test(String(rootClass));
    dark = theme === 'light' || lightClass ? false : theme === 'dark' || darkClass ? true
      : rootStyle.colorScheme === 'dark' || (rootStyle.colorScheme !== 'light' && matchMedia('(prefers-color-scheme: dark)').matches);
    host.dataset.theme = dark ? 'dark' : 'light';
    host.style.fontFamily = getComputedStyle(anchor).fontFamily;
    const width = Math.min(276, Math.max(220, innerWidth - 16));
    panel.style.width = `${width}px`;
    panel.style.left = `${Math.max(8, Math.min(innerWidth - width - 8, left + 46))}px`;
    const height = panel.getBoundingClientRect().height || 307;
    panel.style.top = `${Math.max(8, Math.min(innerHeight - height - 8, top + 40 - height))}px`;
  }
  function resetText(windowValue, fresh) {
    if (!fresh) return snapshot ? '等待重新同步' : '正在同步';
    if (!windowValue) return '当前账户未提供此额度窗口';
    if (windowValue.expired || (windowValue.resetsAt && windowValue.resetsAt <= Date.now())) return '重置中，等待官方同步';
    if (!windowValue.resetsAt) return '重置时间暂不可用';
    return `${new Intl.DateTimeFormat(undefined, { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }).format(windowValue.resetsAt)} 重置`;
  }
  function render() {
    const fresh = core.quotaIsFresh(snapshot, Date.now(), options.maxAgeMs) && Date.now() - lastHeartbeat < 20000;
    host.toggleAttribute('data-stale', !fresh);
    const labels = [];
    for (const key of ['five', 'week']) {
      const value = snapshot?.[key];
      const expired = value && value.resetsAt !== null && value.resetsAt <= Date.now();
      const usable = fresh && value && !expired;
      const percent = usable ? value.remaining : null;
      const text = percent === null ? '—' : `${Number(percent.toFixed(1))}%`;
      const row = shadow.querySelector(`[data-window="${key}"]`);
      row.querySelector('strong').textContent = text;
      row.querySelector('.fill').style.width = `${percent ?? 0}%`;
      row.querySelector('.fill').style.background = core.quotaColor(percent, dark);
      row.querySelector('.reset').textContent = resetText(value, fresh);
      const bar = row.querySelector('.bar');
      bar.removeAttribute('aria-valuenow');
      if (percent !== null) bar.setAttribute('aria-valuenow', String(percent));
      bar.setAttribute('aria-valuetext', percent === null ? '暂不可用' : text);
      const arc = shadow.querySelector(`.${key}-arc`);
      arc.style.stroke = core.quotaColor(percent, dark);
      arc.style.opacity = percent !== null && percent > 0 ? '1' : '0';
      arc.setAttribute('stroke-dasharray', `${percent ?? 0} 100`);
      labels.push(`${key === 'five' ? '5小时' : '每周'}剩余${text}`);
    }
    const zero = fresh && [snapshot?.five, snapshot?.week].some(value => value && value.remaining === 0 && !value.expired);
    const dot = shadow.querySelector('.dot'); dot.style.display = zero ? 'block' : 'none'; dot.style.fill = core.quotaColor(0, dark);
    shadow.querySelector('.cards strong').textContent = fresh && snapshot.resetCards !== null ? `${snapshot.resetCards} 张` : '暂不可用';
    const sync = shadow.querySelector('.sync'); sync.classList.toggle('warning', !fresh && reason !== 'loading');
    const descriptions = { 'loading': '正在同步', 'account-unavailable': '请登录 ChatGPT 账户', 'account-changed': '账户已切换，重新同步中', 'adapter-unavailable': '未找到额度读取接口', 'request-failed': '同步失败，稍后重试', 'unsupported-window': '未找到侧栏界面' };
    sync.textContent = fresh ? `已同步 · ${Math.max(0, Math.floor((Date.now() - snapshot.observedAt) / 1000))} 秒前`
      : `${descriptions[reason] || '数据已过期'}${lastSuccess ? ` · 上次 ${new Date(lastSuccess).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : ''}`;
    button.setAttribute('aria-label', fresh ? `Codex 额度，${labels.join('，')}` : `Codex 额度，${sync.textContent}`);
    shadow.querySelector('.account').textContent = '当前 Codex 账户';
  }
  function identity(accountResponse) {
    const account = accountResponse?.account;
    if (!account || !['chatgpt', 'chatgptAuthTokens'].includes(account.type)) return null;
    // Kept in renderer memory only, never returned to the daemon or written to disk.
    if (!account.email && !account.id && !account.accountId) return null;
    return JSON.stringify([account.type, account.id ?? null, account.accountId ?? null, account.email ?? null]);
  }
  async function request(method, params) {
    if (!['account/read', 'account/rateLimits/read'].includes(method)) throw new Error('readonly');
    let timeout;
    try {
      return await Promise.race([
        client.sendRequest(method, params, { priority: 'background', source: 'codex_quota_rings' }),
        new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('timeout')), 8000); timers.add(timeout); }),
      ]);
    } finally { clearTimeout(timeout); timers.delete(timeout); }
  }
  async function refresh(force = false) {
    if (disposed || inFlight || (!force && Date.now() - lastAttempt < 5000)) return inFlight;
    lastAttempt = Date.now(); const generation = ++pollGeneration;
    inFlight = Promise.resolve().then(async () => {
      try {
        client = findClient();
        if (!client) { reason = 'adapter-unavailable'; snapshot = null; return; }
        const before = identity(await request('account/read', { refreshToken: false }));
        if (!before) { currentIdentity = null; snapshot = null; reason = 'account-unavailable'; return; }
        if (currentIdentity !== before) { snapshot = null; reason = 'account-changed'; render(); }
        const limits = await request('account/rateLimits/read', undefined);
        const after = identity(await request('account/read', { refreshToken: false }));
        if (!after || before !== after) { snapshot = null; currentIdentity = after; reason = 'account-changed'; return; }
        if (disposed || generation !== pollGeneration) return;
        currentIdentity = after;
        snapshot = core.normalizeQuota(limits, Date.now());
        if (snapshot.status === 'ok') { lastSuccess = snapshot.observedAt; reason = 'ok'; }
        else reason = 'request-failed';
      } catch { snapshot = null; reason = 'request-failed'; }
      finally { inFlight = null; if (!disposed) render(); }
    });
    return inFlight;
  }
  function openPanel() { clearTimeout(hoverTimer); panel.hidden = false; button.setAttribute('aria-expanded', 'true'); updatePosition(); render(); refresh(); }
  function closePanel() { panel.hidden = true; button.setAttribute('aria-expanded', 'false'); }
  function scheduleClose() { if (!pinned) { clearTimeout(hoverTimer); hoverTimer = setTimeout(closePanel, 240); } }
  listen(button, 'pointerenter', event => { if (event.pointerType === 'mouse') openPanel(); });
  listen(button, 'pointerleave', event => { if (event.pointerType === 'mouse') scheduleClose(); });
  listen(panel, 'pointerenter', () => clearTimeout(hoverTimer));
  listen(panel, 'pointerleave', event => { if (event.pointerType === 'mouse') scheduleClose(); });
  listen(button, 'focus', openPanel);
  listen(button, 'click', () => { pinned = !pinned; if (pinned) openPanel(); else closePanel(); });
  listen(shadow.querySelector('.close'), 'click', () => { pinned = false; closePanel(); button.focus(); closePanel(); });
  listen(shadow.querySelector('.refresh'), 'click', () => refresh(true));
  listen(document, 'keydown', event => { if (event.key === 'Escape') { pinned = false; closePanel(); } });
  listen(document, 'pointerdown', event => { if (!event.composedPath().includes(host)) { pinned = false; closePanel(); } });
  listen(window, 'resize', updatePosition);
  listen(document, 'visibilitychange', () => { if (!document.hidden) { updatePosition(); refresh(true); } });
  const observer = new MutationObserver(updatePosition);
  observer.observe(document.documentElement, { subtree: true, childList: true });
  const themeObserver = new MutationObserver(() => { updatePosition(); render(); });
  themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'style', 'data-theme'] });
  const pollTimer = setInterval(() => refresh(), options.pollMs);
  const ageTimer = setInterval(() => { updatePosition(); render(); }, 2000);
  const api = {
    version: options.version,
    heartbeat() { lastHeartbeat = Date.now(); },
    refresh,
    report() {
      return { mounted: host.isConnected && host.style.display !== 'none', placement: host.dataset.placement || 'missing-profile',
        reason, snapshot: core.quotaIsFresh(snapshot, Date.now(), options.maxAgeMs) ? snapshot : null };
    },
    dispose() {
      disposed = true; pollGeneration++; abort.abort(); observer.disconnect(); themeObserver.disconnect();
      for (const pending of bridgePending.values()) pending.reject(new Error('disposed')); bridgePending.clear();
      clearInterval(pollTimer); clearInterval(ageTimer); clearTimeout(hoverTimer);
      for (const timer of timers) clearTimeout(timer); timers.clear();
      host.remove(); if (window[KEY] === api) delete window[KEY];
    },
  };
  window[KEY] = api;
  updatePosition(); render(); refresh(true);
  return api.report();
}

export function rendererSource(options = {}) {
  const safe = { version: '0.1.5', pollMs: 15000, maxAgeMs: 45000, ...options };
  return `(${mountQuotaRings.toString()})(${JSON.stringify(safe)}, {normalizeQuota:${normalizeQuota.toString()},quotaColor:${quotaColor.toString()},quotaIsFresh:${quotaIsFresh.toString()}})`;
}
