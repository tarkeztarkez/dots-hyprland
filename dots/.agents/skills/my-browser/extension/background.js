// No content scripts, host permissions, external messaging or website evaluation.
globalThis.myBrowser = {
  async resolve() {
    const windows = await chrome.windows.getAll({ populate: true, windowTypes: ['normal'] });
    const candidates = windows.map(window => ({
      id: window.id,
      title: window.tabs.find(tab => tab.active)?.title ?? '',
    }));
    const result = await chrome.runtime.sendNativeMessage('local.my_browser', { op: 'resolve', windows: candidates });
    if (!result.ok) throw new Error(result.error);
    return result.window;
  },
};
