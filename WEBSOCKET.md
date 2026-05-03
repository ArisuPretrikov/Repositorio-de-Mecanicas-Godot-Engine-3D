# WebSocket Multiplayer — Corrida de Cavalos

Servidor WebSocket para gerenciar partidas multiplayer do jogo de corrida.

---

## Stack

| Camada | Tecnologia |
|---|---|
| Servidor | Node.js + TypeScript + `ws` |
| Cliente | HTML + CSS + JavaScript (vanilla) |
| Protocolo | WebSocket (JSON) |

---

## Como rodar

```bash
cd websocket-server
npm install
npm run dev          # desenvolvimento (ts-node, hot-reload manual)
# ou
npm run build && npm start   # produção (node dist/)
```

Porta padrão: **8080**. Para mudar: `PORT=3000 npm start`

Abrir o cliente: `websocket-server/client/index.html` no browser.

---

## Estrutura de arquivos

```
websocket-server/
├── src/
│   ├── types.ts          — interfaces TypeScript (Player, Match, mensagens)
│   ├── match-manager.ts  — toda a lógica de partidas, lobby, fila, espectador
│   └── server.ts         — servidor WS, roteamento, segurança, heartbeat
├── client/
│   └── index.html        — cliente HTML completo (CSS + JS inline)
├── package.json
└── tsconfig.json
```

---

## Fluxo de partidas

### Quick Match
```
Cliente A: quick_join {name}  →  servidor: queued {position: 1}
Cliente B: quick_join {name}  →  servidor emparelha automaticamente
Ambos recebem: match_start {code, opponentName, playerNumber}
```

### Lobby (com código)
```
Cliente A: create_lobby {name}  →  servidor: lobby_created {code: "X67S2"}
Cliente B: join_lobby {name, code: "X67S2"}  →  servidor inicia partida
Ambos recebem: match_start {code, opponentName, playerNumber}
```

### Múltiplas partidas simultâneas
O servidor mantém um `Map<id, Match>` independente por partida. Cada par de jogadores tem seu próprio estado isolado. Não há limite de partidas paralelas além do `MAX_CONNECTIONS = 100`.

---

## Protocolo de mensagens

### Cliente → Servidor

| `type` | Campos | Descrição |
|---|---|---|
| `quick_join` | `name: string` | Entra na fila de quick match |
| `create_lobby` | `name: string` | Cria lobby e aguarda com código |
| `join_lobby` | `name, code` | Entra em lobby existente pelo código |
| `spectate` | `code` | Assiste uma partida |
| `leave_spectate` | — | Para de assistir |
| `checkpoint_passed` | `checkpointIndex: number` | Passa por um checkpoint |
| `lap_completed` | `lap, elapsedMs` | Completa uma volta |
| `race_finished` | `totalMs: number` | Finaliza a corrida |
| `ping` | — | Keepalive manual (JSON) |

### Servidor → Cliente

| `type` | Campos | Descrição |
|---|---|---|
| `assigned` | `playerId` | ID único atribuído ao conectar |
| `queued` | `position` | Posição na fila de quick match |
| `lobby_created` | `code` | Código do lobby criado |
| `match_start` | `code, opponentName, playerNumber` | Partida iniciada |
| `opponent_checkpoint` | `checkpointIndex` | Oponente passou checkpoint |
| `opponent_lap` | `lap, elapsedMs` | Oponente completou volta |
| `opponent_finished` | `totalMs` | Oponente terminou a corrida |
| `match_end` | `winnerName, yourTime, opponentTime` | Resultado final |
| `opponent_disconnected` | — | Oponente desconectou (W.O.) |
| `spectate_ok` | `code, p1Name, p2Name, matchState` | Snapshot ao entrar como espectador |
| `spectate_event` | `kind, ...data` | Atualização em tempo real para espectadores |
| `lobby_list` | `lobbies[]` | Lista de lobbies abertos |
| `error` | `message` | Erro de validação ou protocolo |
| `pong` | — | Resposta ao ping manual |

---

## Ciclo de vida de uma partida

```
lobby / queued
	  ↓  (ambos conectados)
   racing
	  ↓  (ambos enviam race_finished OU um desconecta)
   finished  ←  match_end enviado para jogadores + espectadores
	  ↓  (5 segundos)
   [removida do servidor]
```

---

## Segurança

| Medida | Detalhe |
|---|---|
| Rate limiting | Máx 30 mensagens/segundo por cliente. Excedeu → `error` + desconexão |
| Max conexões | 100 conexões simultâneas. Nova conexão além disso é rejeitada imediatamente |
| Heartbeat | Ping nativo WS a cada 30s. Sem pong em 30s → `terminate()` |
| Sanitização de nome | Trim, máx 20 chars, apenas letras/números/espaços. Fallback: `"Jogador"` |
| Validação de input | Todo JSON parseado tem `type` verificado. Campos inválidos retornam `error` |
| Códigos legíveis | Alfabeto sem I/O/0/1 (`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`) para evitar confusão visual |

---

## Modo Espectador

Qualquer cliente pode assistir uma partida em andamento usando o código:

```json
{ "type": "spectate", "code": "X67S2" }
```

O servidor envia o snapshot atual da partida (`spectate_ok`) e, a partir daí, encaminha todos os eventos da partida em tempo real (`spectate_event`). Ao fim da partida, espectadores recebem o `spectate_event` de tipo `match_end`.

---

## Cliente HTML

O `client/index.html` é um arquivo único (sem dependências externas) com 5 telas:

| Tela | Quando aparece |
|---|---|
| **Welcome** | Ao abrir. Escolha entre Quick Match, Criar Lobby, Entrar em Lobby, Espectador |
| **Waiting** | Após `quick_join`, aguardando par. Mostra posição na fila |
| **Lobby** | Após `create_lobby`. Exibe código grande para compartilhar |
| **Racing** | Após `match_start`. Painel VOCÊ vs OPONENTE, botões de checkpoint, Auto-Simular |
| **Results** | Após `match_end`. Vencedor destacado, tempos, botão "Jogar Novamente" |

**Auto-Simular**: passa checkpoints (0→4) com delays aleatórios de 500–2000ms, repete por 3 voltas e finaliza automaticamente.

---

## Integração com Godot (NetworkManager)

O arquivo `components/main/network_manager.gd` já está implementado e conectado à cena `main_pista.tscn`. O nó `NetworkManager` foi adicionado como filho de `main_pista.tscn` com as propriedades configuradas:

```
race_manager_path = NodePath("../RaceManager")
horse_path        = NodePath("../Horse")
```

**Sinais emitidos pelo NetworkManager:**
- `match_started(opponent_name: String, player_number: int)` — partida iniciada
- `match_ended(winner_name: String, your_ms: float, opp_ms: float)` — corrida terminada

**Modo desenvolvimento (editor):** o script conecta em `ws://localhost:8080` por padrão.

**Modo web (export):** detecta automaticamente o host via `JavaScriptBridge` e conecta ao mesmo servidor que serviu a página, usando `wss://` se o site for HTTPS.

---

## Export Web do Godot (jogar no navegador)

O servidor já serve os arquivos do jogo em `http://localhost:8080/game/`.

### Passo a passo

**1. Instalar o template de export web no Godot 4.6**
- No editor: `Editor → Export → Manage Export Templates → Download`
- Baixa os templates para a versão do Godot instalada

**2. Configurar o preset de export**
- `Editor → Export → Add... → Web`
- Em **Export Path**, coloque:
  ```
  websocket-server/client/game/index.html
  ```
- Em **Extensions** → marque `Export With Debug` se quiser depurar no browser

**3. Exportar**
```
Project → Export → Web → Export Project
```
Ou via linha de comando:
```bash
godot --export-release "Web" websocket-server/client/game/index.html
```

**4. Rodar o servidor e jogar**
```bash
cd websocket-server
npm install
npm run dev
```
Abra `http://localhost:8080/game/` no navegador.

> **Importante:** os browsers exigem `Cross-Origin-Opener-Policy: same-origin` e `Cross-Origin-Embedder-Policy: require-corp` para o Godot Web funcionar com threads/SharedArrayBuffer. O servidor já envia esses headers automaticamente em todos os arquivos estáticos.

> **Importante 2:** abrir `index.html` diretamente pelo sistema de arquivos (`file://`) não funciona — use sempre o servidor HTTP (`http://localhost:8080`).

### Estrutura esperada após o export

```
websocket-server/client/
├── index.html         ← cliente HTML de lobby
└── game/
	├── index.html     ← jogo Godot exportado
	├── index.js
	├── index.wasm
	├── index.pck
	└── index.worker.js
```
