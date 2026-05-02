extends CharacterBody3D

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

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	# Fallback: se a referência export não foi conectada no editor, busca a AnimationTree
	# por nome dentro da subárvore. Garante que ela esteja ativa também.
	if animation_tree == null:
		animation_tree = find_child("AnimationTree", true, false) as AnimationTree
	if animation_tree:
		animation_tree.active = true


# ─────────────────────────────────────────────────────────────────────────────
# API pública
# ─────────────────────────────────────────────────────────────────────────────

## Retorna a transform global do pivot — usado pelo player ao montar.
func get_pivot_global_transform() -> Transform3D:
	if pivot:
		return pivot.global_transform
	return global_transform


## Define o cavaleiro atual (ou null para desmontar).
func set_rider(new_rider: Node3D) -> void:
	rider = new_rider


# ─────────────────────────────────────────────────────────────────────────────
# Métodos chamados pelo BTPlayer (BTCallMethod)
# ─────────────────────────────────────────────────────────────────────────────

## Aplica gravidade, lê input do cavaleiro (se houver) e move o cavalo.
func tick_movement(delta: float) -> void:
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
