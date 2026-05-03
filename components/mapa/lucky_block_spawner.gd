extends Node3D

## Spawna lucky_block.tscn em cima da pista.
## Coloque Marker3D filhos onde quiser blocos — o Y é ajustado
## automaticamente pela superfície da pista abaixo do Marker.

const LUCKY_BLOCK_PATH := "res://components/lucky_block/lucky_block.tscn"
const LAYER_CAVALO_MASK: int = 1 << 3   # Layer 4: Cavalo
const LAYER_PISTA_MASK:  int = 1 << 1   # Layer 2: Blocos (chão da pista)

@export var height_above_ground: float = 0.6  # altura do bloco acima da pista
@export var ray_length: float = 20.0          # comprimento do ray de detecção

var _scene: PackedScene

func _ready() -> void:
	if not ResourceLoader.exists(LUCKY_BLOCK_PATH):
		push_warning("[LuckyBlockSpawner] Cena não encontrada: " + LUCKY_BLOCK_PATH)
		return
	_scene = load(LUCKY_BLOCK_PATH)
	# Aguarda um frame para o PhysicsServer inicializar antes de fazer queries
	call_deferred("spawn_all")

func spawn_all() -> void:
	var space := get_world_3d().direct_space_state
	for child in get_children():
		if child is Marker3D:
			_spawn_at(child as Marker3D, space)

func _spawn_at(marker: Marker3D, space: PhysicsDirectSpaceState3D) -> void:
	var spawn_pos: Vector3

	if marker.get_meta("override_y", false):
		# Y manual: usa exatamente a posição do Marker
		spawn_pos = marker.global_position
	else:
		# Y automático: detecta a superfície da pista por raycast
		var origin := marker.global_position + Vector3(0, ray_length * 0.5, 0)
		var target := marker.global_position - Vector3(0, ray_length * 0.5, 0)

		var query := PhysicsRayQueryParameters3D.create(origin, target)
		query.collision_mask = LAYER_PISTA_MASK
		query.collide_with_areas = false

		var hit := space.intersect_ray(query)

		if hit:
			spawn_pos = hit["position"] + Vector3(0, height_above_ground, 0)
		else:
			push_warning("[LuckyBlockSpawner] Sem pista sob '%s', usando posição do Marker." % marker.name)
			spawn_pos = marker.global_position

	var block := _scene.instantiate() as Node3D
	get_parent().add_child(block)
	block.global_position = spawn_pos

	# Garante que o RayCast interno do bloco ignora o cavalo
	var ray := block.get_node_or_null("RayCast3D") as RayCast3D
	if ray:
		ray.collision_mask &= ~LAYER_CAVALO_MASK
