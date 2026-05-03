# 🐎 Simple GDD: Corrida de Cavalo

**Versão:** 0.1 | **Gênero:** Racing / Party / Multiplayer

**Status:** Rascunho Inicial (MVP)

---

## 📋 Visão Geral

Jogo de corrida de cavalos inspirado na dinâmica de *Mario Kart*. Os jogadores competem em um circuito fechado de **3 voltas**, utilizando **Lucky Blocks** para obter vantagens (buffs) ou sofrer consequências (debuffs). O objetivo é cruzar a linha de chegada em primeiro lugar.

---

## ⚙️ Parâmetros Principais

| **Parâmetro** | **Valor/Tipo** |
| --- | --- |
| **Voltas** | 3 |
| **Limite de Buffs/Debuffs** | 1 por vez |
| **Distribuição** | Aleatória (Random Roll) |
| **Ícone de Coleta** | Lucky Block (Textura customizada) |
| **Controle de Rota** | Sistema de Checkpoints |

---

## 🕹️ Mecânicas de Jogo

### 🏁 Pista e Checkpoints

- Circuito fechado com colisões laterais.
- Checkpoints invisíveis garantem que o jogador percorra todo o trajeto antes de validar a volta.
- A linha de chegada funciona como o gatilho final para o contador.

### 📦 Sistema de Lucky Block

- Blocos posicionados em pontos da pista.
- **Trigger:** Ao colidir, o bloco some temporariamente e sorteia um Buff ou Debuff.

### 🔢 HUD & Interface

- Contador de voltas em tempo real (ex: 1/3).
- Slot visual mostrando o Buff/Debuff aplicado.
- Feedback de "Fim de Jogo" com a colocação dos jogadores.

---

## 🧪 Power-ups (Buffs & Debuffs)

### 🟢 BUFFS (Vantagens/Ataque)

- 💩 **Merda de Cavalo:**
	- **Ação:** Lançado contra um adversário à frente.
	- **Efeito:** Reduz a visão (overlay na tela) e diminui a velocidade do alvo.
- ⚡ **Velocidade:**
	- **Ação:** Uso imediato.
	- **Efeito:** Multiplica a velocidade atual por 2.0X por tempo limitado.

### 🔴 DEBUFFS (Riscos/Atraso)

- 😤 **Cavalo Estressado:**
	- **Ação:** Ativado imediatamente ao coletar.
	- **Efeito:** Derruba o jogador; requer tempo de animação (Se tiver e der tempo) para montar novamente (parada total).
- 🟫 **Lama:**
	- **Ação:** Ativado imediatamente ao coletar.
	- **Efeito:** Reduz a velocidade e aplica um efeito visual de sujeira na câmera por alguns segundos.
