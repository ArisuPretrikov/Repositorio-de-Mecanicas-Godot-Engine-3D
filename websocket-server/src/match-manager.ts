import { WebSocket } from 'ws';
import {
  Player,
  Match,
  ClientMessage,
  ServerMessage,
  PlayerResult,
  LobbyEntry,
  MatchState,
} from './types';

export class MatchManager {
  public players: Map<string, Player> = new Map();
  // indexed by both match id AND match code for fast lookups
  private matches: Map<string, Match> = new Map();
  public quickQueue: string[] = [];

  // ─── Public API ──────────────────────────────────────────────────────────────

  addPlayer(id: string, ws: WebSocket): Player {
    const player: Player = {
      id,
      ws,
      name: 'Jogador',
      state: 'idle',
      matchId: null,
      playerNumber: null,
      rateLimit: { count: 0, resetAt: Date.now() + 1000 },
      isAlive: true,
    };
    this.players.set(id, player);
    return player;
  }

  removePlayer(id: string): void {
    const player = this.players.get(id);
    if (!player) return;

    // Remove from quick queue
    const qIdx = this.quickQueue.indexOf(id);
    if (qIdx !== -1) this.quickQueue.splice(qIdx, 1);

    // Handle active match
    if (player.matchId) {
      const match = this.matches.get(player.matchId);
      if (match && match.state !== 'finished') {
        if (match.state === 'lobby') {
          // Host left before anyone joined — just delete the lobby
          this.matches.delete(match.id);
          this.matches.delete(match.code);
          this.broadcastLobbyList();
        } else if (match.state === 'racing') {
          // Opponent wins by W.O.
          const opponentId = this.getOpponentId(match, id);
          if (opponentId) {
            this.send(opponentId, { type: 'opponent_disconnected' });
          }
          this.endMatch(match.id, opponentId);
        }
      }
    }

    // Remove from spectating
    for (const match of this.getUniqueMatches()) {
      match.spectatorIds.delete(id);
    }

    this.players.delete(id);
  }

  handleMessage(playerId: string, msg: ClientMessage): void {
    const player = this.players.get(playerId);
    if (!player) return;

    switch (msg.type) {
      case 'quick_join':
        this.handleQuickJoin(player, msg.name);
        break;
      case 'create_lobby':
        this.handleCreateLobby(player, msg.name);
        break;
      case 'join_lobby':
        this.handleJoinLobby(player, msg.name, msg.code);
        break;
      case 'spectate':
        this.handleSpectate(player, msg.code);
        break;
      case 'leave_spectate':
        this.handleLeaveSpectate(player);
        break;
      case 'checkpoint_passed':
        this.handleCheckpointPassed(player, msg.checkpointIndex);
        break;
      case 'lap_completed':
        this.handleLapCompleted(player, msg.lap, msg.elapsedMs);
        break;
      case 'race_finished':
        this.handleRaceFinished(player, msg.totalMs);
        break;
      case 'ping':
        this.send(playerId, { type: 'pong' });
        break;
    }
  }

  getLobbies(): LobbyEntry[] {
    return this.getUniqueMatches()
      .filter((m) => m.state === 'lobby' && m.p2Id === null)
      .map((m) => ({
        code: m.code,
        hostName: m.hostName,
        createdAt: m.createdAt,
      }));
  }

  // ─── Message handlers ─────────────────────────────────────────────────────────

  private handleQuickJoin(player: Player, rawName: string): void {
    if (player.state !== 'idle' && player.state !== 'spectating') {
      this.send(player.id, { type: 'error', message: 'Você já está em uma partida ou na fila.' });
      return;
    }

    player.name = this.sanitizeName(rawName);
    player.state = 'queued';
    player.matchId = null;
    player.playerNumber = null;

    // Remove from spectating if needed
    this.removeFromAllSpectate(player.id);

    // Add to queue (avoid duplicates)
    if (!this.quickQueue.includes(player.id)) {
      this.quickQueue.push(player.id);
    }

    this.send(player.id, { type: 'queued', position: this.quickQueue.indexOf(player.id) + 1 });
    this.tryPairFromQueue();
  }

  private handleCreateLobby(player: Player, rawName: string): void {
    if (player.state !== 'idle' && player.state !== 'spectating') {
      this.send(player.id, { type: 'error', message: 'Você já está em uma partida ou na fila.' });
      return;
    }

    this.removeFromAllSpectate(player.id);

    player.name = this.sanitizeName(rawName);
    player.state = 'lobby_waiting';
    player.playerNumber = 1;

    const match = this.createMatch(player.id, null);
    player.matchId = match.id;

    this.send(player.id, { type: 'lobby_created', code: match.code });
    this.broadcastLobbyList();

    console.log(`[Lobby] Criado: ${match.code} por ${player.name} (${player.id})`);
  }

  private handleJoinLobby(player: Player, rawName: string, rawCode: string): void {
    if (player.state !== 'idle' && player.state !== 'spectating') {
      this.send(player.id, { type: 'error', message: 'Você já está em uma partida ou na fila.' });
      return;
    }

    const code = rawCode.trim().toUpperCase().slice(0, 5);
    const match = this.matches.get(code);

    if (!match) {
      this.send(player.id, { type: 'error', message: 'Lobby não encontrado.' });
      return;
    }
    if (match.state !== 'lobby') {
      this.send(player.id, { type: 'error', message: 'Este lobby já começou ou foi encerrado.' });
      return;
    }
    if (match.p2Id !== null) {
      this.send(player.id, { type: 'error', message: 'Este lobby já está cheio.' });
      return;
    }
    if (match.p1Id === player.id) {
      this.send(player.id, { type: 'error', message: 'Você não pode entrar no seu próprio lobby.' });
      return;
    }

    this.removeFromAllSpectate(player.id);

    player.name = this.sanitizeName(rawName);
    player.state = 'racing';
    player.matchId = match.id;
    player.playerNumber = 2;
    match.p2Id = player.id;

    this.startMatch(match.id);
    this.broadcastLobbyList();
  }

  private handleSpectate(player: Player, rawCode: string): void {
    const code = rawCode.trim().toUpperCase().slice(0, 5);
    const match = this.matches.get(code);

    if (!match) {
      this.send(player.id, { type: 'error', message: 'Partida não encontrada.' });
      return;
    }
    if (match.state === 'finished') {
      this.send(player.id, { type: 'error', message: 'Esta partida já foi encerrada.' });
      return;
    }
    if (match.p1Id === player.id || match.p2Id === player.id) {
      this.send(player.id, { type: 'error', message: 'Você é participante desta partida.' });
      return;
    }

    // Leave any previous spectating
    this.removeFromAllSpectate(player.id);

    player.state = 'spectating';
    match.spectatorIds.add(player.id);

    const p1 = this.players.get(match.p1Id);
    const p2 = match.p2Id ? this.players.get(match.p2Id) : null;

    this.send(player.id, {
      type: 'spectate_ok',
      code: match.code,
      p1Name: p1?.name ?? 'Jogador 1',
      p2Name: p2?.name ?? null,
      matchState: match.state,
    });
  }

  private handleLeaveSpectate(player: Player): void {
    this.removeFromAllSpectate(player.id);
    player.state = 'idle';
    player.matchId = null;
  }

  private handleCheckpointPassed(player: Player, checkpointIndex: number): void {
    if (player.state !== 'racing' || !player.matchId) {
      this.send(player.id, { type: 'error', message: 'Você não está em uma corrida.' });
      return;
    }

    if (typeof checkpointIndex !== 'number' || checkpointIndex < 0 || checkpointIndex > 100) {
      this.send(player.id, { type: 'error', message: 'Checkpoint inválido.' });
      return;
    }

    const match = this.matches.get(player.matchId);
    if (!match || match.state !== 'racing') return;

    const opponentId = this.getOpponentId(match, player.id);
    if (opponentId) {
      this.send(opponentId, { type: 'opponent_checkpoint', checkpointIndex });
    }

    this.notifySpectators(match.id, {
      type: 'spectate_event',
      kind: 'checkpoint',
      playerId: player.id,
      playerName: player.name,
      checkpointIndex,
    });
  }

  private handleLapCompleted(player: Player, lap: number, elapsedMs: number): void {
    if (player.state !== 'racing' || !player.matchId) {
      this.send(player.id, { type: 'error', message: 'Você não está em uma corrida.' });
      return;
    }

    if (
      typeof lap !== 'number' || lap < 1 || lap > 100 ||
      typeof elapsedMs !== 'number' || elapsedMs < 0 || elapsedMs > 3_600_000
    ) {
      this.send(player.id, { type: 'error', message: 'Dados de volta inválidos.' });
      return;
    }

    const match = this.matches.get(player.matchId);
    if (!match || match.state !== 'racing') return;

    const opponentId = this.getOpponentId(match, player.id);
    if (opponentId) {
      this.send(opponentId, { type: 'opponent_lap', lap, elapsedMs });
    }

    this.notifySpectators(match.id, {
      type: 'spectate_event',
      kind: 'lap',
      playerId: player.id,
      playerName: player.name,
      lap,
      elapsedMs,
    });
  }

  private handleRaceFinished(player: Player, totalMs: number): void {
    if (player.state !== 'racing' || !player.matchId) {
      this.send(player.id, { type: 'error', message: 'Você não está em uma corrida.' });
      return;
    }

    if (typeof totalMs !== 'number' || totalMs < 0 || totalMs > 3_600_000) {
      this.send(player.id, { type: 'error', message: 'Tempo inválido.' });
      return;
    }

    const match = this.matches.get(player.matchId);
    if (!match || match.state !== 'racing') return;

    // Record result for this player
    const result: PlayerResult = {
      playerId: player.id,
      name: player.name,
      finishTime: totalMs,
      finished: true,
    };

    if (player.playerNumber === 1) {
      match.results.p1 = result;
    } else {
      match.results.p2 = result;
    }

    // Notify opponent
    const opponentId = this.getOpponentId(match, player.id);
    if (opponentId) {
      this.send(opponentId, { type: 'opponent_finished', totalMs });
    }

    // Notify spectators
    this.notifySpectators(match.id, {
      type: 'spectate_event',
      kind: 'match_end',
      playerName: player.name,
      totalMs,
    });

    // Check if both players finished
    const p1Done = match.results.p1?.finished === true;
    const p2Done = match.p2Id === null || match.results.p2?.finished === true;

    if (p1Done && p2Done) {
      this.endMatch(match.id, null);
    }
  }

  // ─── Core match logic ─────────────────────────────────────────────────────────

  private tryPairFromQueue(): void {
    while (this.quickQueue.length >= 2) {
      const p1Id = this.quickQueue.shift()!;
      const p2Id = this.quickQueue.shift()!;

      const p1 = this.players.get(p1Id);
      const p2 = this.players.get(p2Id);

      // Sanity check: players must still be connected and queued
      if (!p1 || p1.state !== 'queued') {
        if (p2 && p2.state === 'queued') this.quickQueue.unshift(p2Id);
        continue;
      }
      if (!p2 || p2.state !== 'queued') {
        if (p1 && p1.state === 'queued') this.quickQueue.unshift(p1Id);
        continue;
      }

      p1.state = 'racing';
      p1.playerNumber = 1;
      p2.state = 'racing';
      p2.playerNumber = 2;

      const match = this.createMatch(p1Id, p2Id);
      p1.matchId = match.id;
      p2.matchId = match.id;

      this.startMatch(match.id);
    }

    // Update positions for remaining players in queue
    this.quickQueue.forEach((pid, idx) => {
      this.send(pid, { type: 'queued', position: idx + 1 });
    });
  }

  private createMatch(p1Id: string, p2Id: string | null): Match {
    const id = this.generateId();
    const code = this.generateCode();
    const p1 = this.players.get(p1Id);

    const match: Match = {
      id,
      code,
      state: p2Id === null ? 'lobby' : 'racing',
      p1Id,
      p2Id,
      startTime: null,
      spectatorIds: new Set(),
      results: { p1: null, p2: null },
      hostName: p1?.name ?? 'Jogador',
      createdAt: Date.now(),
    };

    this.matches.set(id, match);
    this.matches.set(code, match);  // double-index by code

    return match;
  }

  private startMatch(matchId: string): void {
    const match = this.matches.get(matchId);
    if (!match || !match.p2Id) return;

    match.state = 'racing';
    match.startTime = Date.now();

    const p1 = this.players.get(match.p1Id);
    const p2 = this.players.get(match.p2Id);

    if (p1 && p2) {
      p1.state = 'racing';
      p1.matchId = match.id;

      p2.state = 'racing';
      p2.matchId = match.id;

      this.send(p1.id, {
        type: 'match_start',
        code: match.code,
        opponentName: p2.name,
        playerNumber: 1,
      });
      this.send(p2.id, {
        type: 'match_start',
        code: match.code,
        opponentName: p1.name,
        playerNumber: 2,
      });

      this.notifySpectators(match.id, {
        type: 'spectate_event',
        kind: 'match_start',
        code: match.code,
        p1Name: p1.name,
        p2Name: p2.name,
      });

      console.log(`[Match] Iniciada: ${match.code} — ${p1.name} vs ${p2.name}`);
    }
  }

  private endMatch(matchId: string, forcedWinnerId: string | null): void {
    const match = this.matches.get(matchId);
    if (!match || match.state === 'finished') return;

    match.state = 'finished';

    const p1 = this.players.get(match.p1Id);
    const p2 = match.p2Id ? this.players.get(match.p2Id) : null;

    const p1Time = match.results.p1?.finishTime ?? null;
    const p2Time = match.results.p2?.finishTime ?? null;

    // Determine winner
    let winnerName: string | null = null;

    if (forcedWinnerId) {
      const winner = this.players.get(forcedWinnerId);
      winnerName = winner?.name ?? null;
    } else if (p1Time !== null && p2Time !== null) {
      winnerName = p1Time <= p2Time ? (p1?.name ?? null) : (p2?.name ?? null);
    } else if (p1Time !== null) {
      winnerName = p1?.name ?? null;
    } else if (p2Time !== null) {
      winnerName = p2?.name ?? null;
    }

    // Send match_end to both players
    if (p1) {
      this.send(p1.id, {
        type: 'match_end',
        winnerName,
        yourTime: p1Time,
        opponentTime: p2Time,
      });
      p1.state = 'idle';
      p1.matchId = null;
      p1.playerNumber = null;
    }
    if (p2) {
      this.send(p2.id, {
        type: 'match_end',
        winnerName,
        yourTime: p2Time,
        opponentTime: p1Time,
      });
      p2.state = 'idle';
      p2.matchId = null;
      p2.playerNumber = null;
    }

    // Notify spectators
    this.notifySpectators(matchId, {
      type: 'spectate_event',
      kind: 'match_end',
      winnerName,
      p1Time,
      p2Time,
    });

    // Kick spectators back to idle after notifying
    for (const specId of match.spectatorIds) {
      const spec = this.players.get(specId);
      if (spec) {
        spec.state = 'idle';
        spec.matchId = null;
      }
    }
    match.spectatorIds.clear();

    console.log(`[Match] Encerrada: ${match.code} — vencedor: ${winnerName ?? 'nenhum'}`);

    // Delete match after 5 seconds
    setTimeout(() => {
      this.matches.delete(matchId);
      this.matches.delete(match.code);
    }, 5000);
  }

  private notifySpectators(matchId: string, event: Record<string, unknown>): void {
    const match = this.matches.get(matchId);
    if (!match) return;

    for (const specId of match.spectatorIds) {
      this.send(specId, event as ServerMessage);
    }
  }

  // ─── Utilities ────────────────────────────────────────────────────────────────

  send(playerId: string, msg: ServerMessage | Record<string, unknown>): void {
    const player = this.players.get(playerId);
    if (!player) return;
    if (player.ws.readyState !== player.ws.OPEN) return;

    try {
      player.ws.send(JSON.stringify(msg));
    } catch {
      // Silently ignore send errors
    }
  }

  private generateCode(): string {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars
    let code: string;
    do {
      code = Array.from({ length: 5 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
    } while (this.matches.has(code));
    return code;
  }

  private generateId(): string {
    return crypto.randomUUID();
  }

  sanitizeName(name: unknown): string {
    if (typeof name !== 'string') return 'Jogador';
    const sanitized = name
      .trim()
      .replace(/[^a-zA-Z0-9À-ÿ ]/g, '')
      .slice(0, 20)
      .trim();
    return sanitized.length > 0 ? sanitized : 'Jogador';
  }

  private getOpponentId(match: Match, playerId: string): string | null {
    if (match.p1Id === playerId) return match.p2Id;
    if (match.p2Id === playerId) return match.p1Id;
    return null;
  }

  private removeFromAllSpectate(playerId: string): void {
    for (const match of this.getUniqueMatches()) {
      match.spectatorIds.delete(playerId);
    }
  }

  private getUniqueMatches(): Match[] {
    // matches are double-indexed; return only unique values
    const seen = new Set<string>();
    const result: Match[] = [];
    for (const [, match] of this.matches) {
      if (!seen.has(match.id)) {
        seen.add(match.id);
        result.push(match);
      }
    }
    return result;
  }

  private broadcastLobbyList(): void {
    const lobbies = this.getLobbies();
    // Notify all queued players and spectators about updated lobby list
    for (const [, player] of this.players) {
      if (player.state === 'idle' || player.state === 'spectating' || player.state === 'queued') {
        this.send(player.id, { type: 'lobby_list', lobbies });
      }
    }
  }

  // Expose for server to call when sending initial lobby list
  sendLobbyList(playerId: string): void {
    this.send(playerId, { type: 'lobby_list', lobbies: this.getLobbies() });
  }
}
