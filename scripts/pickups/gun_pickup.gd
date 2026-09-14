class_name GunPickup
extends Area3D
## A gun on the ground. Walk in and it goes in the bag.

const SPIN_SPEED := 1.1
const SCENE_PATH := "res://scenes/course/props/gun_pickup.tscn"
const TEE_GAP := 2.2
const TEE_COLS := 5
const TEE_BACK := 2.8
const TEE_SIDE := 3.0
const TEE_REST := 0.18
## Spinning pickups are centered on their mesh. Sitting the origin on the
## grass buries the gun and the grab sphere, so a placed gun hovers this high.
const HOVER := 0.65


@export var stats: WeaponStats
## Where down the hole this gun stops working, 0 at the tee and 1 at the cup.
## -1 leaves it live the whole way. Set by the hole creator; nothing draws it.
@export var gate := CustomHole.NO_GATE
## Arena loadout: lie on the floor instead of spinning in the air.
var laid_out := false


## Where a spinning pickup should stand so its mesh and grab sphere sit above
## `at` instead of through it. Laid-out tee and arena guns keep TEE_REST.
static func sit_at(node: Node3D, at: Vector3, yaw := 0.0) -> Vector3:
	return GridSnap.anchored_at(node, at + Vector3.UP * HOVER, yaw)


## Tee rack for generated holes. Arena and custom holes place their own.
static func place_starters(root: Node3D, data: HoleData) -> void:
	if root == null or data == null:
		return
	if ArenaHole.applies(data) or data.custom != null:
		return
	var along := _tee_along(data)
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	for i in Weapon.STARTER_GUNS.size():
		var pickup := (load(SCENE_PATH) as PackedScene).instantiate() as GunPickup
		if pickup == null:
			continue
		pickup.name = "Gun_%d" % i
		pickup.stats = Weapon.STARTER_GUNS[i]
		pickup.laid_out = true
		var col := i % TEE_COLS
		var row := int(i / TEE_COLS)
		var at: Vector3 = (
			data.tee
			- along * (TEE_BACK + float(row) * TEE_GAP)
			- side * (TEE_SIDE + float(col) * TEE_GAP)
		)
		at = data.lift(at)
		at.y += TEE_REST
		pickup.position = at
		root.add_child(pickup)


static func _tee_along(data: HoleData) -> Vector3:
	var along := data.cup - data.tee
	along.y = 0.0
	if along.length_squared() < 0.0001:
		return Vector3.FORWARD
	return along.normalized()


func _ready() -> void:
	add_to_group("gun_pickups")
	collision_layer = Layers.PICKUP
	collision_mask = Layers.PLAYER
	body_entered.connect(_on_body_entered)
	_build()


func _process(delta: float) -> void:
	if laid_out:
		return
	rotate_y(SPIN_SPEED * delta)


func _on_body_entered(body: Node3D) -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		return
	var player := body as Player
	if player == null or player.weapon == null or stats == null:
		return
	if player.weapon.has_gun(stats):
		return
	if not ArenaHole.can_pick(player):
		return
	if not player.weapon.add_gun(stats, gate):
		return
	Sfx.play("pickup_ammo", player)
	if player.flow != null and player.flow.has_method("note_loadout"):
		player.flow.note_loadout(player)
	queue_free()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.85 if laid_out else 1.1
	shape.shape = sphere
	add_child(shape)
	if stats == null:
		return
	var vis := Node3D.new()
	vis.name = "Mesh"
	add_child(vis)
	if stats.visual == "rocket":
		Raygun.build_rocket(vis, Palette.PLAYER_ONE)
		vis.scale = Vector3.ONE * 3.0
	else:
		ShopProps.preview(vis, {"id": stats.visual})
	if laid_out:
		vis.rotation.z = deg_to_rad(90.0)
