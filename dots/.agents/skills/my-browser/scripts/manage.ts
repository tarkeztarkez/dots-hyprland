import { CDP } from './cdp';
import { createHash } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const extensionIdForPath = (path: string) => createHash('sha256').update(path).digest('hex').slice(0, 32).replace(/[0-9a-f]/g, value => String.fromCharCode(97 + parseInt(value, 16)));
export const OWN_EXTENSION_ID = extensionIdForPath(realpathSync(fileURLToPath(new URL('../extension', import.meta.url))));

export const normalizeTitle = (title: string) => title.replace(/ - Helium$/, '').replace(/^\d+\. /, '');
export function assertOwned(tab: any, state: any) {
  if (tab.windowId !== state.windowId || tab.groupId !== state.groupId) throw new Error('Owned tab left its Super+E window or group. No action taken.');
}

export async function bridge(cdp: CDP, extensionId?: string, wakeTarget?: string) {
  // Never execute management code in an unrelated installed extension.
  extensionId = OWN_EXTENSION_ID;
  let targets = (await cdp.call('Target.getTargets')).targetInfos;
  wakeTarget ??= targets.find((t: any) => t.type === 'page')?.targetId;
  if (extensionId && !targets.some((t: any) => t.url.startsWith(`chrome-extension://${extensionId}/`)) && wakeTarget) {
    const { sessionId } = await cdp.call('Target.attachToTarget', { targetId: wakeTarget, flatten: true });
    try {
      await cdp.call('ServiceWorker.enable', {}, sessionId);
      await cdp.call('ServiceWorker.startWorker', { scopeURL: `chrome-extension://${extensionId}/` }, sessionId);
      for (let attempt = 0; attempt < 40; attempt++) {
        targets = (await cdp.call('Target.getTargets')).targetInfos;
        if (targets.some((t: any) => t.url.startsWith(`chrome-extension://${extensionId}/`) && t.type === 'service_worker')) break;
        await Bun.sleep(50);
      }
    } finally { await cdp.call('Target.detachFromTarget', { sessionId }); }
  }
  for (const target of targets.filter((t: any) => t.url.startsWith('chrome-extension://') && ['background_page', 'service_worker'].includes(t.type))) {
    const id = new URL(target.url).hostname;
    if (extensionId && id !== extensionId) continue;
    try {
      const ready = await cdp.evaluate(target.targetId, '!!chrome.tabs?.group && !!chrome.tabGroups?.update');
      if (ready) return { targetId: target.targetId, extensionId: id };
    } catch { /* A worker may stop while discovering contexts. */ }
  }
  throw new Error('My Browser extension is unavailable. No other extension or window will be used.');
}

export async function locateWindow(cdp: CDP, title: string) {
  const targets = (await cdp.call('Target.getTargets')).targetInfos.filter((t: any) => t.type === 'page' && normalizeTitle(t.title) === normalizeTitle(title));
  const windows = new Set<number>();
  for (const target of targets) windows.add((await cdp.call('Browser.getWindowForTarget', { targetId: target.targetId })).windowId);
  if (windows.size !== 1) throw new Error('Cannot uniquely identify the tagged Super+E native window. Give its active tab a unique title and retry.');
  return [...windows][0];
}

export async function manage(input: any, cdp: CDP, instance: string) {
  const state = input.state;
  if (state && (state.instance !== instance || state.address !== input.window.address || state.closed)) throw new Error('Browser/window changed or session finished. Start a new session.');
  const extension = await bridge(cdp, state?.extensionId, state?.selected);
  const evaluate = (expression: string) => cdp.evaluate(extension.targetId, expression);
  const pairing = await evaluate('myBrowser.resolve()');
  if (pairing.address !== input.window.address || pairing.instance !== instance || (state && state.windowId !== pairing.windowId)) throw new Error('Super+E pairing changed. No action taken');
  const windowId = pairing.windowId;
  const result = state ? structuredClone(state) : { session: input.session, instance, address: input.window.address, windowId, extensionId: extension.extensionId, tabs: [], proxies: {} };
  const check = async (owned: any) => {
    const native = await evaluate(`chrome.tabs.get(${JSON.stringify(owned.nativeId)})`);
    assertOwned(native, result);
    const actual = await cdp.call('Browser.getWindowForTarget', { targetId: owned.targetId });
    if (actual.windowId !== windowId) throw new Error('Native target does not belong to Super+E');
    return { ...owned, title: native.title, url: native.url };
  };
  if (input.action === 'start' || input.action === 'new-tab') {
    if (state) for (const tab of state.tabs) await check(tab);
    const marker = `about:blank#my-browser-${crypto.randomUUID()}`;
    const created = await evaluate(`(async () => {
      const tab = await chrome.tabs.create(${JSON.stringify({ windowId, active: false, url: marker })});
      try {
        const groupId = await chrome.tabs.group({tabIds:[tab.id], ${state ? `groupId:${state.groupId}` : `createProperties:{windowId:${windowId}}`}});
        await chrome.tabGroups.update(groupId, ${JSON.stringify({ title: `AI ${result.session}`, color: ['blue','red','yellow','green','pink','purple','cyan','orange'][result.session.charCodeAt(result.session.length - 1) % 8], collapsed: false })});
        return {nativeId:tab.id,groupId};
      } catch (error) { await chrome.tabs.remove(tab.id); throw error; }
    })()`);
    for (let attempt = 0; attempt < 40; attempt++) {
      const targets = (await cdp.call('Target.getTargets')).targetInfos.filter((t: any) => t.type === 'page' && t.url === marker);
      if (targets.length === 1) {
        result.groupId = created.groupId;
        const tab = { nativeId: created.nativeId, targetId: targets[0].targetId };
        result.tabs.push(tab); result.selected = tab.targetId;
        await check(tab);
        return result;
      }
      await Bun.sleep(50);
    }
    await evaluate(`chrome.tabs.remove(${created.nativeId})`);
    throw new Error('Created tab did not appear in CDP');
  }
  if (input.action === 'finish') {
    const existing = (await evaluate(`chrome.tabs.query({windowId:${windowId}})`)).map((t: any) => t.id);
    // Check moved tabs too. Missing tabs can be ignored, moved tabs cannot.
    const all = await evaluate('chrome.tabs.query({})');
    const live = state.tabs.filter((tab: any) => all.some((native: any) => native.id === tab.nativeId));
    for (const tab of live) await check(tab);
    if (live.length) await evaluate(`chrome.tabs.remove(${JSON.stringify(live.filter((tab: any) => existing.includes(tab.nativeId)).map((tab: any) => tab.nativeId))})`);
    return { ...result, closed: true };
  }
  if (input.action === 'select') {
    const tab = state.tabs.find((tab: any) => tab.targetId === input.targetId);
    if (!tab) throw new Error('Tab is not owned by this session');
    await check(tab); result.selected = tab.targetId; return result;
  }
  if (input.action === 'close-tab') {
    const tab = state.tabs.find((tab: any) => tab.targetId === (input.targetId ?? state.selected));
    if (!tab) throw new Error('Tab is not owned by this session');
    await check(tab); await evaluate(`chrome.tabs.remove(${tab.nativeId})`);
    result.tabs = result.tabs.filter((owned: any) => owned.targetId !== tab.targetId);
    if (result.selected === tab.targetId) result.selected = null;
    return result;
  }
  const tab = state.tabs.find((tab: any) => tab.targetId === state.selected);
  if (!tab) throw new Error('No selected owned tab');
  await check(tab);
  if (input.action === 'activate') {
    await evaluate(`chrome.tabs.update(${tab.nativeId}, {active:true})`);
    return result;
  }
  if (input.action === 'tabs') return Promise.all(state.tabs.map(check));
  if (input.action !== 'check') throw new Error('Unknown management action');
  return result;
}

if (import.meta.main) {
  const input = await Bun.stdin.json();
  const { cdp, instance } = await CDP.connect();
  try { console.log(JSON.stringify(await manage(input, cdp, instance))); }
  catch (error) { console.error(error instanceof Error ? error.message : 'Browser management failed'); process.exitCode = 1; }
  finally { cdp.close(); }
}
