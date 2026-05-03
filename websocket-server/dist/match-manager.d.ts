import { WebSocket } from 'ws';
import { Player, ClientMessage, ServerMessage, LobbyEntry } from './types';
export declare class MatchManager {
    players: Map<string, Player>;
    private matches;
    quickQueue: string[];
    addPlayer(id: string, ws: WebSocket): Player;
    removePlayer(id: string): void;
    handleMessage(playerId: string, msg: ClientMessage): void;
    getLobbies(): LobbyEntry[];
    private handleQuickJoin;
    private handleCreateLobby;
    private handleJoinLobby;
    private handleSpectate;
    private handleLeaveSpectate;
    private handleCheckpointPassed;
    private handleLapCompleted;
    private handleRaceFinished;
    private tryPairFromQueue;
    private createMatch;
    private startMatch;
    private endMatch;
    private notifySpectators;
    send(playerId: string, msg: ServerMessage | Record<string, unknown>): void;
    private generateCode;
    private generateId;
    sanitizeName(name: unknown): string;
    private getOpponentId;
    private removeFromAllSpectate;
    private getUniqueMatches;
    private broadcastLobbyList;
    sendLobbyList(playerId: string): void;
}
//# sourceMappingURL=match-manager.d.ts.map