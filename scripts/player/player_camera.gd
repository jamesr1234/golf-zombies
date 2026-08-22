class_name PlayerCamera
extends Camera3D
## Lives in its own SubViewport and copies the view its player asks for, which
## is what lets one player's camera render a world it is not a child of.

const FOV_SPEED := 10.0

var player: Player


func _ready() -> void:
	# Each half of the screen is very wide and short. Locking the field of view
	# to the width keeps the horizontal view honest instead of fisheyeing it.
	keep_aspect = Camera3D.KEEP_WIDTH


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	global_transform = player.get_view_transform()
	fov = lerpf(fov, player.get_view_fov(), FOV_SPEED * delta)
	cull_mask = player.view_cull_mask()
