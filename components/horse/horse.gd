extends CharacterBody3D

const ABILITY_SOUND := preload("res://assets/sound/zaowlrd.ogg")

# ── Movimentação ──────────────────────────────────────────────────────────────

@export_group("Movimentacao")
## Velocidade de caminhada do cavalo (m/s).
@export var walk_speed: float = 4.0
## Velocidade de corrida do cavalo (m/s).
@export var run_speed: float = 9.0
## Velocidade de rotação (rad/s) ao apertar A/D.
@export var turn_speed: float = 2.0
## Impulso vertical do pulo.
@export var jump_force: float = 6.0

# ── Animação ──────────────────────────────────────────────────────────────────

@export_group("Animacao")
## AnimationTree do cavalo. Espera os parâmetros:
##   parameters/WalkIdle/blend_amount   (0=Idle, 1=Walk)
##   parameters/AirSelector/blend_amount (0=chão, 1=ar/Fall)
##   parameters/TimeScale/scale         (1.0=walk, run_anim_speed=run)
@export var animation_tree: AnimationTree
## Velocidade base da animação Walk quando o cavalo está caminhando.
@export var walk_anim_speed: float = 1.0
## Velocidade da animação Walk quando o cavalo está correndo.
@export var run_anim_speed: float = 2.0
## Velocidade de interpolação dos blends de animação.
@export var anim_blend_speed: float = 8.0

# ── Habilidade (Time Stop) ───────────────────────────────────────────────────

@export_group("Habilidade")
## Duração da habilidade ability1: pausa o mundo, exceto player + cavalo.
@export var ability_duration: float = 3.0
## Cooldown após a habilidade desativar.
@export var ability_cooldown: float = 5.0
## Material com o shader de screen effect (invert + saturation).
## Se null, é detectado automaticamente buscando por screen_effect.gdshader na cena.
@export var screen_shader_mat: ShaderMaterial
## Velocidade do lerp ao ENTRAR na habilidade (invert→1, saturation→0).
@export var ability_in_speed: float = 4.0
## Velocidade do lerp ao SAIR da habilidade (invert→0, saturation→1).
@export var ability_out_speed: float = 2.0

# ── Pivot ─────────────────────────────────────────────────────────────────────

@export_group("Pivot")
## Marker3D onde o player se posiciona quando montado.
@export var pivot: Marker3D

# ── Estado ────────────────────────────────────────────────────────────────────

## Player atualmente montado (null se ninguém estiver montando).
var rider: Node3D = null
## True quando o cavalo está se locomovendo (W pressionado).
var is_moving := false
## True quando o cavalo está correndo (W + Shift).
var is_running := false

## True quando a habilidade ability1 está ativa (mundo pausado).
var _ability_active := false
## Wall-time (segundos) em que a habilidade ativa expira.
var _ability_active_until: float = 0.0
## Wall-time (segundos) em que o cooldown da habilidade termina.
var _ability_cooldown_until: float = 0.0
## Pares [ShaderMaterial, valor_original] de shake_rate salvos durante a habilidade.
var _saved_shake_rates: Array = []
## Blend atual da habilidade (0=normal, 1=ativa). Lerpado no _process.
var _ability_blend: float = 0.0
## AudioStreamPlayer criado no _ready pra tocar o som da habilidade.
var _ability_sfx: AudioStreamPlayer

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	# Fallback: se a referência export não foi conectada no editor, busca a AnimationTree
	# por nome dentro da subárvore. Garante que ela esteja ativa também.
	if animation_tree == null:
		animation_tree = find_child("AnimationTree", true, false) as AnimationTree
	if animation_tree:
		animation_tree.active = true
	# Localiza o ShaderMaterial de screen effect depois que a cena carregar inteira.
	call_deferred("_locate_screen_shader_mat")
	# Cria o AudioStreamPlayer pra habilidade. PROCESS_MODE_ALWAYS garante que
	# continue tocando mesmo com a árvore pausada durante a habilidade.
	_ability_sfx = AudioStreamPlayer.new()
	_ability_sfx.stream = ABILITY_SOUND
	_ability_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ability_sfx)


func _process(delta: float) -> void:
	# Lerpa _ability_blend rumo ao alvo (1 ativo, 0 inativo) e aplica nos shaders.
	var target := 1.0 if _ability_active else 0.0
	if _ability_blend == target and target == 0.0:
		return  # já normalizado, nada a fazer
	var spd := ability_in_speed if _ability_active else ability_out_speed
	_ability_blend = lerpf(_ability_blend, target, clampf(delta * spd, 0.0, 1.0))
	if absf(_ability_blend - target) < 0.001:
		_ability_blend = target  # snap ao alvo quando muito perto
	if screen_shader_mat:
		screen_shader_mat.set_shader_parameter("invert", _ability_blend)
		screen_shader_mat.set_shader_parameter("saturation", 1.0 - _ability_blend)


## Procura na árvore um ShaderMaterial cujo Shader é o screen_effect.gdshader.
func _locate_screen_shader_mat() -> void:
	if screen_shader_mat:
		return
	screen_shader_mat = _find_screen_shader_mat(get_tree().get_root())


func _find_screen_shader_mat(node: Node) -> ShaderMaterial:
	if node is CanvasItem:
		var ci := node as CanvasItem
		var mat = ci.material
		if mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			if sm.shader and sm.shader.resource_path.ends_with("screen_effect.gdshader"):
				return sm
	for child in node.get_children():
		var found := _find_screen_shader_mat(child)
		if found:
			return found
	return null


# ─────────────────────────────────────────────────────────────────────────────
# API pública
# ─────────────────────────────────────────────────────────────────────────────

## Retorna a transform global do pivot — usado pelo player ao montar.
func get_pivot_global_transform() -> Transform3D:
	if pivot:
		return pivot.global_transform
	return global_transform


## Define o cavaleiro atual (ou null para desmontar).
## Se a habilidade estiver ativa e o player desmontar, ela é desativada e o
## cooldown começa imediatamente.
func set_rider(new_rider: Node3D) -> void:
	if _ability_active and rider != null and new_rider == null:
		_deactivate_ability()
	rider = new_rider


# ─────────────────────────────────────────────────────────────────────────────
# Habilidade ability1: Time Stop
# ─────────────────────────────────────────────────────────────────────────────

## Tenta ativar a habilidade. Falha se: já ativa, em cooldown, ou sem cavaleiro.
func _try_activate_ability() -> void:
	if _ability_active:
		return
	if rider == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _ability_cooldown_until:
		return

	_ability_active = true
	_ability_active_until = now + ability_duration

	# Pausa o SceneTree (todos os nós com PROCESS_MODE_INHERIT/PAUSABLE param).
	# O cavalo + rider passam a PROCESS_MODE_ALWAYS pra continuar processando.
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	if rider:
		rider.process_mode = Node.PROCESS_MODE_ALWAYS

	# Zera o shake_rate de qualquer ShaderMaterial na cena (efeito glitch para).
	_saved_shake_rates.clear()
	_collect_and_zero_shake_rate(get_tree().get_root())

	# Garante que o material de screen effect está localizado.
	_locate_screen_shader_mat()

	# Toca o sound effect da habilidade.
	if _ability_sfx:
		_ability_sfx.play()


## Desativa a habilidade e inicia o cooldown.
func _deactivate_ability() -> void:
	if not _ability_active:
		return
	_ability_active = false
	_ability_cooldown_until = Time.get_ticks_msec() / 1000.0 + ability_cooldown

	# Despausa e devolve modos de processamento ao default (inheritado).
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_INHERIT
	if rider:
		rider.process_mode = Node.PROCESS_MODE_INHERIT

	# Restaura os shake_rate salvos.
	for entry in _saved_shake_rates:
		var sm: ShaderMaterial = entry[0]
		if is_instance_valid(sm):
			sm.set_shader_parameter("shake_rate", entry[1])
	_saved_shake_rates.clear()


## Percorre a árvore a partir de `node` e, para cada ShaderMaterial encontrado
## que tenha shake_rate definido, salva o valor original em _saved_shake_rates
## e zera. Cobre material_override, material_overlay e surface_override de
## MeshInstance3D, além de material em mesh quando tiver.
func _collect_and_zero_shake_rate(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		_try_zero_shader_mat(mi.material_override)
		_try_zero_shader_mat(mi.material_overlay)
		for i in range(mi.get_surface_override_material_count()):
			_try_zero_shader_mat(mi.get_surface_override_material(i))
	for child in node.get_children():
		_collect_and_zero_shake_rate(child)


## Se `mat` é ShaderMaterial e tem shake_rate setado, salva e zera.
func _try_zero_shader_mat(mat) -> void:
	if mat == null or not (mat is ShaderMaterial):
		return
	var sm := mat as ShaderMaterial
	var current = sm.get_shader_parameter("shake_rate")
	if current == null:
		return
	_saved_shake_rates.append([sm, current])
	sm.set_shader_parameter("shake_rate", 0.0)


# ─────────────────────────────────────────────────────────────────────────────
# Métodos chamados pelo BTPlayer (BTCallMethod)
# ─────────────────────────────────────────────────────────────────────────────

## Aplica gravidade, lê input do cavaleiro (se houver) e move o cavalo.
## Também processa habilidade ability1: ativa/desativa e checa expiração por tempo real.
func tick_movement(delta: float) -> void:
	# Habilidade Time Stop: usa wall-time pra contar mesmo com a árvore pausada.
	var now := Time.get_ticks_msec() / 1000.0
	if _ability_active and now >= _ability_active_until:
		_deactivate_ability()
	if rider != null and Input.is_action_just_pressed("ability1"):
		_try_activate_ability()

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if rider != null:
		_handle_mounted_input(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		is_moving = false
		is_running = false

	move_and_slide()


## Atualiza os blends da AnimationTree com base no estado atual.
func tick_animation(delta: float) -> void:
	if animation_tree == null:
		return

	var spd := delta * anim_blend_speed
	var on_floor := is_on_floor()

	var target_walkidle := 1.0 if is_moving else 0.0
	var cur_walkidle := animation_tree.get("parameters/WalkIdle/blend_amount") as float
	animation_tree.set("parameters/WalkIdle/blend_amount", lerpf(cur_walkidle, target_walkidle, spd))

	var target_air := 0.0 if on_floor else 1.0
	var cur_air := animation_tree.get("parameters/AirSelector/blend_amount") as float
	animation_tree.set("parameters/AirSelector/blend_amount", lerpf(cur_air, target_air, spd))

	var target_scale := run_anim_speed if is_running else walk_anim_speed
	var cur_scale := animation_tree.get("parameters/TimeScale/scale") as float
	animation_tree.set("parameters/TimeScale/scale", lerpf(cur_scale, target_scale, spd))


# ─────────────────────────────────────────────────────────────────────────────
# Movimento controlado pelo cavaleiro
# ─────────────────────────────────────────────────────────────────────────────

func _handle_mounted_input(delta: float) -> void:
	# Rotação por A/D — sinais alinhados ao Pivot para que A vire à esquerda do rider.
	var turn := 0.0
	if Input.is_action_pressed("move_left"):
		turn += 1.0
	if Input.is_action_pressed("move_right"):
		turn -= 1.0
	if turn != 0.0:
		rotate_y(turn * turn_speed * delta)

	# Avanço por W (S não faz nada).
	# O modelo do cavalo aponta a cabeça no +Z, então a direção de movimento é +basis.z.
	var forward_input := Input.is_action_pressed("move_forward")
	is_moving = forward_input
	is_running = forward_input and Input.is_action_pressed("run")

	if forward_input:
		var speed := run_speed if is_running else walk_speed
		var forward_dir := global_transform.basis.z
		velocity.x = forward_dir.x * speed
		velocity.z = forward_dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# Pulo por Espaço
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force
