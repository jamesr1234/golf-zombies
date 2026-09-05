class_name CreatorCamera
extends Camera3D
## Noclip flight for the hole creator. Look and move come off the same actions
## a player uses, so the controls are already in muscle memory. The wheel pushes
## the piece being held nearer or further.

const SPEED := 24.0
const BOOST := 3.0
const REACH_MIN := 4.0
const REACH_MAX := 60.0
const REACH_STEP := GridSnap.CELL * 2.0
const LIFT := 18.0
const OVERVIEW_PITCH := -62.0
## Held pieces sit here by default: far enough to see what you are doing,
## close enough to aim.
const REACH_DEFAULT := 14.0

var reach := REACH_DEFAULT
var yaw := 0.0
var pitch := -14.0
var frozen := false

var _mouse := Vector2.ZERO


static func create() -> CreatorCamera:
	var camera := CreatorCamera.new()
	camera.name = "CreatorCamera"
	camera.fov = PlayerLook.BASE_FOV
	camera.far = 4000.0
	return camera


## Drop in behind the tee looking down the opening fairway, which is where a
## hole is read from.
func frame(data: HoleData) -> void:
	var along := data.along_tee()
	yaw = rad_to_deg(atan2(-along.x, -along.z))
	pitch = -14.0
	global_position = data.tee - along * 26.0 + Vector3.UP * LIFT
	_apply()


## Straight down over the middle of the hole, for laying out the shape.
func overview(data: HoleData) -> void:
	var middle := data.tee.lerp(data.cup, 0.5)
	var span := maxf(data.bounds.size.x, data.bounds.size.y)
	pitch = OVERVIEW_PITCH
	global_position = Vector3(middle.x, middle.y + span * 0.55, middle.z + span * 0.42)
	_apply()


func take_mouse(relative: Vector2) -> void:
	if not frozen:
		_mouse += relative


func nudge_reach(steps: float) -> void:
	reach = clampf(reach + steps * REACH_STEP, REACH_MIN, REACH_MAX)


## Stick up / W is look-forward. Godot's move vector already puts forward on
## -Y, so adding basis.z (the camera's back) walks the way the lens points.
static func travel(basis: Basis, wish: Vector2) -> Vector3:
	return (basis.x * wish.x + basis.z * wish.y).limit_length(1.0)


## Where a held piece hangs. Straight out of the lens, so what is under the
## crosshair is what gets placed.
func aim_point() -> Vector3:
	return global_position - global_transform.basis.z * reach


func fly(delta: float) -> void:
	_turn(delta)
	if frozen:
		return
	var wish := Input.get_vector(
		"p1_move_left", "p1_move_right", "p1_move_forward", "p1_move_back"
	) + Input.get_vector(
		"p2_move_left", "p2_move_right", "p2_move_forward", "p2_move_back"
	)
	var basis := global_transform.basis
	var step := travel(basis, wish)
	# Triangle / Space climb. Cross / Z drop. R3 is rotation snap, not descend.
	if Input.is_physical_key_pressed(KEY_SPACE) or PadInput.pressed("revive"):
		step += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Z) or PadInput.pressed("jump"):
		step += Vector3.DOWN
	# L3 is surface snap, so boost stays on Shift.
	var speed := SPEED * (BOOST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	global_position += step.limit_length(1.0) * speed * delta


func _turn(delta: float) -> void:
	var stick := Input.get_vector(
		"p1_look_left", "p1_look_right", "p1_look_up", "p1_look_down"
	) + Input.get_vector(
		"p2_look_left", "p2_look_right", "p2_look_up", "p2_look_down"
	)
	yaw -= _mouse.x * PlayerLook.MOUSE_DEG_PER_PIXEL
	pitch -= _mouse.y * PlayerLook.MOUSE_DEG_PER_PIXEL
	yaw -= stick.x * PlayerLook.STICK_DEG_PER_SEC * delta
	pitch -= stick.y * PlayerLook.STICK_DEG_PER_SEC * delta
	_mouse = Vector2.ZERO
	_apply()


func _apply() -> void:
	pitch = clampf(pitch, -PlayerLook.PITCH_LIMIT, PlayerLook.PITCH_LIMIT)
	rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
