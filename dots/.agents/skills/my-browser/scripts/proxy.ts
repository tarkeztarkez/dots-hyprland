// One CDP connection per owned tab. Other browser targets never reach the CLI.
export class Scope {
  sessions = new Set<string>();
  targets: Set<string>;
  pending = new Map<number, any>();
  constructor(public targetId: string, public windowId: number) { this.targets = new Set([targetId]); }
  request(message: any): 'forward' | 'ignore' | 'deny' {
    if (message.sessionId && !this.sessions.has(message.sessionId)) return 'deny';
    const p = message.params ?? {}, m = message.method;
    if (p.targetId && !this.targets.has(p.targetId)) return 'deny';
    if (p.windowId !== undefined && p.windowId !== this.windowId) return 'deny';
    if (['Page.bringToFront', 'Target.activateTarget'].includes(m)) return 'ignore';
    if (m.startsWith('Browser.') && !['Browser.getVersion', 'Browser.getWindowForTarget', 'Browser.getWindowBounds'].includes(m)) return 'deny';
    if (m.startsWith('Target.') && !['Target.getTargets', 'Target.getTargetInfo', 'Target.setDiscoverTargets', 'Target.attachToTarget', 'Target.detachFromTarget', 'Target.setAutoAttach', 'Target.setAutoAttachRelated'].includes(m)) return 'deny';
    if (m.startsWith('Target.setAutoAttach') && !message.sessionId) return 'deny';
    if (m === 'Target.detachFromTarget' && !this.sessions.has(p.sessionId)) return 'deny';
    if (!message.sessionId && !m.startsWith('Target.') && !m.startsWith('Browser.')) return 'deny';
    this.pending.set(message.id, message); return 'forward';
  }
  response(message: any): any | null {
    if (message.id !== undefined) {
      const request = this.pending.get(message.id); this.pending.delete(message.id);
      if (!request) return null;
      if (request.method === 'Target.getTargets' && message.result) message.result.targetInfos = message.result.targetInfos.filter((t: any) => t.targetId === this.targetId);
      if (request.method === 'Target.attachToTarget' && message.result?.sessionId) this.sessions.add(message.result.sessionId);
      return message;
    }
    if (message.sessionId && !this.sessions.has(message.sessionId)) return null;
    if (message.method === 'Target.attachedToTarget') {
      const info = message.params.targetInfo;
      if (message.sessionId && this.sessions.has(message.sessionId) && info.type !== 'page') {
        this.sessions.add(message.params.sessionId); this.targets.add(info.targetId);
      } else if (info.targetId !== this.targetId) return null;
    }
    const targetId = message.params?.targetInfo?.targetId ?? message.params?.targetId;
    if (targetId && !this.targets.has(targetId)) return null;
    if (!message.sessionId && !message.method.startsWith('Target.')) return null;
    return message;
  }
}

if (import.meta.main) {
  const config = await Bun.file(process.argv[2]).json();
  const targetId = process.argv[3];
  if (!config.tabs.some((tab: any) => tab.targetId === targetId)) throw new Error('Not an owned tab');
  const token = crypto.randomUUID();
  const connections = new Set<WebSocket>();
  const server = Bun.serve<any>({
    hostname: '127.0.0.1', port: 0,
    async fetch(request, server) {
      if (request.headers.has('origin') || new URL(request.url).pathname !== `/${token}`) return new Response('Forbidden', { status: 403 });
      if (request.method === 'DELETE') { setTimeout(() => { for (const socket of connections) socket.close(); server.stop(true); process.exit(0); }, 25); return new Response('Stopped'); }
      const state = await Bun.file(process.argv[2]).json();
      if (state.closed) return new Response('Session finished', { status: 410 });
      if (server.upgrade(request, { data: {} })) return;
      return new Response('WebSocket required', { status: 400 });
    },
    websocket: {
      open(client) {
        const upstream = new WebSocket(config.instance);
        connections.add(upstream);
        client.data = { upstream, scope: new Scope(targetId, config.windowId), queue: [] };
        upstream.addEventListener('open', () => { for (const message of client.data.queue) upstream.send(message); client.data.queue = []; });
        upstream.addEventListener('message', event => {
          const message = client.data.scope.response(JSON.parse(String(event.data)));
          if (message) client.send(JSON.stringify(message));
        });
        upstream.addEventListener('close', () => client.close());
        upstream.addEventListener('error', () => client.close());
      },
      message(client, bytes) {
        try {
          const message = JSON.parse(String(bytes)), action = client.data.scope.request(message);
          if (action !== 'forward') {
            client.send(JSON.stringify({ id: message.id, ...(message.sessionId ? { sessionId: message.sessionId } : {}), ...(action === 'ignore' ? { result: {} } : { error: { code: -32000, message: 'my-browser: command outside owned tab scope' } }) }));
          } else if (client.data.upstream.readyState === WebSocket.OPEN) client.data.upstream.send(String(bytes));
          else client.data.queue.push(String(bytes));
        } catch { client.close(); }
      },
      close(client) { client.data.upstream?.close(); connections.delete(client.data.upstream); },
    },
  });
  console.log(JSON.stringify({ endpoint: `ws://127.0.0.1:${server.port}/${token}` }));
}
