import { expect, test } from 'bun:test';
import { Scope } from '../scripts/proxy';
import { assertOwned, locateWindow, manage } from '../scripts/manage';

test('each proxy exposes one native target, never the global active tab', () => {
  for (const own of ['a', 'b']) {
    const scope = new Scope(own, 6);
    expect(scope.request({ id: 1, method: 'Target.getTargets' })).toBe('forward');
    expect(scope.response({ id: 1, result: { targetInfos: [{ targetId: 'a' }, { targetId: 'b' }] } }).result.targetInfos).toEqual([{ targetId: own }]);
    expect(scope.request({ id: 2, method: 'Target.attachToTarget', params: { targetId: own === 'a' ? 'b' : 'a' } })).toBe('deny');
    expect(scope.response({ method: 'Target.targetCreated', params: { targetInfo: { targetId: 'unrelated' } } })).toBeNull();
  }
});
test('browser closing, tab creation, focus stealing and unknown sessions are blocked', () => {
  const scope = new Scope('a', 6);
  for (const method of ['Browser.close', 'Browser.setWindowBounds', 'Target.createTarget', 'Target.closeTarget', 'Target.createBrowserContext']) expect(scope.request({ id: 1, method })).toBe('deny');
  expect(scope.request({ id: 2, method: 'Runtime.evaluate', sessionId: 'foreign' })).toBe('deny');
  expect(scope.request({ id: 3, method: 'Target.activateTarget', params: { targetId: 'a' } })).toBe('ignore');
});
test('owned sessions and their out-of-process iframes still work', () => {
  const scope = new Scope('a', 6);
  scope.request({ id: 1, method: 'Target.attachToTarget', params: { targetId: 'a' } });
  scope.response({ id: 1, result: { sessionId: 'own' } });
  const event = { method: 'Target.attachedToTarget', sessionId: 'own', params: { sessionId: 'frame', targetInfo: { targetId: 'f', type: 'iframe' } } };
  expect(scope.response(event)).toEqual(event);
  expect(scope.request({ id: 2, method: 'Runtime.evaluate', sessionId: 'frame' })).toBe('forward');
  expect(scope.request({ id: 3, method: 'Page.bringToFront', sessionId: 'own' })).toBe('ignore');
});
test('closed target never causes another target to be adopted', () => {
  const scope = new Scope('closed', 6);
  scope.request({ id: 1, method: 'Target.getTargets' });
  expect(scope.response({ id: 1, result: { targetInfos: [{ targetId: 'other' }] } }).result.targetInfos).toEqual([]);
  expect(scope.request({ id: 2, method: 'Target.createTarget' })).toBe('deny');
});
test('moved window, moved group and restarted browser fail closed', async () => {
  const state = { windowId: 6, groupId: 10, instance: 'old', address: 'window' };
  expect(() => assertOwned({ windowId: 8, groupId: 10 }, state)).toThrow();
  expect(() => assertOwned({ windowId: 6, groupId: 11 }, state)).toThrow();
  await expect(manage({ state, window: { address: 'window' } }, {} as any, 'new')).rejects.toThrow('Browser/window changed');
});
test('ambiguous window titles do not select the newest tab', async () => {
  const cdp = { call: async (method: string, params: any) => method === 'Target.getTargets' ? { targetInfos: [{ targetId: 'a', title: '1. Same', type: 'page' }, { targetId: 'b', title: 'Same', type: 'page' }] } : { windowId: params.targetId === 'a' ? 6 : 8 } };
  await expect(locateWindow(cdp as any, 'Same - Helium')).rejects.toThrow('uniquely');
});
