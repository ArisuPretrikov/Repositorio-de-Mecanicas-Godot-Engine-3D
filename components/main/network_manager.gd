extends Node

@export var server_url: String = "ws://localhost:8080"
@export var race_manager_path: NodePath
@export var horse_path: NodePath

signal match_started(opponent_name: String, player_number: int)
signal match_ended(winner_name: String, your_ms: float, opp_ms: float)

# ── Constantes ────────────────────────────────────────────────────────────────

const TOTAL_LAPS        := 3
const TOTAL_CHECKPOINTS := 4

const C_BG      := Color(0.051, 0.059, 0.078, 0.93)
const C_SURFACE := Color(0.086, 0.106, 0.149, 0.95)
const C_SURFACE2:= Color(0.118, 0.145, 0.204, 0.95)
const C_BORDER  := Color(0.165, 0.200, 0.278)
const C_ACCENT  := Color(0.961, 0.651, 0.137)
const C_BLUE    := Color(0.290, 0.604, 1.000)
const C_GREEN   := Color(0.298, 0.686, 0.490)
const C_RED     := Color(0.878, 0.333, 0.333)
const C_GOLD    := Color(1.000, 0.843, 0.000)
const C_SILVER  := Color(0.753, 0.753, 0.753)
const C_TEXT    := Color(0.910, 0.925, 0.957)
const C_DIM     := Color(0.541, 0.576, 0.659)

# ── Estado WebSocket ──────────────────────────────────────────────────────────

var _ws           := WebSocketPeer.new()
var _connected    := false
var _player_name  := ""
var _opp_name     := ""
var _match_code   := ""
var _race_active  := false
var _race_start_ms := 0

# ── Ghost do oponente ─────────────────────────────────────────────────────────

var _ghost: Node3D     = null
var _ghost_target_pos := Vector3.ZERO
var _ghost_target_ry  := 0.0
const _POS_INTERVAL   := 0.05
var _pos_tick         := 0.0

# ── Tracking HUD ──────────────────────────────────────────────────────────────

var _my_lap       := 0
var _my_cp        := 0
var _opp_lap      := 0
var _opp_cp       := 0
var _opp_finished := false
var _opp_time_ms  := 0.0

# ── Referências de UI ─────────────────────────────────────────────────────────

var _canvas: CanvasLayer

var _lobby_root:   Control
var _name_input:   LineEdit
var _code_input:   LineEdit
var _status_label: Label
var _code_display: Label
var _btn_quick:    Button
var _btn_create:   Button
var _btn_join:     Button

var _hud_root:     Control
var _hud_code_lbl: Label
var _my_name_lbl:  Label
var _my_lap_lbl:   Label
var _my_cp_lbl:    Label
var _my_time_lbl:  Label
var _my_prog:      Panel
var _opp_name_lbl: Label
var _opp_lap_lbl:  Label
var _opp_cp_lbl:   Label
var _opp_time_lbl: Label
var _opp_prog:     Panel

var _countdown_root: Control
var _countdown_lbl:  Label

var _result_root:    Control
var _result_ranking: VBoxContainer

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	_connect_race_manager()
	_set_horse_frozen(true)

func _process(delta: float) -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_set_status("Conectado. Escolha um modo.")
				_enable_buttons(true)
			while _ws.get_available_packet_count() > 0:
				_on_raw(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				_set_status("Desconectado. Tentando reconectar...")
				_enable_buttons(false)
				await get_tree().create_timer(3.0).timeout
				_connect_ws()

	if _race_active:
		if _my_time_lbl:
			_my_time_lbl.text = _fmt(Time.get_ticks_msec() - _race_start_ms)
		_pos_tick += delta
		if _pos_tick >= _POS_INTERVAL:
			_pos_tick = 0.0
			_send_position()

	# Ghost: interpola sempre que existir (inclusive durante countdown)
	if _ghost != null:
		_ghost.global_position = _ghost.global_position.lerp(_ghost_target_pos, 15.0 * delta)
		_ghost.global_rotation.y = lerp_angle(_ghost.global_rotation.y, _ghost_target_ry, 15.0 * delta)

# ── WebSocket ─────────────────────────────────────────────────────────────────

func _get_ws_url() -> String:
	if OS.has_feature("web"):
		var proto: String = JavaScriptBridge.eval(
			"window.location.protocol === 'https:' ? 'wss' : 'ws'"
		)
		var host: String = JavaScriptBridge.eval("window.location.host")
		return "%s://%s" % [proto, host]
	return server_url

func _connect_ws() -> void:
	if _ws.connect_to_url(_get_ws_url()) != OK:
		_set_status("Erro ao conectar.")

func _on_raw(text: String) -> void:
	var msg = JSON.parse_string(text)
	if msg is Dictionary and msg.has("type"):
		_on_message(msg)

func _send(data: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(data))

# ── Handlers de mensagens ─────────────────────────────────────────────────────

func _on_message(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"assigned":
			pass
		"queued":
			_set_status("Na fila... posição #%d" % msg.get("position", 1))
			_code_display.visible = false
		"lobby_created":
			_match_code = msg.get("code", "")
			_set_status("Aguardando oponente.")
			_code_display.text    = _match_code
			_code_display.visible = true
		"match_start":
			_match_code = msg.get("code", "")
			_on_match_start(msg.get("opponentName", "Oponente"), msg.get("playerNumber", 1))
		"opponent_checkpoint":
			_opp_cp = msg.get("checkpointIndex", 0)
			_update_opp()
		"opponent_lap":
			_opp_lap = msg.get("lap", 0)
			_opp_cp  = 0
			_update_opp()
		"opponent_finished":
			_opp_finished = true
			_opp_time_ms  = msg.get("totalMs", 0.0)
			_update_opp()
		"opponent_position":
			_ghost_target_pos = Vector3(
				msg.get("x", 0.0), msg.get("y", 0.0), msg.get("z", 0.0))
			_ghost_target_ry = msg.get("ry", 0.0)
		"opponent_disconnected":
			if _opp_name_lbl:
				_opp_name_lbl.add_theme_color_override("font_color", C_DIM)
				_opp_name_lbl.text = _opp_name + " (saiu)"
		"match_end":
			_on_match_end(msg)
		"error":
			_set_status("Erro: " + msg.get("message", ""))

# ── Lógica de partida ─────────────────────────────────────────────────────────

func _on_match_start(opp_name: String, player_num: int) -> void:
	_opp_name   = opp_name
	_my_lap  = 0;  _my_cp  = 0
	_opp_lap = 0;  _opp_cp = 0
	_opp_finished = false;  _opp_time_ms = 0.0
	_pos_tick = 0.0

	var rm := get_node_or_null(race_manager_path)
	if rm and rm.has_method("reset"):
		rm.reset()

	_lobby_root.visible = false
	_hud_root.visible   = true
	_hud_code_lbl.text  = "CORRIDA  •  %s" % _match_code
	_my_name_lbl.text   = _player_name if not _player_name.is_empty() else "Você"
	_opp_name_lbl.text  = opp_name
	_my_time_lbl.add_theme_color_override("font_color", C_ACCENT)
	_opp_time_lbl.add_theme_color_override("font_color", C_DIM)
	_opp_time_lbl.text  = "--:--.---"
	_update_my()
	_update_opp()

	_spawn_ghost(opp_name)
	_set_horse_frozen(true)   # mantém congelado durante countdown

	await _run_countdown()

	# Countdown terminou — corrida inicia de verdade
	_race_active   = true
	_race_start_ms = Time.get_ticks_msec()
	_set_horse_frozen(false)
	emit_signal("match_started", opp_name, player_num)
	print("[Net] Corrida iniciada vs %s (P%d) — %s" % [opp_name, player_num, _match_code])

func _on_match_end(msg: Dictionary) -> void:
	_race_active = false
	_destroy_ghost()

	var winner_name: String = msg.get("winnerName", "")
	var my_ms:       float  = msg.get("yourTime",      0.0)
	var opp_ms:      float  = msg.get("opponentTime",  0.0)

	_hud_root.visible    = false
	_result_root.visible = true
	_build_ranking(winner_name, my_ms, opp_ms)
	emit_signal("match_ended", winner_name, my_ms, opp_ms)

func _build_ranking(winner_name: String, my_ms: float, opp_ms: float) -> void:
	# Limpa linhas anteriores
	for child in _result_ranking.get_children():
		child.queue_free()

	# Determina 1° e 2° lugar
	var my_name   := _player_name if not _player_name.is_empty() else "Você"
	var opp_name  := _opp_name

	var p1_name: String; var p1_ms: float
	var p2_name: String; var p2_ms: float

	if winner_name == my_name or (my_ms > 0 and (opp_ms <= 0 or my_ms <= opp_ms)):
		p1_name = my_name;  p1_ms = my_ms
		p2_name = opp_name; p2_ms = opp_ms
	else:
		p1_name = opp_name; p1_ms = opp_ms
		p2_name = my_name;  p2_ms = my_ms

	_add_ranking_row("🏆", "1°", p1_name, p1_ms, C_GOLD,   true)
	_add_ranking_row("🥈", "2°", p2_name, p2_ms, C_SILVER, false)

func _add_ranking_row(icon: String, pos: String, name: String, ms: float, color: Color, is_first: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var sf := _make_sf(C_SURFACE2 if is_first else C_SURFACE, 8, is_first)
	if is_first:
		sf.border_color = C_GOLD
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", sf)
	bg.custom_minimum_size.y = 52
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_ranking.add_child(bg)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 12)
	hbox.set_offset(SIDE_LEFT, 14); hbox.set_offset(SIDE_RIGHT, -14)
	bg.add_child(hbox)

	# Ícone
	var icon_lbl := _label(icon, 22, color, HORIZONTAL_ALIGNMENT_LEFT)
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon_lbl)

	# Posição
	var pos_lbl := _label(pos, 13, color, HORIZONTAL_ALIGNMENT_LEFT)
	pos_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pos_lbl.custom_minimum_size.x = 28
	hbox.add_child(pos_lbl)

	# Nome
	var name_lbl := _label(name, 16, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	# Tempo
	var time_str := _fmt(int(ms)) if ms > 0 else "—"
	var time_lbl := _label(time_str, 16, color, HORIZONTAL_ALIGNMENT_RIGHT)
	time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_lbl.add_theme_font_size_override("font_size", 15)
	hbox.add_child(time_lbl)

# ── Countdown ─────────────────────────────────────────────────────────────────

func _run_countdown() -> void:
	_countdown_root.visible = true

	var steps := [
		["3",   C_RED,    120, 1.0],
		["2",   C_ACCENT, 120, 1.0],
		["1",   C_GREEN,  120, 1.0],
		["GO!", C_GREEN,  150, 0.7],
	]

	for step in steps:
		_countdown_lbl.text = step[0]
		_countdown_lbl.add_theme_color_override("font_color", step[1])
		_countdown_lbl.add_theme_font_size_override("font_size", step[2])
		# Pop: escala de 1.4 → 1.0
		_countdown_lbl.pivot_offset = _countdown_lbl.size * 0.5
		_countdown_lbl.scale = Vector2(1.4, 1.4)
		var tw := create_tween()
		tw.tween_property(_countdown_lbl, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(step[3]).timeout

	_countdown_root.visible = false

# ── Race-manager → servidor ───────────────────────────────────────────────────

func _connect_race_manager() -> void:
	var rm := get_node_or_null(race_manager_path)
	if not rm:
		push_warning("[Net] race_manager_path não configurado.")
		return
	rm.checkpoint_passed.connect(_on_local_checkpoint)
	rm.lap_completed.connect(_on_local_lap)
	rm.race_finished.connect(_on_local_finish)

func _on_local_checkpoint(index: int) -> void:
	if not _race_active: return
	_my_cp = index
	_update_my()
	_send({ "type": "checkpoint_passed", "checkpointIndex": index })

func _on_local_lap(lap: int, _total: int) -> void:
	if not _race_active: return
	_my_lap = lap
	_my_cp  = 0
	_update_my()
	_send({ "type": "lap_completed", "lap": lap,
		"elapsedMs": Time.get_ticks_msec() - _race_start_ms })

func _on_local_finish(final_time: float) -> void:
	if not _race_active: return
	_race_active = false
	_send({ "type": "race_finished", "totalMs": int(final_time * 1000.0) })

# ── Ghost ─────────────────────────────────────────────────────────────────────

func _spawn_ghost(opp_name: String) -> void:
	_destroy_ghost()
	_ghost = Node3D.new()

	var mesh_inst := MeshInstance3D.new()
	var capsule   := CapsuleMesh.new()
	capsule.radius = 0.45; capsule.height = 1.8
	mesh_inst.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(C_BLUE.r, C_BLUE.g, C_BLUE.b, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat
	mesh_inst.position.y = 0.9
	_ghost.add_child(mesh_inst)

	var lbl3d := Label3D.new()
	lbl3d.text = opp_name; lbl3d.position.y = 2.3
	lbl3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl3d.font_size = 28; lbl3d.modulate = C_BLUE; lbl3d.outline_size = 6
	_ghost.add_child(lbl3d)

	get_parent().add_child(_ghost)
	var horse := get_node_or_null(horse_path)
	if horse:
		_ghost.global_position = horse.global_position
		_ghost_target_pos = horse.global_position
		_ghost_target_ry  = horse.global_rotation.y

func _destroy_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null

func _send_position() -> void:
	var horse := get_node_or_null(horse_path)
	if not horse: return
	var p: Vector3 = horse.global_position
	_send({ "type": "position_update",
		"x": snappedf(p.x, 0.001), "y": snappedf(p.y, 0.001),
		"z": snappedf(p.z, 0.001), "ry": snappedf(horse.global_rotation.y, 0.001) })

# ── Cavalo ────────────────────────────────────────────────────────────────────

func _set_horse_frozen(frozen: bool) -> void:
	var horse := get_node_or_null(horse_path)
	if not horse: return
	horse.set_process(not frozen)
	horse.set_physics_process(not frozen)

# ── HUD helpers ───────────────────────────────────────────────────────────────

func _update_my() -> void:
	if not _hud_root or not _hud_root.visible: return
	_my_lap_lbl.text = "Volta  %d / %d" % [_my_lap, TOTAL_LAPS]
	_my_cp_lbl.text  = "CP  %d / %d"    % [_my_cp,  TOTAL_CHECKPOINTS]
	_my_prog.anchor_right = _progress(_my_lap, _my_cp)

func _update_opp() -> void:
	if not _hud_root or not _hud_root.visible: return
	_opp_lap_lbl.text = "Volta  %d / %d" % [_opp_lap, TOTAL_LAPS]
	_opp_cp_lbl.text  = "CP  %d / %d"    % [_opp_cp,  TOTAL_CHECKPOINTS]
	_opp_prog.anchor_right = _progress(_opp_lap, _opp_cp)
	if _opp_finished and _opp_time_ms > 0:
		_opp_time_lbl.text = _fmt(int(_opp_time_ms))
		_opp_time_lbl.add_theme_color_override("font_color", C_GREEN)

func _progress(lap: int, cp: int) -> float:
	return minf(float(lap * TOTAL_CHECKPOINTS + cp) / float(TOTAL_LAPS * TOTAL_CHECKPOINTS), 1.0)

func _fmt(ms: int) -> String:
	return "%02d:%02d.%03d" % [ms / 60000, (ms % 60000) / 1000, ms % 1000]

# ── Construção da UI ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)
	_build_lobby_panel()
	_build_hud()
	_build_countdown_overlay()
	_build_result_screen()
	_connect_ws()
	_set_status("Conectando...")
	_enable_buttons(false)

# ── Lobby ─────────────────────────────────────────────────────────────────────

func _build_lobby_panel() -> void:
	_lobby_root = _panel_centered(Vector2(440, 340))
	_canvas.add_child(_lobby_root)

	var vbox := _vbox(10)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby_root.add_child(vbox)

	vbox.add_child(_label("🏇 Corrida Multiplayer", 22, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))

	_name_input = _line_edit("Seu nome...", 36)
	vbox.add_child(_name_input)

	var hbox := _hbox(8)
	vbox.add_child(hbox)
	_btn_quick  = _btn("⚡ Quick Match", _on_quick_match,  C_ACCENT,   Color(0.1, 0.06, 0.0))
	_btn_create = _btn("🏠 Criar Lobby", _on_create_lobby, C_SURFACE2, C_TEXT)
	hbox.add_child(_btn_quick)
	hbox.add_child(_btn_create)

	var hbox2 := _hbox(8)
	vbox.add_child(hbox2)
	_code_input = _line_edit("Código do lobby...", 36)
	_code_input.custom_minimum_size.x = 130
	hbox2.add_child(_code_input)
	_btn_join = _btn("🔑 Entrar", _on_join_lobby, C_BLUE, Color(0.0, 0.05, 0.15))
	hbox2.add_child(_btn_join)

	_status_label = _label("", 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	_code_display = _label("", 42, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_code_display.visible = false
	vbox.add_child(_code_display)

# ── HUD ───────────────────────────────────────────────────────────────────────

func _build_hud() -> void:
	_hud_root = Control.new()
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.visible = false
	_canvas.add_child(_hud_root)

	var code_bar := Panel.new()
	code_bar.set_anchor(SIDE_LEFT, 0.5); code_bar.set_anchor(SIDE_RIGHT, 0.5)
	code_bar.set_anchor(SIDE_TOP,  0.0); code_bar.set_anchor(SIDE_BOTTOM, 0.0)
	code_bar.set_offset(SIDE_LEFT, -180); code_bar.set_offset(SIDE_RIGHT,  180)
	code_bar.set_offset(SIDE_TOP,    10); code_bar.set_offset(SIDE_BOTTOM,  42)
	var cs := _make_sf(C_SURFACE, 20, 1)
	cs.border_color = C_BORDER
	code_bar.add_theme_stylebox_override("panel", cs)
	_hud_root.add_child(code_bar)

	_hud_code_lbl = _label("", 14, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_hud_code_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_code_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	code_bar.add_child(_hud_code_lbl)

	var my_data  := _make_player_panel(true)
	var opp_data := _make_player_panel(false)
	_hud_root.add_child(my_data.root)
	_hud_root.add_child(opp_data.root)

	_my_name_lbl  = my_data.name_lbl;  _my_lap_lbl  = my_data.lap_lbl
	_my_cp_lbl    = my_data.cp_lbl;    _my_time_lbl = my_data.time_lbl
	_my_prog      = my_data.prog_fill

	_opp_name_lbl = opp_data.name_lbl; _opp_lap_lbl = opp_data.lap_lbl
	_opp_cp_lbl   = opp_data.cp_lbl;   _opp_time_lbl = opp_data.time_lbl
	_opp_prog     = opp_data.prog_fill

class _PanelData:
	var root: Panel; var name_lbl: Label; var lap_lbl: Label
	var cp_lbl: Label; var time_lbl: Label; var prog_fill: Panel

func _make_player_panel(is_me: bool) -> _PanelData:
	const W = 240.0; const H = 190.0; const MG = 14.0; const TOP = 52.0
	var accent := C_ACCENT if is_me else C_BLUE

	var root := Panel.new()
	var sf   := _make_sf(C_SURFACE, 10, 2)
	sf.border_color = accent
	root.add_theme_stylebox_override("panel", sf)

	if is_me:
		root.set_anchor(SIDE_LEFT, 0.0); root.set_anchor(SIDE_RIGHT, 0.0)
		root.set_offset(SIDE_LEFT, MG);  root.set_offset(SIDE_RIGHT, MG + W)
	else:
		root.set_anchor(SIDE_LEFT, 1.0); root.set_anchor(SIDE_RIGHT, 1.0)
		root.set_offset(SIDE_LEFT, -(MG + W)); root.set_offset(SIDE_RIGHT, -MG)
	root.set_anchor(SIDE_TOP, 0.0); root.set_anchor(SIDE_BOTTOM, 0.0)
	root.set_offset(SIDE_TOP, TOP); root.set_offset(SIDE_BOTTOM, TOP + H)

	var vbox := _vbox(7)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.set_offset(SIDE_LEFT, 14); vbox.set_offset(SIDE_RIGHT,  -14)
	vbox.set_offset(SIDE_TOP,  14); vbox.set_offset(SIDE_BOTTOM, -14)
	root.add_child(vbox)

	vbox.add_child(_label("VOCÊ" if is_me else "OPONENTE", 10, accent, HORIZONTAL_ALIGNMENT_LEFT))
	var name_lbl := _label("---", 17, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	vbox.add_child(name_lbl)

	var sep_style := StyleBoxLine.new(); sep_style.color = C_BORDER
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	var lap_lbl  := _label("Volta  0 / %d" % TOTAL_LAPS,        14, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	var cp_lbl   := _label("CP  0 / %d"    % TOTAL_CHECKPOINTS, 13, C_DIM,  HORIZONTAL_ALIGNMENT_LEFT)
	var time_lbl := _label("00:00.000" if is_me else "--:--.---", 19, accent, HORIZONTAL_ALIGNMENT_LEFT)
	vbox.add_child(lap_lbl); vbox.add_child(cp_lbl); vbox.add_child(time_lbl)

	var prog_bg := Panel.new()
	prog_bg.custom_minimum_size = Vector2(0, 8)
	prog_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog_bg.add_theme_stylebox_override("panel", _make_sf(C_BORDER, 4, 0))
	vbox.add_child(prog_bg)

	var prog_fill := Panel.new()
	prog_fill.set_anchor(SIDE_LEFT, 0.0); prog_fill.set_anchor(SIDE_TOP,    0.0)
	prog_fill.set_anchor(SIDE_RIGHT, 0.0); prog_fill.set_anchor(SIDE_BOTTOM, 1.0)
	prog_fill.set_offset(SIDE_LEFT, 0); prog_fill.set_offset(SIDE_RIGHT,  0)
	prog_fill.set_offset(SIDE_TOP,  0); prog_fill.set_offset(SIDE_BOTTOM, 0)
	prog_fill.add_theme_stylebox_override("panel", _make_sf(accent, 4, 0))
	prog_bg.add_child(prog_fill)

	var d := _PanelData.new()
	d.root = root; d.name_lbl = name_lbl; d.lap_lbl = lap_lbl
	d.cp_lbl = cp_lbl; d.time_lbl = time_lbl; d.prog_fill = prog_fill
	return d

# ── Countdown overlay ─────────────────────────────────────────────────────────

func _build_countdown_overlay() -> void:
	_countdown_root = Control.new()
	_countdown_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_root.visible = false
	_canvas.add_child(_countdown_root)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	_countdown_root.add_child(bg)

	_countdown_lbl = _label("3", 120, C_RED, HORIZONTAL_ALIGNMENT_CENTER)
	_countdown_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_lbl.add_theme_font_size_override("font_size", 120)
	_countdown_root.add_child(_countdown_lbl)

# ── Resultado ─────────────────────────────────────────────────────────────────

func _build_result_screen() -> void:
	_result_root = _panel_centered(Vector2(460, 310))
	_result_root.visible = false
	_canvas.add_child(_result_root)

	var vbox := _vbox(16)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_root.add_child(vbox)

	var title := _label("Resultado da Corrida", 22, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(title)

	var sep_style := StyleBoxLine.new(); sep_style.color = C_BORDER
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	_result_ranking = _vbox(8)
	_result_ranking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_result_ranking)

	var replay := _btn("🔄  Jogar Novamente", func():
		_destroy_ghost()
		_result_root.visible = false
		_lobby_root.visible  = true
		_enable_buttons(true)
		_set_status("Conectado. Escolha um modo.")
		_set_horse_frozen(true)
	, C_ACCENT, Color(0.1, 0.06, 0.0))
	replay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(replay)

# ── Fábrica de controles ──────────────────────────────────────────────────────

func _make_sf(color: Color, radius: int, border: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left    = radius; s.corner_radius_top_right    = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	s.border_width_left  = border; s.border_width_right  = border
	s.border_width_top   = border; s.border_width_bottom = border
	return s

func _panel_centered(size: Vector2) -> Panel:
	var p := Panel.new()
	var s := _make_sf(C_BG, 10, 1)
	s.border_color = C_BORDER
	s.content_margin_left  = 22; s.content_margin_right  = 22
	s.content_margin_top   = 22; s.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = size
	p.set_anchor(SIDE_LEFT,   0.5); p.set_anchor(SIDE_RIGHT,  0.5)
	p.set_anchor(SIDE_TOP,    0.5); p.set_anchor(SIDE_BOTTOM, 0.5)
	p.set_offset(SIDE_LEFT,   -size.x * 0.5); p.set_offset(SIDE_RIGHT,  size.x * 0.5)
	p.set_offset(SIDE_TOP,    -size.y * 0.5); p.set_offset(SIDE_BOTTOM, size.y * 0.5)
	return p

func _label(text: String, size: int, color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

func _line_edit(placeholder: String, min_h: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size.y = min_h
	return e

func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", sep); return h

func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", sep); return v

func _btn(text: String, cb: Callable, bg: Color, fg: Color = C_TEXT) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_stylebox_override("normal",  _make_sf(bg,                 6, 0))
	b.add_theme_stylebox_override("hover",   _make_sf(bg.lightened(0.15), 6, 0))
	b.add_theme_stylebox_override("pressed", _make_sf(bg.darkened(0.10),  6, 0))
	return b

func _set_status(msg: String) -> void:
	if _status_label: _status_label.text = msg

func _enable_buttons(enabled: bool) -> void:
	if _btn_quick:  _btn_quick.disabled  = not enabled
	if _btn_create: _btn_create.disabled = not enabled
	if _btn_join:   _btn_join.disabled   = not enabled

# ── Ações dos botões ──────────────────────────────────────────────────────────

func _on_quick_match() -> void:
	_player_name = _name_input.text.strip_edges()
	if _player_name.is_empty(): _set_status("Digite seu nome."); return
	if not _connected:
		_set_status("Conectando..."); _connect_ws()
		await get_tree().create_timer(1.5).timeout
	_send({ "type": "quick_join", "name": _player_name })
	_set_status("Entrando na fila...")
	_enable_buttons(false)

func _on_create_lobby() -> void:
	_player_name = _name_input.text.strip_edges()
	if _player_name.is_empty(): _set_status("Digite seu nome."); return
	if not _connected:
		_connect_ws(); await get_tree().create_timer(1.5).timeout
	_send({ "type": "create_lobby", "name": _player_name })
	_enable_buttons(false)

func _on_join_lobby() -> void:
	_player_name = _name_input.text.strip_edges()
	var code := _code_input.text.strip_edges().to_upper()
	if _player_name.is_empty() or code.is_empty():
		_set_status("Preencha nome e código."); return
	if not _connected:
		_connect_ws(); await get_tree().create_timer(1.5).timeout
	_send({ "type": "join_lobby", "name": _player_name, "code": code })
	_enable_buttons(false)
