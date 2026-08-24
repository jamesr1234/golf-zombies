class_name Raygun
extends Node3D
## The gun the player carries, hung off the head so it follows the view. It rides
## up and down with the stride while you run and settles dead still the moment you
## pull the trigger, so a shot is never taken from a moving gun. Reloading lifts
## it and gives it a short wiggle, the same motion on both meshes. Swapping to the
## shotgun replaces the raygun mesh and lets the stock kick back on each blast.

## The gun rides right against the camera, where the player's own lamp would wash it
## out, so its meshes sit on their own render layer and that lamp skips them.
const VIEW_LAYER := 1 << 1

const REST := Vector3(0.15, -0.095, -0.5)
## Small numbers go a long way here: each half of the screen is short, so its
## vertical field of view is narrow and a couple of centimetres of gun reads as a
## clear lope.
const BOB_HEIGHT := 0.024
const BOB_SWAY := 0.012
const BOB_ROLL_DEG := 1.6
## Radians of bob phase per second at a full sprint.
const BOB_RATE := 7.5
## How long the gun stays locked after the trigger comes back up.
const STEADY_LINGER := 0.15
## How fast the bob fades in and out. High enough to feel like the gun is snapped
## onto the target, low enough that it is never a jump cut.
const SETTLE_SPEED := 8.0
const KICK_BACK := Vector3(0.01, 0.022, 0.08)
const KICK_PITCH_DEG := -11.0
const KICK_RECOVER := 0.55
## Up, a little inward, and closer to the camera, like bringing the mag up.
const RELOAD_LIFT := Vector3(0.03, 0.085, 0.045)
const RELOAD_PITCH_DEG := -18.0
const RELOAD_YAW_DEG := 10.0
const RELOAD_ROLL_DEG := 8.0
const RELOAD_WIGGLE := Vector3(0.012, 0.01, 0.008)
const RELOAD_WIGGLE_TURNS := 3.2
## Fraction of the reload spent raising, then dropping. The middle holds the pose.
const RELOAD_RAISE := 0.16

var _rifle: Node3D
var _shotgun: Node3D
var _rocket: Node3D
var _sniper: Node3D
var _net: Node3D
var _flare: Node3D
var _nailer: Node3D
var _phase := 0.0
var _amount := 0.0
var _steady_left := 0.0
var _kick_pos := Vector3.ZERO
var _kick_pitch := 0.0
var _melee_left := 0.0


func _ready() -> void:
	position = REST


func build(color: Color) -> void:
	_rifle = Node3D.new()
	add_child(_rifle)
	_build_rifle(_rifle, color)
	_shotgun = Node3D.new()
	add_child(_shotgun)
	_build_shotgun(_shotgun, color)
	_rocket = Node3D.new()
	add_child(_rocket)
	_build_rocket(_rocket, color)
	_sniper = Node3D.new()
	add_child(_sniper)
	_build_sniper(_sniper, color)
	_net = Node3D.new()
	add_child(_net)
	_build_net(_net, color)
	_flare = Node3D.new()
	add_child(_flare)
	_build_flare(_flare, color)
	_nailer = Node3D.new()
	add_child(_nailer)
	_build_nailer(_nailer, color)
	_paint_view(self)
	show_gun("rifle")


func use_shotgun(on: bool) -> void:
	show_gun("shotgun" if on else "rifle")


func show_gun(kind: String) -> void:
	if _rifle == null:
		return
	_rifle.visible = kind == "rifle"
	_shotgun.visible = kind == "shotgun"
	if _rocket != null:
		_rocket.visible = kind == "rocket"
	if _sniper != null:
		_sniper.visible = kind == "sniper"
	if _net != null:
		_net.visible = kind == "net"
	if _flare != null:
		_flare.visible = kind == "flare"
	if _nailer != null:
		_nailer.visible = kind == "nailer"


func is_shotgun() -> bool:
	return _shotgun != null and _shotgun.visible


func is_rocket() -> bool:
	return _rocket != null and _rocket.visible


func is_sniper() -> bool:
	return _sniper != null and _sniper.visible


func is_net() -> bool:
	return _net != null and _net.visible


func is_flare() -> bool:
	return _flare != null and _flare.visible


func is_nailer() -> bool:
	return _nailer != null and _nailer.visible


## Farthest the visible gun reaches down the barrel, used to tell the two meshes apart.
func forward_extent() -> float:
	var root := _rifle
	if is_rocket():
		root = _rocket
	elif is_sniper():
		root = _sniper
	elif is_net():
		root = _net
	elif is_flare():
		root = _flare
	elif is_nailer():
		root = _nailer
	elif is_shotgun():
		root = _shotgun
	if root == null:
		return 0.0
	var z := 0.0
	for child in root.get_children():
		z = minf(z, child.position.z)
	return z


func kick(strength: float) -> void:
	if strength <= 0.0:
		return
	_kick_pos = KICK_BACK * strength
	_kick_pitch = deg_to_rad(KICK_PITCH_DEG * strength)


func start_melee() -> void:
	_melee_left = Melee.SWING_TIME
	_kick_pos = Vector3.ZERO
	_kick_pitch = 0.0
	_amount = 0.0


func is_meleeing() -> bool:
	return _melee_left > 0.0


## Pace is the fraction of a sprint the player is travelling at; shooting locks the
## gun still while the trigger is producing shots. Kick sits on top of that rest.
## Reload fraction is 0 idle and 0..1 while a mag is going in, matching the weapon.
## A melee swing replaces bob and reload for the duration of the club stroke.
func animate(delta: float, pace: float, shooting: bool, reload_fraction := 0.0) -> void:
	if shooting:
		_steady_left = STEADY_LINGER
	else:
		_steady_left = maxf(0.0, _steady_left - delta)
	if _melee_left > 0.0:
		_melee_left = maxf(0.0, _melee_left - delta)
		var progress := 1.0 - _melee_left / Melee.SWING_TIME
		var euler := melee_euler_deg(progress)
		position = REST + melee_offset(progress)
		rotation = Vector3(deg_to_rad(euler.x), deg_to_rad(euler.y), deg_to_rad(euler.z))
		return
	_phase = wrapf(_phase + clampf(pace, 0.0, 1.0) * BOB_RATE * delta, 0.0, TAU)
	var bob_target := 0.0 if reload_fraction > 0.0 else bob_amount(pace, _steady_left)
	_amount = move_toward(_amount, bob_target, SETTLE_SPEED * delta)
	_kick_pos = _kick_pos.move_toward(Vector3.ZERO, KICK_RECOVER * delta)
	_kick_pitch = move_toward(_kick_pitch, 0.0, deg_to_rad(absf(KICK_PITCH_DEG)) * 4.0 * delta)
	var reload_pos := reload_offset(reload_fraction)
	var reload_rot := reload_rotation(reload_fraction)
	position = REST + bob_offset(_phase, _amount) + _kick_pos + reload_pos
	rotation.x = _kick_pitch + reload_rot.x
	rotation.y = reload_rot.y
	rotation.z = deg_to_rad(sin(_phase) * BOB_ROLL_DEG * _amount) + reload_rot.z


func is_steady() -> bool:
	return is_zero_approx(_amount)


## How much bob the gun should be showing. Zero while shooting, which is what makes
## the shot itself feel aimed rather than sprayed from the hip.
static func bob_amount(pace: float, steady_left: float) -> float:
	if steady_left > 0.0:
		return 0.0
	return clampf(pace, 0.0, 1.0)


## Mostly up and down, with a little sway across, twice per stride.
static func bob_offset(phase: float, amount: float) -> Vector3:
	return Vector3(sin(phase) * BOB_SWAY, sin(phase * 2.0) * BOB_HEIGHT, 0.0) * amount


## 0 at the start and end of a reload, 1 while the mag is being worked.
static func reload_envelope(fraction: float) -> float:
	if fraction <= 0.0 or fraction >= 1.0:
		return 0.0
	if fraction < RELOAD_RAISE:
		return smoothstep(0.0, RELOAD_RAISE, fraction)
	if fraction > 1.0 - RELOAD_RAISE:
		return 1.0 - smoothstep(1.0 - RELOAD_RAISE, 1.0, fraction)
	return 1.0


static func reload_offset(fraction: float) -> Vector3:
	var envelope := reload_envelope(fraction)
	if envelope <= 0.0:
		return Vector3.ZERO
	var turn := fraction * TAU * RELOAD_WIGGLE_TURNS
	var wiggle := Vector3(
		sin(turn) * RELOAD_WIGGLE.x,
		cos(turn * 1.35) * RELOAD_WIGGLE.y,
		sin(turn * 0.85) * RELOAD_WIGGLE.z
	)
	return (RELOAD_LIFT + wiggle) * envelope


static func reload_rotation(fraction: float) -> Vector3:
	var envelope := reload_envelope(fraction)
	if envelope <= 0.0:
		return Vector3.ZERO
	var turn := fraction * TAU * RELOAD_WIGGLE_TURNS
	return Vector3(
		deg_to_rad(RELOAD_PITCH_DEG + sin(turn * 1.15) * 5.0) * envelope,
		deg_to_rad(RELOAD_YAW_DEG + cos(turn) * 4.0) * envelope,
		deg_to_rad(sin(turn * 0.9) * RELOAD_ROLL_DEG) * envelope
	)


## First-person club swing. The gun starts over the right shoulder, drops through
## the middle of the view, and follows through left before recovering to rest.
static func melee_offset(progress: float) -> Vector3:
	return Melee.swing_arc(
		progress,
		Vector3(0.26, 0.14, 0.08),
		Vector3(0.02, -0.12, -0.16),
		Vector3(-0.28, 0.08, 0.04)
	)


static func melee_euler_deg(progress: float) -> Vector3:
	return Melee.swing_arc(
		progress,
		Vector3(-28.0, 48.0, 26.0),
		Vector3(16.0, 0.0, -10.0),
		Vector3(-18.0, -52.0, -20.0)
	)


func _build_rifle(parent: Node3D, color: Color) -> void:
	var shell := color.darkened(0.5)
	var body := MeshFactory.box(Vector3(0.06, 0.075, 0.18), shell)
	parent.add_child(body)
	var grip := MeshFactory.box(Vector3(0.05, 0.11, 0.06), shell)
	grip.position = Vector3(0.0, -0.08, 0.05)
	grip.rotation.x = deg_to_rad(-12.0)
	parent.add_child(grip)
	var cell := MeshFactory.box(Vector3(0.035, 0.04, 0.08), color, Palette.GLOW_SOFT)
	cell.position = Vector3(0.0, 0.045, 0.03)
	parent.add_child(cell)
	var barrel := MeshFactory.cylinder(0.017, 0.16, shell)
	barrel.rotation.x = deg_to_rad(90.0)
	barrel.position.z = -0.14
	parent.add_child(barrel)
	for z: float in [-0.1, -0.14, -0.18]:
		var coil := MeshFactory.cylinder(0.04, 0.016, color, Palette.GLOW_SOFT)
		coil.rotation.x = deg_to_rad(90.0)
		coil.position.z = z
		parent.add_child(coil)
	var emitter := MeshFactory.sphere(0.028, color, Palette.GLOW_MEDIUM)
	emitter.position.z = -0.22
	parent.add_child(emitter)


func _build_shotgun(parent: Node3D, color: Color) -> void:
	var metal := color.darkened(0.42)
	var wood := color.darkened(0.72)
	var receiver := MeshFactory.box(Vector3(0.08, 0.07, 0.16), metal)
	receiver.position = Vector3(0.0, 0.0, 0.02)
	parent.add_child(receiver)
	for x: float in [-0.022, 0.022]:
		var barrel := MeshFactory.cylinder(0.018, 0.34, metal)
		barrel.rotation.x = deg_to_rad(90.0)
		barrel.position = Vector3(x, 0.01, -0.22)
		parent.add_child(barrel)
		var muzzle := MeshFactory.cylinder(0.022, 0.02, color, Palette.GLOW_SOFT)
		muzzle.rotation.x = deg_to_rad(90.0)
		muzzle.position = Vector3(x, 0.01, -0.4)
		parent.add_child(muzzle)
	var pump := MeshFactory.box(Vector3(0.07, 0.045, 0.13), wood)
	pump.position = Vector3(0.0, -0.04, -0.14)
	parent.add_child(pump)
	var grip := MeshFactory.box(Vector3(0.045, 0.12, 0.055), wood)
	grip.position = Vector3(0.0, -0.09, 0.08)
	grip.rotation.x = deg_to_rad(-20.0)
	parent.add_child(grip)
	var stock := MeshFactory.box(Vector3(0.045, 0.055, 0.16), wood)
	stock.position = Vector3(0.0, -0.025, 0.16)
	parent.add_child(stock)
	var butt := MeshFactory.box(Vector3(0.055, 0.09, 0.03), wood)
	butt.position = Vector3(0.0, -0.04, 0.25)
	parent.add_child(butt)


func _build_rocket(parent: Node3D, color: Color) -> void:
	var metal := color.darkened(0.38)
	var tube := MeshFactory.cylinder(0.04, 0.3, metal)
	tube.rotation.x = deg_to_rad(90.0)
	tube.position.z = -0.16
	parent.add_child(tube)
	var drum := MeshFactory.cylinder(0.075, 0.09, color, Palette.GLOW_SOFT)
	drum.rotation.z = deg_to_rad(90.0)
	drum.position = Vector3(0.04, -0.01, 0.02)
	parent.add_child(drum)
	var grip := MeshFactory.box(Vector3(0.05, 0.12, 0.055), metal)
	grip.position = Vector3(0.0, -0.09, 0.08)
	grip.rotation.x = deg_to_rad(-18.0)
	parent.add_child(grip)
	var stock := MeshFactory.box(Vector3(0.05, 0.06, 0.14), metal)
	stock.position = Vector3(0.0, -0.02, 0.16)
	parent.add_child(stock)
	var warhead := MeshFactory.sphere(0.042, Palette.MAGENTA, Palette.GLOW_MEDIUM)
	warhead.position.z = -0.32
	parent.add_child(warhead)


func _build_sniper(parent: Node3D, color: Color) -> void:
	var metal := color.darkened(0.48)
	var stock_col := color.darkened(0.7)
	var receiver := MeshFactory.box(Vector3(0.055, 0.065, 0.2), metal)
	receiver.position = Vector3(0.0, 0.01, 0.02)
	parent.add_child(receiver)
	var barrel := MeshFactory.cylinder(0.014, 0.46, metal)
	barrel.rotation.x = deg_to_rad(90.0)
	barrel.position.z = -0.28
	parent.add_child(barrel)
	var brake := MeshFactory.cylinder(0.02, 0.03, color, Palette.GLOW_SOFT)
	brake.rotation.x = deg_to_rad(90.0)
	brake.position.z = -0.52
	parent.add_child(brake)
	var scope := MeshFactory.cylinder(0.022, 0.12, color, Palette.GLOW_MEDIUM)
	scope.rotation.x = deg_to_rad(90.0)
	scope.position = Vector3(0.0, 0.055, -0.04)
	parent.add_child(scope)
	var lens := MeshFactory.sphere(0.024, Palette.ICE, Palette.GLOW_STRONG)
	lens.position = Vector3(0.0, 0.055, -0.1)
	parent.add_child(lens)
	var grip := MeshFactory.box(Vector3(0.045, 0.11, 0.05), stock_col)
	grip.position = Vector3(0.0, -0.08, 0.08)
	grip.rotation.x = deg_to_rad(-16.0)
	parent.add_child(grip)
	var stock := MeshFactory.box(Vector3(0.045, 0.05, 0.18), stock_col)
	stock.position = Vector3(0.0, -0.02, 0.18)
	parent.add_child(stock)
	var butt := MeshFactory.box(Vector3(0.055, 0.085, 0.03), stock_col)
	butt.position = Vector3(0.0, -0.035, 0.28)
	parent.add_child(butt)


func _build_net(parent: Node3D, color: Color) -> void:
	var metal := color.darkened(0.45)
	var tube := MeshFactory.cylinder(0.032, 0.22, metal)
	tube.rotation.x = deg_to_rad(90.0)
	tube.position.z = -0.12
	parent.add_child(tube)
	var hoop := MeshFactory.torus(0.05, 0.09, Palette.NET, Palette.GLOW_MEDIUM)
	hoop.rotation.x = deg_to_rad(90.0)
	hoop.position.z = -0.26
	parent.add_child(hoop)
	var grip := MeshFactory.box(Vector3(0.045, 0.11, 0.05), metal)
	grip.position = Vector3(0.0, -0.085, 0.07)
	grip.rotation.x = deg_to_rad(-16.0)
	parent.add_child(grip)
	var stock := MeshFactory.box(Vector3(0.04, 0.05, 0.12), metal)
	stock.position = Vector3(0.0, -0.02, 0.14)
	parent.add_child(stock)
	var cell := MeshFactory.box(Vector3(0.04, 0.035, 0.06), Palette.NET, Palette.GLOW_SOFT)
	cell.position = Vector3(0.0, 0.04, 0.02)
	parent.add_child(cell)


func _build_flare(parent: Node3D, color: Color) -> void:
	var metal := color.darkened(0.4)
	var wood := Palette.AMBER.darkened(0.55)
	var head := MeshFactory.box(Vector3(0.07, 0.055, 0.12), wood)
	head.position = Vector3(0.0, 0.01, -0.02)
	parent.add_child(head)
	var shaft := MeshFactory.cylinder(0.016, 0.28, metal)
	shaft.rotation.x = deg_to_rad(90.0)
	shaft.position.z = -0.2
	parent.add_child(shaft)
	var tip := MeshFactory.sphere(0.03, Palette.LIME, Palette.GLOW_STRONG)
	tip.position.z = -0.36
	parent.add_child(tip)
	var ring := MeshFactory.cylinder(0.028, 0.02, Palette.LIME, Palette.GLOW_MEDIUM)
	ring.rotation.x = deg_to_rad(90.0)
	ring.position.z = -0.3
	parent.add_child(ring)
	var grip := MeshFactory.box(Vector3(0.045, 0.11, 0.05), wood)
	grip.position = Vector3(0.0, -0.08, 0.06)
	grip.rotation.x = deg_to_rad(-14.0)
	parent.add_child(grip)
	var cell := MeshFactory.box(Vector3(0.035, 0.03, 0.05), Palette.LIME, Palette.GLOW_SOFT)
	cell.position = Vector3(0.0, 0.045, 0.02)
	parent.add_child(cell)


func _build_nailer(parent: Node3D, color: Color) -> void:
	var metal := Palette.CART.darkened(0.35)
	var body := MeshFactory.box(Vector3(0.055, 0.07, 0.16), metal)
	body.position = Vector3(0.0, 0.0, 0.02)
	parent.add_child(body)
	var barrel := MeshFactory.cylinder(0.015, 0.22, metal)
	barrel.rotation.x = deg_to_rad(90.0)
	barrel.position.z = -0.16
	parent.add_child(barrel)
	var spike := MeshFactory.cylinder(0.01, 0.06, Palette.CART, Palette.GLOW_SOFT)
	spike.rotation.x = deg_to_rad(90.0)
	spike.position.z = -0.3
	parent.add_child(spike)
	var mag := MeshFactory.box(Vector3(0.04, 0.1, 0.05), color.darkened(0.5))
	mag.position = Vector3(0.0, -0.08, 0.0)
	parent.add_child(mag)
	var grip := MeshFactory.box(Vector3(0.042, 0.1, 0.048), metal)
	grip.position = Vector3(0.0, -0.085, 0.07)
	grip.rotation.x = deg_to_rad(-18.0)
	parent.add_child(grip)
	var rail := MeshFactory.box(Vector3(0.03, 0.02, 0.12), Palette.CART, Palette.GLOW_SOFT)
	rail.position = Vector3(0.0, 0.05, -0.04)
	parent.add_child(rail)


func _paint_view(node: Node) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null:
		mesh.layers = VIEW_LAYER
	for child in node.get_children():
		_paint_view(child)
