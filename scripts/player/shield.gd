class_name Shield
extends AnimatableBody3D
## Planted in front of a player who is covering. Twice the body width so a
## golfer can stand behind it; enemy shots die on this layer, friendly fire does not.
## Visual is a neon outline — the middle stays empty.

## Same as the player capsule radius. Kept here so this script does not load
## Player (Player already loads Shield).
const BODY_RADIUS := 0.4
const WIDTH := BODY_RADIUS * 4.0
const HEIGHT := 1.72
const THICKNESS := 0.14
const FORWARD := 0.82
const FRAME := 0.07
## Close enough to read the panel, far enough to see the planted robot.
const CAM_DISTANCE := 3.4
const CAM_HEIGHT := 2.15
const CAM_LOOK_HEIGHT := 1.05
const CAM_LOOK_AHEAD := 0.9
const CAM_FOV := 92.0


func _ready() -> void:
	collision_layer = Layers.SHIELD
	collision_mask = 0
	sync_to_physics = false
	name = "Shield"
	add_child(_shape())
	add_child(_outline())
	position = Vector3(0.0, HEIGHT * 0.5, -FORWARD)
	set_raised(false)


func set_raised(on: bool) -> void:
	visible = on
	for child in get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			shape.disabled = not on


static func covers_width() -> float:
	return WIDTH


static func player_width() -> float:
	return BODY_RADIUS * 2.0


## Behind the robot, looking over their shoulder at the panel.
static func view_transform(origin: Vector3, yaw_deg: float, pitch_deg: float) -> Transform3D:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var facing := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var target := origin + Vector3.UP * CAM_LOOK_HEIGHT + facing * CAM_LOOK_AHEAD
	target += Vector3.UP * sin(pitch) * 1.6
	var eye := origin - facing * CAM_DISTANCE + Vector3.UP * CAM_HEIGHT
	eye.y = maxf(eye.y - sin(pitch) * 0.85, origin.y + 0.55)
	var xform := Transform3D(Basis(), eye)
	return xform.looking_at(target, Vector3.UP)


func _shape() -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, THICKNESS)
	node.shape = box
	return node


func _outline() -> Node3D:
	var root := Node3D.new()
	root.name = "Outline"
	var span := HEIGHT - FRAME * 2.0
	root.add_child(_bar(Vector3(WIDTH, FRAME, THICKNESS), Vector3(0.0, (HEIGHT - FRAME) * 0.5, 0.0)))
	root.add_child(_bar(Vector3(WIDTH, FRAME, THICKNESS), Vector3(0.0, (FRAME - HEIGHT) * 0.5, 0.0)))
	root.add_child(_bar(Vector3(FRAME, span, THICKNESS), Vector3((FRAME - WIDTH) * 0.5, 0.0, 0.0)))
	root.add_child(_bar(Vector3(FRAME, span, THICKNESS), Vector3((WIDTH - FRAME) * 0.5, 0.0, 0.0)))
	var lamp := OmniLight3D.new()
	lamp.light_color = Palette.CYAN
	lamp.light_energy = 2.2
	lamp.omni_range = 4.2
	root.add_child(lamp)
	return root


func _bar(size: Vector3, at: Vector3) -> MeshInstance3D:
	var node := MeshFactory.box(size, Palette.CYAN, Palette.GLOW_STRONG)
	node.position = at
	return node
