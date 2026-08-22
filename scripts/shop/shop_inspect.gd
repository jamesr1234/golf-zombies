class_name ShopInspect
extends Node3D
## Hovered clubhouse stock, spun with look while you shop. The camera sits off
## to the left so the listing can occupy that half and the item stays on the right.

const Props := preload("res://scripts/shop/shop_props.gd")

const CAM_DISTANCE := 3.2
const CAM_HEIGHT := 1.65
const CAM_LOOK := 1.05
const CAM_LEFT := 1.4
const CAM_FOV := 70.0
const HOLD := Vector3(0.0, 1.12, -0.58)

var item_id := ""
var yaw := 0.0
var pitch := 0.0
var _pose: Node3D


func _ready() -> void:
	name = "ShopInspect"
	position = HOLD
	visible = false


## In front of the shopper, slid left so the subject lands on the right of frame.
static func view_transform(origin: Vector3, yaw_deg: float) -> Transform3D:
	var facing_yaw := deg_to_rad(yaw_deg)
	var facing := Vector3.FORWARD.rotated(Vector3.UP, facing_yaw)
	var right := Vector3.RIGHT.rotated(Vector3.UP, facing_yaw)
	var target := origin + Vector3.UP * CAM_LOOK
	var eye := origin + facing * CAM_DISTANCE - right * CAM_LEFT + Vector3.UP * CAM_HEIGHT
	return Transform3D(Basis(), eye).looking_at(target, Vector3.UP)


func spin(look: Vector2, tumble := true) -> void:
	yaw = wrapf(yaw - look.x, -180.0, 180.0)
	if tumble:
		pitch = wrapf(pitch + look.y, -180.0, 180.0)
	_apply_spin()


func show_item(item: Dictionary) -> void:
	var next_id := String(item.get("id", ""))
	if next_id == item_id and _pose != null:
		return
	item_id = next_id
	yaw = 0.0
	pitch = 0.0
	_rebuild(item)


func clear() -> void:
	item_id = ""
	yaw = 0.0
	pitch = 0.0
	_drop_pose()
	visible = false


func _rebuild(item: Dictionary) -> void:
	_drop_pose()
	if item.is_empty() or String(item.get("kind", "")) == "apparel":
		visible = false
		return
	_pose = Node3D.new()
	add_child(_pose)
	Props.preview(_pose, item)
	visible = true
	_apply_spin()


func _apply_spin() -> void:
	if _pose == null:
		return
	_pose.rotation_degrees = Vector3(pitch, yaw, 0.0)


func _drop_pose() -> void:
	if _pose == null:
		return
	_pose.queue_free()
	_pose = null
