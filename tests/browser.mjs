import fs from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import { CdpSession } from '../src/cdp.mjs';
import { rendererSource } from '../src/renderer.mjs';
import { runDaemon } from '../src/daemon.mjs';
import { controlRequest } from '../src/runtime.mjs';

const browserPath = process.env.CHROME_PATH || [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium',
].find(existsSync);
if (!browserPath) throw new Error('Set CHROME_PATH to run the real browser integration test.');
const results = path.resolve('test-results'); await fs.mkdir(results, { recursive: true });
const profile = await fs.mkdtemp(path.join(os.tmpdir(), 'quota-rings-test-'));
const fixture = `<!doctype html><html class="dark" style="color-scheme:dark"><meta charset="utf-8"><title>Quota Rings test · synthetic data</title><style>
body{background:#101010;color:#ededed;font:14px "Segoe UI",sans-serif}nav{position:fixed;left:0;top:0;bottom:0;width:60px;border-right:1px solid #303030}#avatar{position:fixed;bottom:16px;left:16px;width:32px;height:32px;border:0;border-radius:50%;background:#b93629;color:white}main{padding:70px 0 0 92px}p{color:#888}button{cursor:pointer}
</style><nav><button id="avatar" aria-label="打开个人资料菜单">LO</button></nav><main><h2>Codex 额度 · 双环</h2><p>浏览器集成测试，数据为合成示例。</p></main><script>
window.fixtureAccount='account-a';window.fixtureCalls=[];window.fixtureFail=false;
window.fixtureSnapshot={rateLimitsByLimitId:{codex:{primary:{usedPercent:28,windowDurationMins:300,resetsAt:Date.now()/1000+3600},secondary:{usedPercent:62,windowDurationMins:10080,resetsAt:Date.now()/1000+200000}}},rateLimitResetCredits:{availableCount:2,credits:[]}};
window.fixtureClient={hostId:'local',requestPromises:new Map(),async sendRequest(method){window.fixtureCalls.push(method);if(window.fixtureFail)throw new Error('fixture-offline');if(method==='account/read')return{account:{type:'chatgpt',email:window.fixtureAccount+'@example.invalid'}};if(method==='account/rateLimits/read'){if(window.fixtureSwitchOnRates){window.fixtureAccount='account-b';window.fixtureSwitchOnRates=false;}return window.fixtureSnapshot;}throw new Error('unexpected-method');}};
window.__codexRoot={_internalRoot:{current:{client:window.fixtureClient}}};
</script></html>`;
const httpServer = http.createServer((request, response) => { response.writeHead(200, { 'content-type': 'text/html;charset=utf-8' }); response.end(fixture); });
await new Promise(resolve => httpServer.listen(0, '127.0.0.1', resolve));
const proc = spawn(browserPath, ['--headless=new', '--no-first-run', '--disable-gpu', '--force-dark-mode', '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=0', '--user-data-dir=' + profile, 'about:blank'], { windowsHide: true, stdio: 'ignore' });
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let session;
try {
  let port;
  for (let i = 0; i < 100; i++) { try { port = Number((await fs.readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]); if (port) break; } catch {} await sleep(100); }
  assert(port, 'Browser did not start');
  const targets = await fetch(`http://127.0.0.1:${port}/json/list`).then(response => response.json());
  session = await CdpSession.connect(targets.find(target => target.type === 'page').webSocketDebuggerUrl, port);
  await session.request('Emulation.setDeviceMetricsOverride', { width: 820, height: 720, deviceScaleFactor: 1, mobile: false });
  await session.request('Page.navigate', { url: `http://127.0.0.1:${httpServer.address().port}` });
  for (let i = 0; i < 50; i++) { if (await session.evaluate('Boolean(window.fixtureClient)')) break; await sleep(100); }
  await session.evaluate(rendererSource({ pollMs: 60000 })); await sleep(100);
  async function run(expression) { return session.evaluate(expression); }
  async function snapshot() { return run('window.__CODEX_QUOTA_RINGS_V1__.report()'); }
  const initial = await snapshot();
  assert(initial.mounted); assert.equal(initial.snapshot.five.remaining, 72); assert.equal(initial.snapshot.week.remaining, 38);
  await session.evaluate(rendererSource({ pollMs: 60000 }));
  assert.equal(await run('document.querySelectorAll("#codex-quota-rings").length'), 1);
  await run(`document.querySelector('#codex-quota-rings').shadowRoot.querySelector('.ring').dispatchEvent(new PointerEvent('pointerenter',{pointerType:'mouse'}))`);
  assert.equal(await run(`document.querySelector('#codex-quota-rings').shadowRoot.querySelector('.panel').hidden`), false);
  assert.equal(await run(`document.querySelector('#codex-quota-rings').shadowRoot.querySelector('.cards strong').textContent`), '2 张');
  await run('window.fixtureSnapshot.rateLimitResetCredits.availableCount=0;window.__CODEX_QUOTA_RINGS_V1__.refresh(true)');
  assert.equal((await snapshot()).snapshot.resetCards, 0);
  await run('window.fixtureSnapshot.rateLimitResetCredits.availableCount=null;window.__CODEX_QUOTA_RINGS_V1__.refresh(true)');
  assert.equal(await run(`document.querySelector('#codex-quota-rings').shadowRoot.querySelector('.cards strong').textContent`), '暂不可用');
  await run('window.fixtureSwitchOnRates=true;window.__CODEX_QUOTA_RINGS_V1__.refresh(true)');
  assert.equal((await snapshot()).snapshot, null);
  assert.equal((await snapshot()).reason, 'account-changed');
  await run('window.__CODEX_QUOTA_RINGS_V1__.refresh(true)'); assert((await snapshot()).snapshot);
  await run('window.fixtureFail=true;window.__CODEX_QUOTA_RINGS_V1__.refresh(true)');
  assert.equal((await snapshot()).snapshot, null);
  assert.equal(await run(`document.querySelector('#codex-quota-rings').shadowRoot.querySelector('[data-window="five"] strong').textContent`), '—');
  await run('window.fixtureFail=false;window.__codexRoot._internalRoot.current={};window.__CODEX_QUOTA_RINGS_V1__.refresh(true)');
  assert.equal((await snapshot()).reason, 'adapter-unavailable');
  await run('window.__codexRoot._internalRoot.current={client:window.fixtureClient};window.__CODEX_QUOTA_RINGS_V1__.refresh(true)');
  assert((await snapshot()).snapshot, 'Must recover after a missing renderer adapter');
  await run(`(()=>{
    window.fixtureBridgeMessages=[];window.fixtureUnrelatedResponses=0;
    window.addEventListener('message',event=>{if(event.data?.type==='mcp-response')window.fixtureUnrelatedResponses++});
    window.electronBridge={async sendMessageFromView(message){
      window.fixtureBridgeMessages.push(message);
      if(message.type!=='mcp-request'||message.hostId!=='local')throw Error('Unexpected bridge transport');
      const result=await window.fixtureClient.sendRequest(message.request.method,message.request.params);
      window.dispatchEvent(new MessageEvent('message',{data:{type:'mcp-response',hostId:'local',message:{id:message.request.id,result}}}));
    }};
    window.__codexRoot._internalRoot.current={};
  })()`);
  await run('window.__CODEX_QUOTA_RINGS_V1__.refresh(true)');
  assert((await snapshot()).snapshot, 'Native desktop bridge must work without a React client reference');
  assert.equal(await run('window.fixtureUnrelatedResponses'), 0, 'Own responses must not reach unrelated client promise maps');
  await run(`window.dispatchEvent(new MessageEvent('message',{data:{type:'mcp-response',hostId:'local',message:{id:'unrelated-request',result:{}}}}))`);
  assert.equal(await run('window.fixtureUnrelatedResponses'), 1, 'Other application responses must not be intercepted');
  await run('window.fixtureFail=true;window.__CODEX_QUOTA_RINGS_V1__.refresh(true)');
  assert.equal((await snapshot()).snapshot,null,'Bridge failures must clear quota');
  await run('window.fixtureFail=false;window.__CODEX_QUOTA_RINGS_V1__.refresh(true)');
  assert((await snapshot()).snapshot, 'Bridge must recover');
  await run('delete window.__codexRoot;window.__CODEX_QUOTA_RINGS_V1__.dispose()');
  await session.evaluate(rendererSource({ pollMs: 60000 })); await sleep(100);
  assert((await snapshot()).mounted && (await snapshot()).snapshot, 'Bridge mount must not depend on the private React root name');
  await run(`document.querySelector('#codex-quota-rings').shadowRoot.querySelector('.ring').dispatchEvent(new PointerEvent('pointerenter',{pointerType:'mouse'}))`);
  await run(`window.fixtureSnapshot.rateLimitsByLimitId.codex={primary:{usedPercent:20,windowDurationMins:10080,resetsAt:Date.now()/1000+1000}};window.__CODEX_QUOTA_RINGS_V1__.refresh(true)`);
  assert.equal((await snapshot()).snapshot.five, null);
  await run(`window.fixtureSnapshot.rateLimitsByLimitId.codex.primary.resetsAt=Date.now()/1000-1;window.__CODEX_QUOTA_RINGS_V1__.refresh(true)`);
  assert.equal(await run(`document.querySelector('#codex-quota-rings').shadowRoot.querySelector('[data-window="week"] strong').textContent`), '—');
  await run(`window.fixtureSnapshot.rateLimitsByLimitId.codex={primary:{usedPercent:0,windowDurationMins:300,resetsAt:Date.now()/1000+3600},secondary:{usedPercent:95,windowDurationMins:10080,resetsAt:Date.now()/1000+200000}};window.fixtureSnapshot.rateLimitResetCredits.availableCount=2;window.__CODEX_QUOTA_RINGS_V1__.refresh(true)`);
  await sleep(300);
  const colors = await run(`(()=>{const s=document.querySelector('#codex-quota-rings').shadowRoot;return {five:getComputedStyle(s.querySelector('.five-arc')).stroke,week:getComputedStyle(s.querySelector('.week-arc')).stroke}})()`);
  assert.notEqual(colors.five, colors.week);
  const png = await session.request('Page.captureScreenshot', { format: 'png' });
  await fs.writeFile(path.join(results, 'browser-desktop.png'), Buffer.from(png.data, 'base64'));
  await session.request('Emulation.setDeviceMetricsOverride', { width: 390, height: 700, deviceScaleFactor: 1, mobile: false }); await sleep(100);
  const bounds = await run(`(()=>{const p=document.querySelector('#codex-quota-rings').shadowRoot.querySelector('.panel').getBoundingClientRect();return {left:p.left,right:p.right,bottom:p.bottom,width:innerWidth,height:innerHeight}})()`);
  assert(bounds.left >= 0 && bounds.right <= bounds.width && bounds.bottom <= bounds.height && bounds.right > bounds.left);
  await run(`document.documentElement.className='light'`); await sleep(100);
  assert.equal(await run(`document.querySelector('#codex-quota-rings').dataset.theme`), 'light');
  await run(`(()=>{const rail=document.querySelector('nav');rail.setAttribute('data-app-navigation-rail','');rail.style.cssText+=';display:flex;flex-direction:column;justify-content:flex-end';const footer=document.createElement('div');footer.id='profile-footer';const avatar=document.querySelector('#avatar');avatar.style.position='static';footer.append(avatar);rail.append(footer);})()`);
  await sleep(200);
  assert.equal((await snapshot()).placement, 'navigation-rail');
  assert.equal(await run(`document.querySelector('#codex-quota-rings').nextElementSibling.id`), 'profile-footer');
  assert.equal(await run(`document.querySelector('#avatar').parentElement.id`), 'profile-footer', 'React-owned profile must stay in its original footer');
  await run(`document.querySelector('#codex-quota-rings').remove()`); await sleep(200);
  assert((await snapshot()).mounted, 'Recover if a sidebar update removes the owned sibling');
  assert.equal(await run(`document.querySelectorAll('#codex-quota-rings').length`), 1);
  await run(`window.__CODEX_QUOTA_RINGS_V1__.dispose()`);
  assert.equal(await run(`document.querySelector('#codex-quota-rings')`), null);
  assert((await run('window.fixtureCalls')).every(method => ['account/read', 'account/rateLimits/read'].includes(method)));
  const helperDirectory = path.join(results, 'helper-' + Date.now());
  await runDaemon({ port, directory: helperDirectory });
  await sleep(150);
  assert((await controlRequest('status', helperDirectory)).running);
  assert.equal(await run(`Boolean(document.querySelector('#codex-quota-rings'))`), true);
  await controlRequest('stop', helperDirectory);
  await sleep(200);
  assert.equal(await run(`document.querySelector('#codex-quota-rings')`), null);
  console.log(JSON.stringify({ passed: true, initialQuota: { five: 72, week: 38, resetCards: 2 }, hover: true, accountSwitch: true, offline: true, adapterRecovery: true, missingWindow: true, expiredWindow: true, zeroAndUnknownCards: true, independentColors: colors, narrowLayout: bounds, cleanup: true, helperMountStatusAndStop: true }));
  await session.request('Browser.close').catch(() => {});
} finally {
  session?.close(); proc.kill(); httpServer.close();
  // The profile belongs only to this test; cleanup is intentionally left to the OS temp policy.
}
