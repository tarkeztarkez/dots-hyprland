// Explicitly gated live-test actions, confined to synthetic about:blank tabs.
import { CDP } from '../scripts/cdp';
import { bridge } from '../scripts/manage';

if (process.env.MY_BROWSER_LIVE_TEST !== '1') throw new Error('Live browser tests require explicit opt-in');
const { action, a, b } = await Bun.stdin.json();
for (const state of [a, b]) if (!state.session.startsWith('groups-live-')) throw new Error('Not a test session');
const { cdp, instance } = await CDP.connect();
try {
  if (a.instance !== instance || b.instance !== instance || a.windowId !== b.windowId) throw new Error('Test browser changed');
  const extension = await bridge(cdp, a.extensionId, a.tabs[0].targetId);
  const ids = [a.tabs[0].nativeId, b.tabs[0].nativeId];
  const result = await cdp.evaluate(extension.targetId, `(async () => {
    const tabs = await Promise.all(${JSON.stringify(ids)}.map(id => chrome.tabs.get(id)));
    if (tabs.some(tab => tab.windowId !== ${a.windowId} || !tab.url.startsWith('about:blank#my-browser-'))) throw new Error('Not a synthetic test tab');
    ${action === 'move' ? `await chrome.tabs.group({tabIds:[${ids[0]}],groupId:${b.groupId}});` : ''}
    ${action === 'restore' ? `await chrome.tabs.group({tabIds:[${ids[0]}],groupId:${a.groupId}});` : ''}
    ${action === 'close' ? `await chrome.tabs.remove(${ids[0]});` : ''}
    return Promise.all([${a.groupId},${b.groupId}].map(id => chrome.tabGroups.get(id).then(group => ({id:group.id,title:group.title,windowId:group.windowId})).catch(() => null)));
  })()`);
  console.log(JSON.stringify(result));
} finally { cdp.close(); }
