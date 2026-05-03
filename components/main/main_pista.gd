extends Node3D

func _ready() -> void:
	var player: Node3D = $Player
	var horse:  Node3D = $Horse
	if player and horse and player.has_method("mount_on"):
		player.mount_on(horse)
