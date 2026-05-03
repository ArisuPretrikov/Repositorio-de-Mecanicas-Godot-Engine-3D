import { WebSocket } from 'ws';
export type PlayerState = 'idle' | 'queued' | 'lobby_waiting' | 'racing' | 'spectating';
export type MatchState = 'lobby' | 'racing' | 'finished';
export interface RateLimit {
    count: number;
    resetAt: number;
}
export interface Player {
    id: string;
    ws: WebSocket;
    name: string;
    state: PlayerState;
    matchId: string | null;
    playerNumber: 1 | 2 | null;
    rateLimit: RateLimit;
    isAlive: boolean;
}
export interface PlayerResult {
    playerId: string;
    name: string;
    finishTime: number | null;
    finished: boolean;
}
export interface Match {
    id: string;
    code: string;
    state: MatchState;
    p1Id: string;
    p2Id: string | null;
    startTime: number | null;
    spectatorIds: Set<string>;
    results: {
        p1: PlayerResult | null;
        p2: PlayerResult | null;
    };
    hostName: string;
    createdAt: number;
}
export interface MsgQuickJoin {
    type: 'quick_join';
    name: string;
}
export interface MsgCreateLobby {
    type: 'create_lobby';
    name: string;
}
export interface MsgJoinLobby {
    type: 'join_lobby';
    name: string;
    code: string;
}
export interface MsgSpectate {
    type: 'spectate';
    code: string;
}
export interface MsgLeaveSpectate {
    type: 'leave_spectate';
}
export interface MsgCheckpointPassed {
    type: 'checkpoint_passed';
    checkpointIndex: number;
}
export interface MsgLapCompleted {
    type: 'lap_completed';
    lap: number;
    elapsedMs: number;
}
export interface MsgRaceFinished {
    type: 'race_finished';
    totalMs: number;
}
export interface MsgPing {
    type: 'ping';
}
export type ClientMessage = MsgQuickJoin | MsgCreateLobby | MsgJoinLobby | MsgSpectate | MsgLeaveSpectate | MsgCheckpointPassed | MsgLapCompleted | MsgRaceFinished | MsgPing;
export interface SrvAssigned {
    type: 'assigned';
    playerId: string;
}
export interface SrvQueued {
    type: 'queued';
    position: number;
}
export interface SrvLobbyCreated {
    type: 'lobby_created';
    code: string;
}
export interface SrvMatchStart {
    type: 'match_start';
    code: string;
    opponentName: string;
    playerNumber: 1 | 2;
}
export interface SrvOpponentCheckpoint {
    type: 'opponent_checkpoint';
    checkpointIndex: number;
}
export interface SrvOpponentLap {
    type: 'opponent_lap';
    lap: number;
    elapsedMs: number;
}
export interface SrvOpponentFinished {
    type: 'opponent_finished';
    totalMs: number;
}
export interface SrvMatchEnd {
    type: 'match_end';
    winnerName: string | null;
    yourTime: number | null;
    opponentTime: number | null;
}
export interface SrvOpponentDisconnected {
    type: 'opponent_disconnected';
}
export interface SrvSpectateOk {
    type: 'spectate_ok';
    code: string;
    p1Name: string;
    p2Name: string | null;
    matchState: MatchState;
}
export interface SrvSpectateEvent {
    type: 'spectate_event';
    kind: 'match_start' | 'checkpoint' | 'lap' | 'match_end';
    [key: string]: unknown;
}
export interface LobbyEntry {
    code: string;
    hostName: string;
    createdAt: number;
}
export interface SrvLobbyList {
    type: 'lobby_list';
    lobbies: LobbyEntry[];
}
export interface SrvError {
    type: 'error';
    message: string;
}
export interface SrvPong {
    type: 'pong';
}
export type ServerMessage = SrvAssigned | SrvQueued | SrvLobbyCreated | SrvMatchStart | SrvOpponentCheckpoint | SrvOpponentLap | SrvOpponentFinished | SrvMatchEnd | SrvOpponentDisconnected | SrvSpectateOk | SrvSpectateEvent | SrvLobbyList | SrvError | SrvPong;
//# sourceMappingURL=types.d.ts.map