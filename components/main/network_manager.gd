extends Node

## Conecta o jogo Godot ao servidor WebSocket de corrida.
## Como usar:
##   1. Adicione um nó Node em main_pista.tscn, renomeie para "NetworkManager"
##   2. Anexe este script
##   3. Configure race_manager_path e horse_path no Inspector
##   4. Rode o servidor: cd websocket-server && npm run dev

@export var server_url: String = "ws://localhost:8080"
@export var race_manager_path: NodePath
@export var horse_path: NodePath

signal match_started(opponent_name: String, player_number: int)
signal match_ended(winner_name: String, your_ms: float, opp_ms: float)

# ── Estado ────────────────────────────────────────────────────────────────────

var _ws := WebSocketPeer.new()
var _connected := false
var _player_name := ""
var _match_code := ""
var _race_active := false
var _race_start_ms := 0

# ── Referências de UI (criadas em _ready) ─────────────────────────────────────

var _canvas: CanvasLayer
var _lobby_root: Control      # painel pré-corrida (visível até match_start)
var _name_input: LineEdit
var _code_input: LineEdit
var _status_label: Label
var _code_display: Label      # exibe código do lobby em letras grandes
var _btn_quick: Button
var _btn_create: Button
var _btn_join: Button

var _hud_root: Control        # HUD de oponente durante a corrida
var _opp_label: Label

var _result_root: Control     # tela de resultado
var _result_label: Label

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	_connect_race_manager()
	_set_horse_frozen(true)

func _process(_delta: float) -> void:
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

# ── Conexão WS ────────────────────────────────────────────────────────────────

func _get_ws_url() -> String:
	if OS.has_feature("web"):
		# No export web: conecta ao mesmo host:porta que serviu a página
		var proto: String = JavaScriptBridge.eval(
			"window.location.protocol === 'https:' ? 'wss' : 'ws'"
		)
		var host: String = JavaScriptBridge.eval("window.location.host")
		return "%s://%s" % [proto, host]
	return server_url

func _connect_ws() -> void:
	var url := _get_ws_url()
	var err := _ws.connect_to_url(url)
	if err != OK:
		_set_status("Erro ao conectar em: " + url)

func _on_raw(text: String) -> void:
	var msg = JSON.parse_string(text)
	if not msg is Dictionary or not msg.has("type"):
		return
	_on_message(msg)

func _send(data: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(data))

# ── Handlers de mensagens do servidor ─────────────────────────────────────────

func _on_message(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"assigned":
			_connect_ws_ready()
		"queued":
			_set_status("Aguardando oponente... (posição #%d na fila)" % msg.get("position", 1))
			_code_display.visible = false
		"lobby_created":
			_match_code = msg.get("code", "")
			_set_status("Aguardando oponente entrar no lobby.")
			_code_display.text = _match_code
			_code_display.visible = true
		"match_start":
			_match_code = msg.get("code", "")
			var opp: String = msg.get("opponentName", "Oponente")
			var num: int = msg.get("playerNumber", 1)
			_on_match_start(opp, num)
		"opponent_checkpoint":
			_opp_label.text = _opp_label.text.split("\n")[0] + \
				"\nCheckpoint %d ✓" % msg.get("checkpointIndex", 0)
		"opponent_lap":
			var lap: int = msg.get("lap", 0)
			var t: float = msg.get("elapsedMs", 0) / 1000.0
			_opp_label.text = _opp_label.text.split("\n")[0] + \
				"\nVolta %d  (%.1fs)" % [lap, t]
		"opponent_finished":
			var t: float = msg.get("totalMs", 0) / 1000.0
			_opp_label.text = _opp_label.text.split("\n")[0] + \
				"\nTerminou! %.2fs" % t
		"opponent_disconnected":
			_opp_label.text = _opp_label.text.split("\n")[0] + "\nDesconectou."
		"match_end":
			_on_match_end(msg)
		"error":
			_set_status("Erro: " + msg.get("message", ""))

func _connect_ws_ready() -> void:
	pass  # assigned apenas confirma a conexão — não há ação adicional

# ── Lógica de partida ─────────────────────────────────────────────────────────

func _on_match_start(opp_name: String, player_num: int) -> void:
	_race_active = true
	_lobby_root.visible = false
	_hud_root.visible = true
	_opp_label.text = opp_name
	_set_horse_frozen(false)
	emit_signal("match_started", opp_name, player_num)
	print("[Net] Partida iniciada vs %s (você é P%d) — Código: %s" % [opp_name, player_num, _match_code])

func _on_match_end(msg: Dictionary) -> void:
	_race_active = false
	var winner: String = msg.get("winnerName", "?")
	var my_ms: float = msg.get("yourTime", 0.0)
	var opp_ms: float = msg.get("opponentTime", 0.0)
	_hud_root.visible = false
	_result_root.visible = true
	var you_str := "%.2fs" % (my_ms / 1000.0) if my_ms > 0 else "—"
	var opp_str := "%.2fs" % (opp_ms / 1000.0) if opp_ms > 0 else "—"
	_result_label.text = "Vencedor: %s\n\nSeu tempo: %s\nOponente: %s" % [winner, you_str, opp_str]
	emit_signal("match_ended", winner, my_ms, opp_ms)

# ── Envio de eventos de corrida → servidor ────────────────────────────────────

func _connect_race_manager() -> void:
	var rm := get_node_or_null(race_manager_path)
	if not rm:
		push_warning("[Net] race_manager_path não configurado.")
		return
	rm.checkpoint_passed.connect(_on_local_checkpoint)
	rm.lap_completed.connect(_on_local_lap)
	rm.race_finished.connect(_on_local_finish)

func _on_local_checkpoint(index: int) -> void:
	if not _race_active:
		return
	_send({ "type": "checkpoint_passed", "checkpointIndex": index })

func _on_local_lap(lap: int, _total: int) -> void:
	if not _race_active:
		return
	var elapsed := (Time.get_ticks_msec() - _race_start_ms)
	_send({ "type": "lap_completed", "lap": lap, "elapsedMs": elapsed })

func _on_local_finish(final_time: float) -> void:
	if not _race_active:
		return
	_race_active = false
	var total_ms := int(final_time * 1000.0)
	_send({ "type": "race_finished", "totalMs": total_ms })

# ── Controle do cavalo ────────────────────────────────────────────────────────

func _set_horse_frozen(frozen: bool) -> void:
	var horse := get_node_or_null(horse_path)
	if not horse:
		return
	# Desativa/ativa o processo do behavior tree para bloquear movimento
	horse.set_process(not frozen)
	horse.set_physics_process(not frozen)

# ── Ações dos botões ──────────────────────────────────────────────────────────

func _on_quick_match() -> void:
	_player_name = _name_input.text.strip_edges()
	if _player_name.is_empty():
		_set_status("Digite seu nome.")
		return
	if not _connected:
		_set_status("Conectando ao servidor...")
		_connect_ws()
		await get_tree().create_timer(1.5).timeout
	_send({ "type": "quick_join", "name": _player_name })
	_set_status("Entrando na fila...")
	_enable_buttons(false)

func _on_create_lobby() -> void:
	_player_name = _name_input.text.strip_edges()
	if _player_name.is_empty():
		_set_status("Digite seu nome.")
		return
	if not _connected:
		_connect_ws()
		await get_tree().create_timer(1.5).timeout
	_send({ "type": "create_lobby", "name": _player_name })
	_enable_buttons(false)

func _on_join_lobby() -> void:
	_player_name = _name_input.text.strip_edges()
	var code := _code_input.text.strip_edges().to_upper()
	if _player_name.is_empty() or code.is_empty():
		_set_status("Preencha nome e código.")
		return
	if not _connected:
		_connect_ws()
		await get_tree().create_timer(1.5).timeout
	_send({ "type": "join_lobby", "name": _player_name, "code": code })
	_enable_buttons(false)

# ── Construção da UI ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)

	_build_lobby_panel()
	_build_hud()
	_build_result_screen()

	# Inicia tentativa de conexão ao servidor
	_connect_ws()
	_set_status("Conectando ao servidor em %s..." % server_url)
	_enable_buttons(false)

func _build_lobby_panel() -> void:
	_lobby_root = _panel(Vector2(420, 320), Vector2(0.5, 0.5))
	_canvas.add_child(_lobby_root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	_lobby_root.add_child(vbox)

	var title := Label.new()
	title.text = "Corrida Multiplayer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Seu nome..."
	_name_input.custom_minimum_size.y = 36
	vbox.add_child(_name_input)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	_btn_quick = _button("Quick Match", _on_quick_match)
	_btn_create = _button("Criar Lobby", _on_create_lobby)
	hbox.add_child(_btn_quick)
	hbox.add_child(_btn_create)

	var hbox2 := HBoxContainer.new()
	hbox2.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox2)

	_code_input = LineEdit.new()
	_code_input.placeholder_text = "Código do lobby..."
	_code_input.custom_minimum_size = Vector2(130, 36)
	hbox2.add_child(_code_input)

	_btn_join = _button("Entrar", _on_join_lobby)
	hbox2.add_child(_btn_join)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	_code_display = Label.new()
	_code_display.text = ""
	_code_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_display.add_theme_font_size_override("font_size", 40)
	_code_display.visible = false
	vbox.add_child(_code_display)

func _build_hud() -> void:
	_hud_root = Control.new()
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.visible = false
	_canvas.add_child(_hud_root)

	var panel := _panel(Vector2(200, 70), Vector2(1.0, 0.0))
	panel.set_anchor(SIDE_RIGHT, 1.0)
	panel.set_anchor(SIDE_LEFT, 1.0)
	panel.set_offset(SIDE_LEFT, -210)
	panel.set_offset(SIDE_RIGHT, -10)
	panel.set_offset(SIDE_TOP, 10)
	panel.set_offset(SIDE_BOTTOM, 90)
	_hud_root.add_child(panel)

	_opp_label = Label.new()
	_opp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_opp_label.text = "Oponente"
	_opp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_opp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_opp_label)

func _build_result_screen() -> void:
	_result_root = _panel(Vector2(360, 220), Vector2(0.5, 0.5))
	_result_root.visible = false
	_canvas.add_child(_result_root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	_result_root.add_child(vbox)

	var title := Label.new()
	title.text = "Resultado"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_result_label)

	var btn_replay := _button("Jogar Novamente", func():
		_result_root.visible = false
		_lobby_root.visible = true
		_enable_buttons(true)
		_set_status("Conectado. Escolha um modo.")
		_set_horse_frozen(true)
	)
	btn_replay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn_replay)

# ── Helpers de UI ─────────────────────────────────────────────────────────────

func _panel(size: Vector2, anchor: Vector2) -> Panel:
	var p := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.92)
	style.corner_radius_top_left    = 8
	style.corner_radius_top_right   = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left   = 16
	style.content_margin_right  = 16
	style.content_margin_top    = 16
	style.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", style)
	p.custom_minimum_size = size
	p.set_anchor(SIDE_LEFT,   anchor.x)
	p.set_anchor(SIDE_RIGHT,  anchor.x)
	p.set_anchor(SIDE_TOP,    anchor.y)
	p.set_anchor(SIDE_BOTTOM, anchor.y)
	p.set_offset(SIDE_LEFT,   -size.x * anchor.x)
	p.set_offset(SIDE_RIGHT,  size.x * (1.0 - anchor.x))
	p.set_offset(SIDE_TOP,    -size.y * anchor.y)
	p.set_offset(SIDE_BOTTOM, size.y * (1.0 - anchor.y))
	return p

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b

func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg

func _enable_buttons(enabled: bool) -> void:
	if _btn_quick:  _btn_quick.disabled  = not enabled
	if _btn_create: _btn_create.disabled = not enabled
	if _btn_join:   _btn_join.disabled   = not enabled
