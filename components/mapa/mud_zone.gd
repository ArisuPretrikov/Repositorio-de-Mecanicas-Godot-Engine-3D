extends Area3D

## Zona de lama: define metadado "terrain_type" que o RayCast3D do cavalo
## lê em tempo real (sem sinais). O RayCast precisa ter collide_with_areas = true.

@export var terrain_type: String = "mud"
@export var speed_multiplier: float = 0.4

func _ready() -> void:
	set_meta("terrain_type", terrain_type)
	set_meta("speed_multiplier", speed_multiplier)
