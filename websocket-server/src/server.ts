import { WebSocketServer, WebSocket } from 'ws';
import { createServer, IncomingMessage, ServerResponse } from 'http';
import { readFileSync, existsSync, statSync } from 'fs';
import { join, extname } from 'path';
import { MatchManager } from './match-manager';
import { ClientMessage } from './types';

const PORT          = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
const MAX_CONN      = 100;
const RATE_LIMIT    = 30;
const HEARTBEAT_MS  = 30_000;
const CLIENT_DIR    = join(__dirname, '..', 'client');

const MIME: Record<string, string> = {
  '.html' : 'text/html; charset=utf-8',
  '.js'   : 'text/javascript',
  '.css'  : 'text/css',
  '.wasm' : 'application/wasm',
  '.pck'  : 'application/octet-stream',
  '.png'  : 'image/png',
  '.ico'  : 'image/x-icon',
  '.json' : 'application/json',
  '.svg'  : 'image/svg+xml',
};

// ─── HTTP: serve arquivos estáticos ──────────────────────────────────────────

function serveStatic(req: IncomingMessage, res: ServerResponse): void {
  let urlPath = (req.url ?? '/').split('?')[0];
  if (urlPath === '/' || urlPath === '') urlPath = '/index.html';

  // Segurança: impede path traversal
  const filePath = join(CLIENT_DIR, urlPath);
  if (!filePath.startsWith(CLIENT_DIR)) {
    res.writeHead(403); res.end('Forbidden'); return;
  }

  // Diretório → tenta index.html dentro dele
  let target = filePath;
  if (existsSync(target) && statSync(target).isDirectory()) {
    target = join(target, 'index.html');
  }

  if (!existsSync(target)) {
    res.writeHead(404); res.end('Not found'); return;
  }

  const contentType = MIME[extname(target)] ?? 'application/octet-stream';

  // Headers obrigatórios para o export web do Godot (SharedArrayBuffer / threads)
  res.setHeader('Cross-Origin-Opener-Policy',   'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy',  'require-corp');
  res.setHeader('Content-Type', contentType);
  res.setHeader('Cache-Control', 'no-cache');

  res.writeHead(200);
  res.end(readFileSync(target));
}

// ─── Servidor HTTP + WS na mesma porta ───────────────────────────────────────

const httpServer = createServer(serveStatic);
const wss        = new WebSocketServer({ server: httpServer });
const manager    = new MatchManager();

httpServer.on('error', (err: NodeJS.ErrnoException) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`[Erro] Porta ${PORT} em uso. Use PORT=<outra> npm run dev`);
    process.exit(1);
  }
  console.error(`[Erro] HTTP: ${err.message}`);
});

// ─── Heartbeat ────────────────────────────────────────────────────────────────

const heartbeatTimer = setInterval(() => {
  for (const [id, player] of manager.players) {
    if (!player.isAlive) {
      console.log(`[Heartbeat] Sem resposta de ${id} — encerrando`);
      player.ws.terminate();
      continue;
    }
    player.isAlive = false;
    try { player.ws.ping(); } catch { /* ignore */ }
  }
}, HEARTBEAT_MS);

wss.on('close', () => clearInterval(heartbeatTimer));

// ─── Conexões WebSocket ───────────────────────────────────────────────────────

wss.on('connection', (ws: WebSocket) => {
  if (manager.players.size >= MAX_CONN) {
    ws.close(1013, 'Servidor cheio'); return;
  }

  const id     = crypto.randomUUID();
  manager.addPlayer(id, ws);

  console.log(`[Conexão] ${id}  (total: ${manager.players.size})`);

  manager.send(id, { type: 'assigned', playerId: id });
  manager.sendLobbyList(id);

  ws.on('pong', () => {
    const p = manager.players.get(id);
    if (p) p.isAlive = true;
  });

  ws.on('message', (raw: Buffer | string) => {
    const p = manager.players.get(id);
    if (!p) return;

    // Rate limiting
    const now = Date.now();
    if (now > p.rateLimit.resetAt) { p.rateLimit.count = 0; p.rateLimit.resetAt = now + 1000; }
    if (++p.rateLimit.count > RATE_LIMIT) {
      manager.send(id, { type: 'error', message: 'Rate limit excedido.' });
      ws.close(1008, 'Rate limit exceeded'); return;
    }

    // Parse
    let msg: unknown;
    try { msg = JSON.parse(raw.toString()); }
    catch { manager.send(id, { type: 'error', message: 'JSON inválido.' }); return; }

    if (typeof msg !== 'object' || msg === null ||
        typeof (msg as Record<string, unknown>)['type'] !== 'string') {
      manager.send(id, { type: 'error', message: 'Campo "type" obrigatório.' }); return;
    }

    const validTypes = new Set([
      'quick_join','create_lobby','join_lobby','spectate','leave_spectate',
      'checkpoint_passed','lap_completed','race_finished','ping',
    ]);
    const m = msg as Record<string, unknown>;
    if (!validTypes.has(m['type'] as string)) {
      manager.send(id, { type: 'error', message: `Tipo desconhecido: ${m['type']}` }); return;
    }

    manager.handleMessage(id, m as unknown as ClientMessage);
  });

  ws.on('close', () => {
    console.log(`[Desconexão] ${id}  (restantes: ${manager.players.size - 1})`);
    manager.removePlayer(id);
  });

  ws.on('error', (err: Error) => console.error(`[Erro WS] ${id}: ${err.message}`));
});

// ─── Start ────────────────────────────────────────────────────────────────────

httpServer.listen(PORT, () => {
  console.log(`\n[Servidor] Rodando em http://localhost:${PORT}`);
  console.log(`  → Cliente HTML : http://localhost:${PORT}/`);
  console.log(`  → Jogo Godot   : http://localhost:${PORT}/game/\n`);
});
