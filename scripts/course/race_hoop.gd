class_name RaceHoop
extends Area3D
## Standing neon ring off the Test Hole 2 tee. A ball through the mouth
## jumps to the last five hundred yards.

const INNER := 6.0
const TUBE := 0.55
const OUTER := INNER + TUBE
const DETECT := 3.6
const COLOR: Color = Palette.CYAN
const _RaceLane := preload("res://scripts/course/race_lane.gd")

var _data: HoleData
var _rng := RandomNumberGenerator.new()


static func create(data: HoleData) -> RaceHoop:
	var node := RaceHoop.new()
	node.name = "RaceHoop"
	node.position = data.race_hoop
	node.rotation.y = deg_to_rad(data.race_hoop_yaw)
	node._data = data
	node._assemble()
	return node


func _ready() -> void:
	collision_layer = Layers.SURFACE
	collision_mask = Layers.BALL
	monitoring = true
	if get_child_count() == 0:
		_assemble()
	_rng.randomize()


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		var ball := body as GolfBall
		if ball != null:
			_try_warp(ball)


func _try_warp(ball: GolfBall) -> void:
	if _data == null or _data.centerline.size() < 2:
		return
	if ball.try_race_warp(RaceHole.drop_point(_data, _rng)):
		_RaceLane.ignite_in(ball.get_tree())


func _assemble() -> void:
	collision_layer = Layers.SURFACE
	collision_mask = Layers.BALL
	monitoring = true
	var mouth := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = INNER * 0.86
	cyl.height = DETECT
	mouth.shape = cyl
	mouth.rotation.x = deg_to_rad(90.0)
	mouth.position.y = OUTER
	add_child(mouth)
	var ring := MeshFactory.torus(INNER, OUTER, COLOR, Palette.GLOW_STRONG)
	ring.position.y = OUTER
	add_child(ring)
	var lamp := OmniLight3D.new()
	lamp.light_color = COLOR
	lamp.light_energy = 4.2
	lamp.omni_range = 18.0
	lamp.position.y = OUTER
	add_child(lamp)
