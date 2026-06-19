/**
 * NotiPlus - Cloudflare Worker
 *
 * Endpoints:
 *   GET  /ws       — WebSocket for Flutter apps
 *   GET  /ws-admin — WebSocket for Web UI (real-time device count)
 *   POST /send     — Send notification to all Flutter clients
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (['/ws', '/ws-admin', '/send'].some(p => url.pathname === p)) {
      const id = env.NOTIFICATION_HUB.idFromName('global');
      const hub = env.NOTIFICATION_HUB.get(id);
      const response = await hub.fetch(request);

      if (response.status !== 101) {
        const newHeaders = new Headers(response.headers);
        for (const [k, v] of Object.entries(corsHeaders)) {
          newHeaders.set(k, v);
        }
        return new Response(response.body, {
          status: response.status,
          headers: newHeaders,
        });
      }
      return response;
    }

    return new Response('NotiPlus API is running', { status: 200 });
  },
};

// ─── Durable Object ──────────────────────────────────────────────────────────

export class NotificationHub {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.sessions = new Set();       // Flutter app clients
    this.adminSessions = new Set();  // Web UI clients
  }

  _broadcastStatus() {
    const msg = JSON.stringify({ connected: this.sessions.size });
    for (const admin of this.adminSessions) {
      try { admin.send(msg); } catch { this.adminSessions.delete(admin); }
    }
  }

  async fetch(request) {
    const url = new URL(request.url);

    // Flutter app WebSocket
    if (url.pathname === '/ws') {
      if (request.headers.get('Upgrade') !== 'websocket') {
        return new Response('Expected WebSocket upgrade', { status: 426 });
      }

      const [client, server] = Object.values(new WebSocketPair());
      server.accept();
      this.sessions.add(server);
      this._broadcastStatus();

      server.addEventListener('close', () => {
        this.sessions.delete(server);
        this._broadcastStatus();
      });
      server.addEventListener('error', () => {
        this.sessions.delete(server);
        this._broadcastStatus();
      });

      return new Response(null, { status: 101, webSocket: client });
    }

    // Web UI WebSocket — receives real-time device count
    if (url.pathname === '/ws-admin') {
      if (request.headers.get('Upgrade') !== 'websocket') {
        return new Response('Expected WebSocket upgrade', { status: 426 });
      }

      const [client, server] = Object.values(new WebSocketPair());
      server.accept();
      this.adminSessions.add(server);

      // Send current count immediately on connect
      server.send(JSON.stringify({ connected: this.sessions.size }));

      server.addEventListener('close', () => this.adminSessions.delete(server));
      server.addEventListener('error', () => this.adminSessions.delete(server));

      return new Response(null, { status: 101, webSocket: client });
    }

    // POST /send — broadcast notification to all Flutter clients
    if (url.pathname === '/send' && request.method === 'POST') {
      let body;
      try {
        body = await request.json();
      } catch {
        return new Response(
          JSON.stringify({ error: 'Invalid JSON body' }),
          { status: 400, headers: { 'Content-Type': 'application/json' } },
        );
      }

      const { title, body: notifBody, imageUrl } = body;
      if (!title || !notifBody) {
        return new Response(
          JSON.stringify({ error: 'title and body are required' }),
          { status: 400, headers: { 'Content-Type': 'application/json' } },
        );
      }

      const payload = { title, body: notifBody };
      if (imageUrl) payload.imageUrl = imageUrl;
      const message = JSON.stringify(payload);

      let sent = 0;
      for (const session of this.sessions) {
        try { session.send(message); sent++; }
        catch { this.sessions.delete(session); }
      }

      return new Response(
        JSON.stringify({ success: true, sent, connected: this.sessions.size }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      );
    }

    return new Response('Not found', { status: 404 });
  }
}
