extends Node3D

enum PowerUp {
	VELOCIDADE,
	LAMA,
	CAVALO_ESTRESSADO,
	MERDA_DE_CAVALO,
}

const BUFFS   := [PowerUp.VELOCIDADE, PowerUp.MERDA_DE_CAVALO]
const DEBUFFS := [PowerUp.LAMA, PowerUp.CAVALO_ESTRESSADO]

@export var respawn_time: float    = 8.0
@export var effect_duration: float = 5.0
@export var speed_multiplier: float = 2.0  # Velocidade: 2×
@export var slow_multiplier: float  = 0.4  # Lama: 40% da velocidade

var _horse: Node3D = null
var _active: PowerUp = -1
var _saved_walk: float
var _saved_run: float

func _ready() -> void:
	$Area3D.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not visible or _horse != null:
		return
	_horse = body
	_collect()

func _collect() -> void:
	visible = false

	if _active >= 0:
		_revert()

	var pool := BUFFS if randf() > 0.5 else DEBUFFS
	var pw: PowerUp = pool[randi() % pool.size()]

	_apply(pw)
	get_tree().create_timer(respawn_time).timeout.connect(_respawn)

func _apply(pw: PowerUp) -> void:
	match pw:
		PowerUp.VELOCIDADE:
			_save_speed()
			_horse.walk_speed *= speed_multiplier
			_horse.run_speed  *= speed_multiplier
			_active = pw
			get_tree().create_timer(effect_duration).timeout.connect(_revert)
			print("[LuckyBlock] VELOCIDADE x%.1f por %.0fs" % [speed_multiplier, effect_duration])

		PowerUp.LAMA:
			_save_speed()
			_horse.walk_speed *= slow_multiplier
			_horse.run_speed  *= slow_multiplier
			_active = pw
			get_tree().create_timer(effect_duration).timeout.connect(_revert)
			print("[LuckyBlock] LAMA — velocidade reduzida por %.0fs" % effect_duration)

		PowerUp.CAVALO_ESTRESSADO:
			print("[LuckyBlock] CAVALO ESTRESSADO — pendente: force_dismount() no horse.gd")
			_horse = null

		PowerUp.MERDA_DE_CAVALO:
			print("[LuckyBlock] MERDA DE CAVALO — pendente: sistema de projétil")
			_horse = null

func _save_speed() -> void:
	_saved_walk = _horse.walk_speed
	_saved_run  = _horse.run_speed

func _revert() -> void:
	if is_instance_valid(_horse) and _active in [PowerUp.VELOCIDADE, PowerUp.LAMA]:
		_horse.walk_speed = _saved_walk
		_horse.run_speed  = _saved_run
	_active = -1
	_horse = null

func _respawn() -> void:
	visible = true
