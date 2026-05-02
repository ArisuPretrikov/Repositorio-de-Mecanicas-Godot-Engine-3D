extends CharacterBody3D

# ── Movimentação ──────────────────────────────────────────────────────────────

@export_group("Movimentacao")
## Velocidade de caminhada normal.
@export var speed: float = 5.0
## Velocidade máxima ao correr.
@export var run_speed: float = 9.0
## Velocidade ao agachar.
@export var crouch_speed: float = 2.0
## Velocidade de caminhada montado.
@export var mount_speed: float = 6.0
## Velocidade máxima ao correr montado.
@export var mount_run_speed: float = 12.0
## Impulso vertical aplicado ao pular.
@export var jump_force: float = 5.0
## Multiplicador de velocidade ao andar para os lados (0–1).
@export var side_speed_multiplier: float = 0.8
## Multiplicador de velocidade ao andar para trás (0–1).
@export var back_speed_multiplier: float = 0.6

@export var StepsParticles : GPUParticles3D

@export var JumpParticles : GPUParticles3D

var in_floor_now = true

# ── Pose ──────────────────────────────────────────────────────────────────────

@export_group("Pose")
## Pose atual do personagem: "normal", "crouch", "climb" ou "mount".
@export var pose: String = "normal"

# ── Montaria ─────────────────────────────────────────────────────────────────

@export_group("Montaria")
## Indica se o personagem está montado.
@export var mounted: bool = false
## RayCast3D apontado para frente que detecta cavalos (layer Cavalo).
@export var ray_interact: RayCast3D
## Cavalo atualmente sendo montado (null quando não está em modo montaria).
var mounted_horse: Node3D = null

# ── Escalar ───────────────────────────────────────────────────────────────────

@export_group("Escalar")
## Indica se o personagem está em modo escalagem.
@export var climb: bool = false
## RayCast3D apontado para frente que detecta paredes escaláveis.
@export var ray_climb: RayCast3D
## Impulso vertical aplicado ao ATIVAR o climb (ajuda o player a "agarrar" o início da parede).
@export var climb_start_jump: float = 3.0

# ── Agachar ───────────────────────────────────────────────────────────────────

@export_group("Agachar")
## Indica se o personagem está agachado.
@export var crouch: bool = false

# ── Stamina ───────────────────────────────────────────────────────────────────

@export_group("Stamina")
## Stamina máxima.
@export var max_stamina: float = 100.0
## Taxa de regeneração padrão (unidades/segundo).
@export var stamina_regen: float = 10.0
## Taxa de regeneração ao agachar (unidades/segundo); deve ser maior que stamina_regen.
@export var stamina_regen_crouch: float = 25.0
## Custo de stamina por segundo ao correr.
@export var stamina_cost_run: float = 20.0
## Custo de stamina por segundo ao escalar em movimento.
@export var stamina_cost_climb: float = 15.0
## Custo de stamina por pulo.
@export var stamina_cost_jump: float = 15.0
## Fração (0–1) da stamina máxima necessária para sair do modo exaustão.
@export var exhaustion_threshold: float = 0.5

# ── Câmera ────────────────────────────────────────────────────────────────────

@export_group("Camera")
## Câmera em primeira pessoa.
@export var camera1p : Camera3D
## Câmera em terceira pessoa (filha de camera1p).
@export var camera3p : Camera3D
## Limite de rotação vertical da câmera em graus.
@export var head_vertical_limit: float = 60
## Nó pivot da cabeça; recebe rotação horizontal e vertical do mouse.
@export var head_pivot: Node3D
## Sensibilidade do mouse em rad/pixel.
@export var mouse_sensitivity: float = 0.003
## Ângulo (°) a partir do qual o body começa a seguir a cabeça horizontalmente.
@export var body_soft_limit: float = 45.0
## Ângulo máximo (°) permitido entre body e cabeça.
@export var body_hard_limit: float = 90.0

# ── Animação ──────────────────────────────────────────────────────────────────

@export_group("Animacao")
## AnimationTree do modelo do personagem.
@export var animation_tree : AnimationTree
## Nó raiz do modelo 3D; sua rotação Y representa a direção do corpo.
@onready var body_pivot := $Body
## ProgressBar 2D que exibe a stamina atual na tela.
@onready var stamina_bar: ProgressBar = $StaminaUI/StaminaBar
## Velocidade de interpolação da rotação do body_pivot.
@export var body_follow_speed: float = 8.0

# ── Debug ─────────────────────────────────────────────────────────────────────

@export_group("Variaveis Internas")
## Label na tela para exibir informações de debug.
@export var debug := Label

# ── Variáveis de estado ───────────────────────────────────────────────────────

## Direção de movimento calculada no frame atual (normalizada).
var direction: Vector3
## Força da gravidade lida das configurações do projeto.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Normal da última parede detectada durante a escalagem.
var _climb_wall_normal := Vector3.ZERO
## Valor atual de stamina.
var stamina: float
## True enquanto o personagem está correndo.
var is_running := false
## True enquanto há input direcional ativo.
var in_moving := false
## True enquanto o personagem está em modo de exaustão (stamina zerada).
var is_exhausted := false
## True no frame em que o personagem pulou; consumido por state_update_animation para disparar o OneShot.
var _just_jumped := false
## True no frame em que o personagem deve disparar a animação de Hurt.
var _just_hurt := false
## Direção de movimento WASD restrita a um único eixo (sem diagonais).
var _move_dir := Vector2.ZERO
## Backup do collision_layer original — restaurado ao desmontar.
var _saved_collision_layer: int = 0
## Backup do collision_mask original — restaurado ao desmontar.
var _saved_collision_mask: int = 0
## Backups das rotações pré-montaria — restauradas ao desmontar para evitar snap visual.
var _saved_rotation: Vector3 = Vector3.ZERO
var _saved_body_rot_y: float = 0.0
var _saved_head_rot: Vector3 = Vector3.ZERO


# ─────────────────────────────────────────────────────────────────────────────
# Ciclo de vida
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stamina = max_stamina


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Rotação horizontal no eixo Y global (olhar para os lados)
		head_pivot.global_rotate(Vector3.UP, -event.relative.x * mouse_sensitivity)
		# Rotação vertical no eixo X local (olhar para cima e baixo)
		head_pivot.rotate_object_local(Vector3.RIGHT, event.relative.y * mouse_sensitivity)
		# Limita inclinação vertical
		head_pivot.rotation.x = clamp(head_pivot.rotation.x, deg_to_rad(-head_vertical_limit), deg_to_rad(head_vertical_limit))
		# Garante que não haja inclinação lateral
		head_pivot.rotation.z = 0

	if event.is_action_pressed("ui_cancel") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("ui_cancel") and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("camera_change") and camera1p.current:
		camera1p.current = false
		camera3p.current = true
	elif event.is_action_pressed("camera_change") and not camera1p.current:
		camera1p.current = true
		camera3p.current = false

	if event.is_action_pressed("interact"):
		if mounted:
			mount_off()
		elif ray_interact and ray_interact.is_colliding():
			var target := _find_mountable(ray_interact.get_collider())
			if target:
				mount_on(target)


# ─────────────────────────────────────────────────────────────────────────────
# Utilitários internos (prefixo _ = não chamar diretamente do BT)
# ─────────────────────────────────────────────────────────────────────────────

## Arredonda um ângulo em radianos para o múltiplo de 90° mais próximo.
func _snap_to_nearest_90(angle: float) -> float:
	return deg_to_rad(round(rad_to_deg(angle) / 90.0) * 90.0)


## Sobe pela árvore a partir do collider procurando o primeiro nó com método set_rider.
## Permite que o raycast acerte o Area3D do cavalo e ainda assim acerte o CharacterBody3D pai.
func _find_mountable(node: Node) -> Node3D:
	var cur := node
	while cur != null:
		if cur is Node3D and cur.has_method("set_rider"):
			return cur
		cur = cur.get_parent()
	return null


## Retorna o input WASD restrito a UM eixo (sem diagonais).
## Regra: o botão pressionado mais recentemente vence; ao soltar,
## faz fallback para qualquer outro botão ainda segurado.
func _get_move_dir() -> Vector2:
	if Input.is_action_just_pressed("move_left"):
		_move_dir = Vector2(-1.0, 0.0)
	elif Input.is_action_just_pressed("move_right"):
		_move_dir = Vector2(1.0, 0.0)
	elif Input.is_action_just_pressed("move_forward"):
		_move_dir = Vector2(0.0, -1.0)
	elif Input.is_action_just_pressed("move_back"):
		_move_dir = Vector2(0.0, 1.0)

	var still_held := false
	if _move_dir.x < 0.0:
		still_held = Input.is_action_pressed("move_left")
	elif _move_dir.x > 0.0:
		still_held = Input.is_action_pressed("move_right")
	elif _move_dir.y < 0.0:
		still_held = Input.is_action_pressed("move_forward")
	elif _move_dir.y > 0.0:
		still_held = Input.is_action_pressed("move_back")

	if not still_held:
		if Input.is_action_pressed("move_left"):
			_move_dir = Vector2(-1.0, 0.0)
		elif Input.is_action_pressed("move_right"):
			_move_dir = Vector2(1.0, 0.0)
		elif Input.is_action_pressed("move_forward"):
			_move_dir = Vector2(0.0, -1.0)
		elif Input.is_action_pressed("move_back"):
			_move_dir = Vector2(0.0, 1.0)
		else:
			_move_dir = Vector2.ZERO

	return _move_dir


## Altera apenas o componente Y da rotação local de um nó sem afetar X e Z.
func _set_rotation_y(node: Node3D, y: float) -> void:
	node.rotation = Vector3(node.rotation.x, y, node.rotation.z)


## Retorna a velocidade de movimento correta segundo a prioridade: montaria > agachar > correr > andar.
func _calculate_move_speed() -> float:
	if mounted:
		return mount_run_speed if is_running else mount_speed
	if crouch:
		return crouch_speed
	if is_running:
		return run_speed
	return speed


## Retorna o multiplicador direcional para andar/agachar: frente=1.0, lado=side_speed_multiplier, trás=back_speed_multiplier.
func _directional_multiplier(input_dir: Vector2) -> float:
	if input_dir == Vector2.ZERO:
		return 1.0
	var nd   := input_dir.normalized()
	var fwd  := maxf(-nd.y, 0.0)
	var back := maxf( nd.y, 0.0)
	var side := absf(nd.x)
	var total := fwd + back + side
	return (fwd * 1.0 + back * back_speed_multiplier + side * side_speed_multiplier) / total


## Retorna o multiplicador direcional para escalagem: cima/baixo=1.0, lado=side_speed_multiplier.
func _climb_directional_multiplier(input_dir: Vector2) -> float:
	if input_dir == Vector2.ZERO:
		return 1.0
	var nd   := input_dir.normalized()
	var vert := absf(nd.y)
	var side := absf(nd.x)
	var total := vert + side
	if total <= 0.0:
		return 1.0
	return (vert * 1.0 + side * side_speed_multiplier) / total


# ─────────────────────────────────────────────────────────────────────────────
# API pública
# ─────────────────────────────────────────────────────────────────────────────

## Aplica dano e dispara a animação de Hurt.
## O parâmetro `amount` está reservado para integração futura com sistema de vida.
func take_damage(amount: float) -> void:
	_just_hurt = true


## Entra no modo montaria sobre `horse`.
## Desliga colisões e gravidade do player; o player passa a ser snapeado no Pivot do cavalo.
## Cancela climb e crouch automaticamente.
func mount_on(horse: Node3D) -> void:
	if horse == null or mounted:
		return
	mounted = true
	mounted_horse = horse
	if climb:
		climb = false
		_climb_wall_normal = Vector3.ZERO
	crouch = false

	# Salva e desativa collision (player vira "ghost", quem colide é o cavalo)
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO

	# Salva rotações pré-montaria pra restaurar quando desmontar (sem snap visual)
	_saved_rotation = rotation
	if body_pivot:
		_saved_body_rot_y = body_pivot.rotation.y
	if head_pivot:
		_saved_head_rot = head_pivot.rotation

	if horse.has_method("set_rider"):
		horse.set_rider(self)


## Sai do modo montaria — restaura colisões/rotações e larga o player ao lado do cavalo.
func mount_off() -> void:
	if mounted_horse and mounted_horse.has_method("set_rider"):
		mounted_horse.set_rider(null)
	mounted = false

	# Restaura colisão
	collision_layer = _saved_collision_layer
	collision_mask = _saved_collision_mask

	# Ejeta o player verticalmente a partir do pivot, evitando ficar preso em paredes laterais.
	# Posiciona acima da hitbox do cavalo (capsule_radius + folga) e dá um pequeno impulso pra cima.
	if mounted_horse:
		var pivot_pos: Vector3
		if mounted_horse.has_method("get_pivot_global_transform"):
			pivot_pos = mounted_horse.get_pivot_global_transform().origin
		else:
			pivot_pos = mounted_horse.global_position
		global_position = pivot_pos + Vector3.DOWN * 1.5
		velocity = Vector3.DOWN * 3.0
	else:
		velocity = Vector3.ZERO
	mounted_horse = null

	# Restaura as rotações pré-montaria (player volta a olhar pra onde estava antes)
	rotation = _saved_rotation
	if body_pivot:
		body_pivot.rotation.y = _saved_body_rot_y
	if head_pivot:
		head_pivot.rotation = _saved_head_rot


# ─────────────────────────────────────────────────────────────────────────────
# Movimento — chamar a partir do Selector de movimento no BT
# ─────────────────────────────────────────────────────────────────────────────

## Aplica gravidade, pulo e movimento WASD no chão.
## Deve ser chamado pelo BT quando climb == false.
## Quando montado: ignora física, snapa posição/rotação no Pivot do cavalo,
## e atualiza is_running com base no input para alimentar a animação de mount.
func movement_walk(delta: float) -> void:
	if mounted and mounted_horse:
		var pivot_xform: Transform3D = mounted_horse.get_pivot_global_transform() if mounted_horse.has_method("get_pivot_global_transform") else mounted_horse.global_transform
		# Snapa apenas posição e yaw (mantém X/Z em zero pra player ficar de pé)
		global_position = pivot_xform.origin
		var pivot_yaw := pivot_xform.basis.get_euler().y
		rotation = Vector3(0.0, pivot_yaw, 0.0)
		velocity = Vector3.ZERO
		# is_running para a animação de Mount_Run (player se inclina/corre junto)
		is_running = Input.is_action_pressed("move_forward") and Input.is_action_pressed("run")
		return

	if _just_jumped and is_on_floor():
		JumpParticles.emitting = true
		_just_jumped = false
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") and not ray_climb.is_colliding() and not is_exhausted and not crouch:
		velocity.y = jump_force
		stamina = maxf(stamina - stamina_cost_jump, 0.0)
		_just_jumped = true



	var input_dir := _get_move_dir()
	is_running = Input.is_action_pressed("run") and not crouch and not is_exhausted and stamina > 0 and input_dir.y < 0
	var move_speed := _calculate_move_speed() * _directional_multiplier(input_dir)

	direction = (head_pivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = -direction.x * move_speed
		velocity.z = -direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	move_and_slide()


## Aplica movimento lateral e vertical na superfície da parede (W=cima, S=baixo, A/D=lados).
## Deve ser chamado pelo BT quando climb == true.
func movement_climb() -> void:
	is_running = false
	velocity.y = 0.0

	var wall_normal: Vector3
	if is_on_wall():
		wall_normal = get_wall_normal()
		_climb_wall_normal = wall_normal
	elif _climb_wall_normal != Vector3.ZERO:
		wall_normal = _climb_wall_normal
	else:
		return

	var up_on_wall    := (Vector3.UP - wall_normal * wall_normal.dot(Vector3.UP)).normalized()
	var right_on_wall := wall_normal.cross(up_on_wall).normalized()
	var move_speed    := _calculate_move_speed()

	var input_dir := _get_move_dir()
	direction = (right_on_wall * -input_dir.x + up_on_wall * -input_dir.y).normalized()

	if direction:
		var effective_speed := move_speed * _climb_directional_multiplier(input_dir)
		velocity.x = direction.x * effective_speed
		velocity.y = direction.y * effective_speed
		velocity.z = direction.z * effective_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.y = move_toward(velocity.y, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	# Mantém contato com a parede — sem isso o movimento lateral perde is_on_wall()
	velocity -= wall_normal * gravity * 0.4

	move_and_slide()


# ─────────────────────────────────────────────────────────────────────────────
# Atualização de estado — chamar a partir das sequências de estado no BT
# ─────────────────────────────────────────────────────────────────────────────

## Atualiza in_moving: true se há input direcional no frame atual.
## Quando montado: in_moving reflete só W (cavalo só se locomove pra frente; A/D apenas rotacionam).
func state_update_moving() -> void:
	if mounted:
		in_moving = Input.is_action_pressed("move_forward")
		StepsParticles.emitting = false
		return
	in_moving = _get_move_dir() != Vector2.ZERO
	if pose == "normal" and is_on_floor():
		StepsParticles.emitting = in_moving
	else:
		StepsParticles.emitting = false

## Ativa/desativa agachamento e cancela escalagem ao agachar.
## Quando montado, ignora crouch.
func state_update_crouch() -> void:
	if mounted:
		crouch = false
		return
	if Input.is_action_pressed("crouch"):
		if not climb:
			crouch = true
		climb = false
	else:
		crouch = false


## Gerencia entrada e saída do modo escalagem via RayCast e botão de pulo.
## Pulo perto de parede = entrar; pulo escalando = sair; sem parede = auto-sair.
## Não permite entrar no climb se estiver exausto ou montado.
func state_update_climb_toggle() -> void:
	if mounted:
		if climb:
			climb = false
			_climb_wall_normal = Vector3.ZERO
		return

	if Input.is_action_just_pressed("jump"):
		if climb:
			climb = false
			_climb_wall_normal = Vector3.ZERO
		elif ray_climb.is_colliding() and not is_exhausted:
			climb = true
			# Pequeno impulso pra cima ao agarrar a parede
			velocity.y = climb_start_jump
		return

	if climb and not ray_climb.is_colliding() and not is_on_wall():
		climb = false
		_climb_wall_normal = Vector3.ZERO


## Gerencia o modo de exaustão.
## Entra quando stamina chega a 0 (cancela escalagem imediatamente).
## Sai quando stamina >= exhaustion_threshold * max_stamina.
func state_update_exhaustion() -> void:
	if not is_exhausted and stamina <= 0.0:
		is_exhausted = true
		if climb:
			climb = false
			_climb_wall_normal = Vector3.ZERO
	elif is_exhausted and stamina >= max_stamina * exhaustion_threshold:
		is_exhausted = false


## Drena ou regenera stamina com base no estado atual e atualiza a barra 2D.
## Regras de stamina:
##   Correndo + em movimento   → drena stamina_cost_run/s
##   Escalando + em movimento  → drena stamina_cost_climb/s
##   Escalando + parado        → neutro (sem dreno nem regen)
##   Agachado                  → regen stamina_regen_crouch/s
##   Padrão                    → regen stamina_regen/s
func state_update_stamina(delta: float) -> void:
	var draining := false

	if is_running and in_moving:
		stamina -= stamina_cost_run * delta
		draining = true

	if climb and in_moving:
		stamina -= stamina_cost_climb * delta
		draining = true

	# Escalando parado: estado neutro — não drena, não recupera
	var climb_idle := climb and not in_moving
	if not draining and not climb_idle:
		var regen_rate := stamina_regen_crouch if crouch else stamina_regen
		stamina = minf(stamina + regen_rate * delta, max_stamina)

	stamina = maxf(stamina, 0.0)
	stamina_bar.value = stamina


## Atualiza a string de pose com base no estado atual.
func state_update_pose() -> void:
	if climb:
		pose = "climb"
	elif mounted:
		pose = "mount"
	elif crouch:
		pose = "crouch"
	else:
		pose = "normal"


## Rotaciona body_pivot para seguir head_pivot com deadzone (body_soft_limit) e clamp (body_hard_limit).
## Durante escalagem: trava o corpo perpendicular à parede e limita a câmera a ±45°.
## Durante montaria: trava o corpo alinhado ao Player root (que segue o pivot do cavalo)
## e limita a cabeça a ±body_soft_limit em torno do "frente" do cavalo.
func state_update_body_pivot(delta: float) -> void:
	if body_pivot == null:
		return

	if mounted:
		# body_pivot.rotation.y = 0 → corpo aponta no mesmo yaw do Player root (= pivot do cavalo)
		body_pivot.rotation.y = lerp_angle(wrapf(body_pivot.rotation.y, -PI, PI), 0.0, delta * body_follow_speed)
		var head_diff_mount := wrapf(head_pivot.rotation.y, -PI, PI)
		head_pivot.rotation.y = clamp(head_diff_mount, -deg_to_rad(body_soft_limit), deg_to_rad(body_soft_limit))
		return

	if climb and _climb_wall_normal != Vector3.ZERO:
		var into_wall := -_climb_wall_normal
		into_wall.y = 0.0
		var wall_yaw := atan2(into_wall.x, into_wall.z)
		body_pivot.rotation.y = lerp_angle(wrapf(body_pivot.rotation.y, -PI, PI), wall_yaw, delta * body_follow_speed)
		var head_diff := wrapf(head_pivot.rotation.y - wall_yaw, -PI, PI)
		head_pivot.rotation.y = wall_yaw + clamp(head_diff, -deg_to_rad(45.0), deg_to_rad(45.0))
		return

	var head_yaw := wrapf(head_pivot.rotation.y, -PI, PI)
	var body_yaw := wrapf(body_pivot.rotation.y, -PI, PI)
	var diff     := wrapf(head_yaw - body_yaw, -PI, PI)

	if in_moving:
		body_pivot.rotation.y = lerp_angle(body_yaw, head_yaw, delta * body_follow_speed)
	elif absf(diff) > deg_to_rad(body_soft_limit):
		var target_yaw : float = head_yaw - sign(diff) * deg_to_rad(body_soft_limit)
		body_pivot.rotation.y = lerp_angle(body_yaw, target_yaw, delta * body_follow_speed)

	var final_diff := wrapf(body_pivot.rotation.y - head_yaw, -PI, PI)
	body_pivot.rotation.y = head_yaw + clamp(final_diff, -deg_to_rad(body_hard_limit), deg_to_rad(body_hard_limit))


## Atualiza a AnimationTree com base no estado atual.
## Estrutura da BlendTree:
##   HurtShot          (OneShot): dispara animação Hurt uma vez
##   MountSelector     (Blend2):  0=Walk/Climb branch  1=Mount tree
##   Mount_Idle_Walk   (Blend2):  0=Mount_Idle  1=Mount_Walk_Run
##   Mount_Walk_Run    (Blend2):  0=Mount_Walk  1=Mount_Run
##   Climb_Crouch_Walk (Blend3): -1=Climb  0=Crouch  1=Normal(ShotJump)
##   Walk_Idle         (Blend2):  0=Idle   1=Walk
##   Crouch_Idle       (Blend2):  0=Crouch 1=Crouch_Walk
##   Climb_Idle_All_Fall (Blend3): -1=Climb_Idle  0=Climb_R_Up_L  1=Fall
##   Climb_R_Up_L      (Blend3): -1=Climb_Right  0=Climb_Up  1=Climb_Left
##   ShotJump          (OneShot): dispara animação Jump uma vez
func state_update_animation(delta: float) -> void:
	if animation_tree == null:
		return

	var spd := delta * 8.0
	var input_dir := _get_move_dir()

	# ── TimeScale: anima na velocidade real do player (Walk = 1.0) ───────────
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var time_scale := 1.0
	if in_moving and horizontal_speed > 0.1 and speed > 0.0:
		time_scale = horizontal_speed / speed
	animation_tree.set("parameters/TimeScale/scale", time_scale)

	# ── OneShot: Hurt ────────────────────────────────────────────────────────
	if _just_hurt:
		animation_tree.set("parameters/HurtShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_just_hurt = false

	# ── MountSelector: blend entre walk/climb (0) e mount (1) ────────────────
	var target_mount := 1.0 if mounted else 0.0
	var cur_mount := animation_tree.get("parameters/MountSelector/blend_amount") as float
	animation_tree.set("parameters/MountSelector/blend_amount", lerpf(cur_mount, target_mount, spd))

	# ── Mount: Idle / Walk / Run ─────────────────────────────────────────────
	var target_mount_idle_walk := 1.0 if (mounted and in_moving) else 0.0
	var cur_mount_idle_walk := animation_tree.get("parameters/Mount_Idle_Walk/blend_amount") as float
	animation_tree.set("parameters/Mount_Idle_Walk/blend_amount", lerpf(cur_mount_idle_walk, target_mount_idle_walk, spd))

	var target_mount_walk_run := 1.0 if (mounted and is_running) else 0.0
	var cur_mount_walk_run := animation_tree.get("parameters/Mount_Walk_Run/blend_amount") as float
	animation_tree.set("parameters/Mount_Walk_Run/blend_amount", lerpf(cur_mount_walk_run, target_mount_walk_run, spd))

	# ── Modo principal ────────────────────────────────────────────────────────
	var target_main := -1.0 if climb else (0.0 if crouch else 1.0)
	var cur_main := animation_tree.get("parameters/Climb_Crouch_Walk/blend_amount") as float
	animation_tree.set("parameters/Climb_Crouch_Walk/blend_amount", lerpf(cur_main, target_main, spd))

	# ── Normal: Walk / Idle ───────────────────────────────────────────────────
	var target_walk := 1.0 if (in_moving and not climb and not crouch) else 0.0
	var cur_walk := animation_tree.get("parameters/Walk_Idle/blend_amount") as float
	animation_tree.set("parameters/Walk_Idle/blend_amount", lerpf(cur_walk, target_walk, spd))


	# ── Agachado: Crouch / Crouch_Walk ───────────────────────────────────────
	var target_crouch_walk := 1.0 if (in_moving and crouch) else 0.0
	var cur_crouch_walk := animation_tree.get("parameters/Crouch_Idle/blend_amount") as float
	animation_tree.set("parameters/Crouch_Idle/blend_amount", lerpf(cur_crouch_walk, target_crouch_walk, spd))

	# ── Escalagem: Idle / Direcional / Fall ───────────────────────────────────
	var target_climb_mode := -1.0 if not in_moving else 0.0
	var cur_climb_mode := animation_tree.get("parameters/Climb_Idle_All_Fall/blend_amount") as float
	animation_tree.set("parameters/Climb_Idle_All_Fall/blend_amount", lerpf(cur_climb_mode, target_climb_mode, spd))

	# ── Escalagem direcional: Right / Up / Left ───────────────────────────────
	# -input_dir.x: A(esq)→+1=Climb_Left, D(dir)→-1=Climb_Right, W/S→0=Climb_Up
	var target_climb_dir := clampf(-input_dir.x, -1.0, 1.0)
	var cur_climb_dir := animation_tree.get("parameters/Climb_R_Up_L/blend_amount") as float
	animation_tree.set("parameters/Climb_R_Up_L/blend_amount", lerpf(cur_climb_dir, target_climb_dir, delta * 12.0))

	# ── Queda/Pulo: ativa Fall sempre que o player estiver no ar e não escalando ──
	var target_fall := 0.0 if (is_on_floor() or climb or mounted) else 1.0
	var cur_fall := animation_tree.get("parameters/WalkFall/blend_amount") as float
	animation_tree.set("parameters/WalkFall/blend_amount", lerpf(cur_fall, target_fall, delta * 8.0))
