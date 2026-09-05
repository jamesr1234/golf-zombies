@tool
class_name FoldingSteps
extends StaticBody3D
## Stairs with a lever on the top landing. Throw the lever and every step swings
## into one even slope, pivoting about the lip of the landing until it is steeper
## than a player can stand on. Whoever reached the lever first keeps the top and
## everybody still on the stairs slides back down.

const CELL := 1.35
const USE_RANGE := 2.8
const COOL := 0.5
## Seconds for the stairs to swing flat.
const FOLD_TIME := 0.9
## Target tread rise. Treads this shallow keep the walking slope inside half a
## tread of the step it belongs to, so feet land on the steps you can see.
const STEP_RISE := CELL / 5.0
## Treads overlap by this much so the folded slope has no cracks in it.
const OVERLAP := 1.35
## Degrees the folded slope must clear the player floor limit by.
const OVER_STEEP := 5.0
const DECK := 0.34
const POST_H := 1.15
const LEVER_L := 0.62
const LEVER_TILT := 0.62

## Footprint in grid cells: run along +X, rise, width along Z. The origin sits at
## the toe of the stairs, the way the obstacle pieces grow from a ground corner.
## The run tracks the rise so the climb stays inside the player floor limit; a
## rise that outruns the run would leave stairs nobody can walk up either.
@export var run_cells := 6
@export var rise_cells := 6
@export var width_cells := 3
## Landing at the head of the stairs, in cells. The lever stands on it.
@export var landing_cells := 1
## Slope the steps fold into, clamped clear of the player floor limit.
@export var fold_deg := 66.0

@export var sync_folded := false

var _fold := 0.0
var _cool := 0.0
var _bricks: Array[Node3D] = []
var _slope: CollisionShape3D
var _lever: Node3D
var _glow: StandardMaterial3D


static func nearest(who: Node3D) -> FoldingSteps:
	var best: FoldingSteps
	var best_d := INF
	if who == null or not who.is_inside_tree():
		return null
	for node in who.get_tree().get_nodes_in_group("folding_steps"):
		var stairs := node as FoldingSteps
		if stairs == null or not stairs.can_use(who):
			continue
		var d := who.global_position.distance_to(stairs.lever_at())
		if d < best_d:
			best = stairs
			best_d = d
	return best


func _ready() -> void:
	add_to_group("folding_steps")
	_build()
	_fold = 1.0 if sync_folded else 0.0
	_pose()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	if NetSession.is_active():
		NetSync.attach(self, PackedStringArray([":sync_folded"]))


func run_len() -> float:
	return float(maxi(1, run_cells)) * CELL


func rise_len() -> float:
	return float(maxi(1, rise_cells)) * CELL


func width_len() -> float:
	return float(maxi(1, width_cells)) * CELL


func landing_len() -> float:
	return float(maxi(1, landing_cells)) * CELL


func step_count() -> int:
	return maxi(3, roundi(rise_len() / STEP_RISE))


## Slope of the stairs. Walkable as long as the rise does not outrun the run.
func stair_angle() -> float:
	return atan2(rise_len(), run_len())


func fold_angle() -> float:
	return deg_to_rad(clampf(fold_deg, PlayerMotion.FLOOR_MAX_DEG + OVER_STEEP, 82.0))


func slope_angle() -> float:
	return lerpf(stair_angle(), fold_angle(), _ease())


## Lip of the landing. The slope pivots about this point, so it never moves.
func slope_top() -> Vector3:
	return Vector3(run_len(), rise_len(), 0.0)


## Where the slope meets the ground. Steepening walks the toe up the footprint.
func slope_toe() -> Vector3:
	return slope_top() - Vector3(rise_len() / tan(slope_angle()), rise_len(), 0.0)


func is_folded() -> bool:
	return sync_folded


func fold_amount() -> float:
	return _fold


func lever_at() -> Vector3:
	if _lever == null:
		return global_position
	return _lever.global_position


func can_use(who: Node3D) -> bool:
	if who == null or not is_inside_tree():
		return false
	if who.get("health") != null and who.health.has_method("is_alive"):
		if not who.health.is_alive():
			return false
	if who.get("shopping") == true or who.get("talking") == true:
		return false
	if who.get("state") != null and int(who.state) != 0:
		return false
	return who.global_position.distance_to(lever_at()) <= USE_RANGE


func try_toggle(player: Node) -> void:
	if not Engine.is_editor_hint() and NetSession.is_active() and not multiplayer.is_server():
		_request_toggle.rpc_id(1, int(player.get("peer_id")))
		return
	_flip(player)


func _flip(player: Node = null) -> void:
	if player != null and not can_use(player):
		return
	if _cool > 0.0:
		return
	sync_folded = not sync_folded
	_cool = COOL
	Sfx.play("steps_fold" if sync_folded else "steps_unfold", self)


func _physics_process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	var target := 1.0 if sync_folded else 0.0
	if is_equal_approx(_fold, target):
		return
	_fold = move_toward(_fold, target, delta / FOLD_TIME)
	_pose()


func _ease() -> float:
	return smoothstep(0.0, 1.0, _fold)


## One walking slab under the treads, swung about the landing lip. The tread
## boxes are the picture of it; this is what feet and the ball actually meet.
func _pose() -> void:
	if _slope == null:
		return
	var e := _ease()
	var theta := slope_angle()
	var along := Vector3(cos(theta), sin(theta), 0.0)
	var up := Vector3(-sin(theta), cos(theta), 0.0)
	var span := slope_top().distance_to(slope_toe())
	var box := _slope.shape as BoxShape3D
	var thick := box.size.y
	box.size.x = span
	_slope.rotation.z = theta
	_slope.position = slope_top() - along * (span * 0.5) - up * (thick * 0.5)
	var n := _bricks.size()
	if n > 0:
		var rise := rise_len()
		var flat_len := run_len() / float(n)
		var ramp_len := span / float(n)
		for i in n:
			var flat := Vector3(
				(float(i) + 0.5) * flat_len, (float(i) + 0.5) * rise / float(n) - thick * 0.5, 0.0
			)
			var ramp := (
				slope_toe() + along * ((float(i) + 0.5) * ramp_len) - up * (thick * 0.5)
			)
			_bricks[i].position = flat.lerp(ramp, e)
			_bricks[i].rotation.z = theta * e
			_bricks[i].scale.x = lerpf(1.0, ramp_len / flat_len, e)
	if _lever != null:
		_lever.rotation.z = lerpf(LEVER_TILT, -LEVER_TILT, e)
	if _glow != null:
		var tint := Palette.LIME.lerp(Palette.LED_RED, e)
		_glow.albedo_color = tint
		_glow.emission = tint


## Built every load rather than saved, so a size change or a duplicate in the
## editor comes up right and the scene file stays one node.
func _build() -> void:
	for child in get_children():
		child.free()
	_bricks.clear()
	collision_layer = Layers.WORLD
	collision_mask = 0
	_glow = MeshFactory.material(Palette.LIME, false, Palette.GLOW_SOFT)
	_build_support()
	_build_steps()
	_build_landing()
	_build_lever()


## Pier under the landing plus stacked blocks under the stairs. The fill stays
## under the folded slope so the treads still have room to swing down.
func _build_support() -> void:
	var root := Node3D.new()
	root.name = "Support"
	add_child(root)
	var pier_h := maxf(0.08, rise_len() - DECK)
	_add_block(
		root,
		"Pier",
		Vector3(landing_len(), pier_h, width_len()),
		Vector3(run_len() + landing_len() * 0.5, pier_h * 0.5, 0.0)
	)
	var pitch := tan(fold_angle())
	var n := maxi(1, rise_cells)
	var slab := rise_len() / float(n)
	for i in n:
		var top := slab * float(i + 1)
		var left := run_len() - (rise_len() - top) / pitch
		var depth := run_len() - left
		if depth < 0.08:
			continue
		_add_block(
			root,
			"Block%d" % i,
			Vector3(depth, slab, width_len()),
			Vector3(left + depth * 0.5, top - slab * 0.5, 0.0)
		)


func _add_block(root: Node3D, block_name: String, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	shape.name = block_name
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	root.add_child(shape)
	var mesh := MeshFactory.box(size, Palette.WALL.darkened(0.2), Palette.GLOW_FAINT)
	mesh.name = "%sMesh" % block_name
	mesh.position = at
	root.add_child(mesh)


func _build_steps() -> void:
	var n := step_count()
	var thick := rise_len() / float(n) * OVERLAP
	var tread := Vector3(run_len() / float(n), thick, width_len())
	var steps := Node3D.new()
	steps.name = "Steps"
	add_child(steps)
	for i in n:
		var brick := MeshFactory.box(tread, Palette.WALL, Palette.GLOW_FAINT)
		brick.name = "Step%d" % i
		brick.add_child(_lip(tread))
		steps.add_child(brick)
		_bricks.append(brick)
	_slope = CollisionShape3D.new()
	_slope.name = "Slope"
	var box := BoxShape3D.new()
	box.size = Vector3(rise_len() / sin(stair_angle()), thick, width_len())
	_slope.shape = box
	add_child(_slope)


func _build_landing() -> void:
	var size := Vector3(landing_len(), DECK, width_len())
	var at := slope_top() + Vector3(landing_len() * 0.5, -DECK * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	shape.name = "Landing"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	add_child(shape)
	var deck := MeshFactory.box(size, Palette.WALL, Palette.GLOW_FAINT)
	deck.name = "LandingDeck"
	deck.position = at
	deck.add_child(_lip(size))
	add_child(deck)


## Glowing lip along the top of a slab. Every lip shares one material, so the
## whole piece goes from green to red the moment the lever moves.
func _lip(slab: Vector3) -> MeshInstance3D:
	var lip := MeshFactory.box(Vector3(slab.x * 1.02, 0.05, slab.z * 1.02), Palette.LIME)
	lip.name = "Lip"
	lip.material_override = _glow
	lip.position.y = slab.y * 0.5
	lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return lip


func _build_lever() -> void:
	var base := slope_top() + Vector3(landing_len() * 0.5, 0.0, 0.0)
	var post := MeshFactory.box(Vector3(0.16, POST_H, 0.16), Palette.CART_FRAME)
	post.name = "LeverPost"
	post.position = base + Vector3(0.0, POST_H * 0.5, 0.0)
	add_child(post)
	_lever = Node3D.new()
	_lever.name = "Lever"
	_lever.position = base + Vector3(0.0, POST_H, 0.0)
	add_child(_lever)
	var arm := MeshFactory.box(Vector3(LEVER_L, 0.1, 0.1), Palette.LIME)
	arm.name = "LeverArm"
	arm.material_override = _glow
	arm.position = Vector3(LEVER_L * 0.5, 0.0, 0.0)
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lever.add_child(arm)
	var knob := MeshFactory.sphere(0.12, Palette.AMBER, Palette.GLOW_STRONG)
	knob.name = "LeverKnob"
	knob.position = Vector3(LEVER_L * 0.5, 0.0, 0.0)
	knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.add_child(knob)


@rpc("any_peer", "reliable")
func _request_toggle(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for node in get_tree().get_nodes_in_group("players"):
		if int(node.get("peer_id")) == peer_id:
			_flip(node)
			return
