"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const ws_1 = require("ws");
const match_manager_1 = require("./match-manager");
const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
const MAX_CONNECTIONS = 100;
const RATE_LIMIT_MAX = 30; // messages per second
const HEARTBEAT_INTERVAL = 30_000; // 30 s
const manager = new match_manager_1.MatchManager();
const wss = new ws_1.WebSocketServer({ port: PORT });
wss.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
        console.error(`[Erro] Porta ${PORT} já está em uso. Use PORT=<outra> para escolher outra porta.`);
        process.exit(1);
    }
    else {
        console.error(`[Erro] WebSocketServer: ${err.message}`);
    }
});
// ─── Heartbeat ────────────────────────────────────────────────────────────────
const heartbeatTimer = setInterval(() => {
    for (const [id, player] of manager.players) {
        if (!player.isAlive) {
            console.log(`[Heartbeat] Sem resposta de ${id} — encerrando conexão`);
            player.ws.terminate();
            continue;
        }
        player.isAlive = false;
        try {
            player.ws.ping();
        }
        catch {
            // ignore
        }
    }
}, HEARTBEAT_INTERVAL);
wss.on('close', () => clearInterval(heartbeatTimer));
// ─── Connection handler ───────────────────────────────────────────────────────
wss.on('connection', (ws) => {
    // Enforce max connections
    if (manager.players.size >= MAX_CONNECTIONS) {
        ws.close(1013, 'Servidor cheio');
        return;
    }
    const id = crypto.randomUUID();
    const player = manager.addPlayer(id, ws);
    console.log(`[Conexão] Nova: ${id} (total: ${manager.players.size})`);
    // Send assigned immediately
    manager.send(id, { type: 'assigned', playerId: id });
    // Send current lobby list
    manager.sendLobbyList(id);
    // ─── Pong (native WebSocket pong) ──────────────────────────────────────────
    ws.on('pong', () => {
        const p = manager.players.get(id);
        if (p)
            p.isAlive = true;
    });
    // ─── Message handler ────────────────────────────────────────────────────────
    ws.on('message', (raw) => {
        const p = manager.players.get(id);
        if (!p)
            return;
        // ── Rate limiting ─────────────────────────────────────────────────────────
        const now = Date.now();
        if (now > p.rateLimit.resetAt) {
            p.rateLimit.count = 0;
            p.rateLimit.resetAt = now + 1000;
        }
        p.rateLimit.count++;
        if (p.rateLimit.count > RATE_LIMIT_MAX) {
            manager.send(id, { type: 'error', message: 'Rate limit excedido. Conexão encerrada.' });
            ws.close(1008, 'Rate limit exceeded');
            return;
        }
        // ── Parse JSON ────────────────────────────────────────────────────────────
        let msg;
        try {
            msg = JSON.parse(raw.toString());
        }
        catch {
            manager.send(id, { type: 'error', message: 'JSON inválido.' });
            return;
        }
        // ── Basic type validation ──────────────────────────────────────────────────
        if (typeof msg !== 'object' || msg === null || typeof msg['type'] !== 'string') {
            manager.send(id, { type: 'error', message: 'Mensagem inválida: campo "type" obrigatório.' });
            return;
        }
        // ── Validate known message types ──────────────────────────────────────────
        const validTypes = new Set([
            'quick_join', 'create_lobby', 'join_lobby', 'spectate', 'leave_spectate',
            'checkpoint_passed', 'lap_completed', 'race_finished', 'ping',
        ]);
        const clientMsg = msg;
        if (!validTypes.has(clientMsg['type'])) {
            manager.send(id, { type: 'error', message: `Tipo de mensagem desconhecido: ${clientMsg['type']}` });
            return;
        }
        manager.handleMessage(id, clientMsg);
    });
    // ─── Close handler ──────────────────────────────────────────────────────────
    ws.on('close', () => {
        console.log(`[Desconexão] ${id} (restantes: ${manager.players.size - 1})`);
        manager.removePlayer(id);
    });
    // ─── Error handler ──────────────────────────────────────────────────────────
    ws.on('error', (err) => {
        console.error(`[Erro WS] ${id}: ${err.message}`);
    });
});
console.log(`[Servidor] Horse Race WebSocket rodando na porta ${PORT}`);
//# sourceMappingURL=server.js.map