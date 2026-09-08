// Browser-management backend. It never evaluates code in a website.
export class CDP {
  socket: WebSocket;
  next = 0;
  pending = new Map<number, { resolve: (value: any) => void; reject: (error: Error) => void; timer: ReturnType<typeof setTimeout> }>();
  constructor(socket: WebSocket) {
    this.socket = socket;
    socket.addEventListener('message', (event) => {
      const value = JSON.parse(String(event.data));
      const pending = this.pending.get(value.id);
      if (!pending) return;
      clearTimeout(pending.timer); this.pending.delete(value.id);
      if (value.error) pending.reject(new Error(value.error.message)); else pending.resolve(value.result);
    });
  }
  static async connect() {
    const version = await fetch('http://127.0.0.1:9222/json/version', { signal: AbortSignal.timeout(3000) }).then(r => r.json());
    const socket = new WebSocket(version.webSocketDebuggerUrl);
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('CDP connection timed out')), 3000);
      socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
      socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('CDP connection failed')); }, { once: true });
    });
    return { cdp: new CDP(socket), instance: version.webSocketDebuggerUrl };
  }
  call(method: string, params: object = {}, sessionId?: string): Promise<any> {
    const id = ++this.next;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 10000);
      this.pending.set(id, { resolve, reject, timer });
      this.socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
  }
  async evaluate(targetId: string, expression: string) {
    const { sessionId } = await this.call('Target.attachToTarget', { targetId, flatten: true });
    try {
      const result = await this.call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, sessionId);
      if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? 'Browser management evaluation failed');
      return result.result.value;
    } finally { await this.call('Target.detachFromTarget', { sessionId }); }
  }
  close() { this.socket.close(); }
}

if (import.meta.main) {
  const { cdp } = await CDP.connect();
  try {
    const { targetInfos } = await cdp.call('Target.getTargets');
    const capable = [];
    for (const target of targetInfos.filter((t: any) => t.url.startsWith('chrome-extension://') && ['background_page', 'service_worker'].includes(t.type))) {
      try {
        const info = await cdp.evaluate(target.targetId, '({name:chrome.runtime.getManifest().name,groups:!!chrome.tabGroups?.update,tabs:!!chrome.tabs?.group})');
        if (info.groups && info.tabs) capable.push({ ...info, extensionId: new URL(target.url).hostname });
      } catch { /* A stopped worker is not a usable API context. */ }
    }
    console.log(JSON.stringify(capable));
  } finally { cdp.close(); }
}
