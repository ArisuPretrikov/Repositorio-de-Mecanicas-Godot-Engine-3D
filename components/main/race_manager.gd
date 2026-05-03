extends Node

signal lap_completed(lap: int, total: int)
signal race_finished(final_time: float)

const TOTAL_LAPS := 3

# Nome do nó → índice lógico do checkpoint
# Variantes _1 e _2 mapeiam para o mesmo índice: passou um, contabilizou
const CHECKPOINT_INDEX := {
	"Checkpoint_01": 0,
	"Checkpoint_02": 1,
	"Checkpoint_03": 2,
	"Checkpoint_04_1": 3,
	"Checkpoint_04_2": 3,
	"Checkpoint_05_1": 4,
	"Checkpoint_05_2": 4,
}

const LAST_INDEX := 4  # maior índice lógico antes de voltar ao 01

# Configure no Inspector apontando para os nós corretos
@export var checkpoints_node: NodePath
@export var horse_node: NodePath

var _lap: int = 0
var _passed := {}      # índice lógico → true
var _started := false
var _finished := false
var _time := 0.0

func _ready() -> void:
	_connect_checkpoints()

func _process(delta: float) -> void:
	if _started and not _finished:
		_time += delta

# ── Conexão ───────────────────────────────────────────────────────────────────

func _connect_checkpoints() -> void:
	var container := get_node_or_null(checkpoints_node)
	if not container:
		push_error("RaceManager: defina 'checkpoints_node' no Inspector.")
		return

	var conectados := 0
	for child in container.get_children():
		if child is Area3D and CHECKPOINT_INDEX.has(child.name):
			child.body_entered.connect(_on_area_entered.bind(child.name))
			conectados += 1

	print("[Race] %d checkpoints conectados." % conectados)

# ── Detecção ──────────────────────────────────────────────────────────────────

func _on_area_entered(body: Node3D, cp_name: String) -> void:
	var horse := get_node_or_null(horse_node)
	if horse == null or body != horse:
		return
	_handle(CHECKPOINT_INDEX[cp_name], cp_name)

# ── Lógica da corrida ─────────────────────────────────────────────────────────

func _handle(idx: int, cp_name: String) -> void:
	if _finished:
		return

	if idx == 0:
		_handle_start_finish()
		return

	if not _started or _passed.has(idx):
		return

	# Garante que todos os checkpoints anteriores já foram passados
	for i in range(1, idx):
		if not _passed.has(i):
			print("[Race] Ordem inválida — passou %s antes do checkpoint %d." % [cp_name, i])
			return

	_passed[idx] = true
	print("[Race] %s ✓  (%d/%d)" % [cp_name, _passed.size(), LAST_INDEX])

func _handle_start_finish() -> void:
	if not _started:
		_started = true
		_passed.clear()
		print("[Race] Corrida iniciada!")
		return

	if not _all_passed():
		print("[Race] Volta inválida — faltam checkpoints.")
		return

	_lap += 1
	_passed.clear()
	emit_signal("lap_completed", _lap, TOTAL_LAPS)
	print("[Race] Volta %d/%d completa!" % [_lap, TOTAL_LAPS])

	if _lap >= TOTAL_LAPS:
		_finished = true
		emit_signal("race_finished", _time)
		print("[Race] Corrida finalizada! Tempo: %.2fs" % _time)

func _all_passed() -> bool:
	for i in range(1, LAST_INDEX + 1):
		if not _passed.has(i):
			return false
	return true
