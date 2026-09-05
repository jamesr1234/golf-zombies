class_name CreatorLandings
extends Node3D
## Circular pads on every full-swing landing from the tee to the cup. Only the
## creator draws these, so a hole can be dressed around where a good shot
## actually finishes. The real green is the last pad.

const NAME := "LandingZones"
const LIFT := 0.16
## A committed swing that just missed the power lock. Great shots sit at the
## centre; this is the short edge of the pad.
const GOOD_POWER := 1.0 - SwingMeter.POWER_SWEET


static func create() -> CreatorLandings:
	var pads := CreatorLandings.new()
	pads.name = NAME
	return pads


static func attach(host: Node3D, data: HoleData) -> void:
	if host == null:
		return
	var pads := create()
	host.add_child(pads)
	pads.refresh(data)


static func carry() -> float:
	return Shot.carry_to_height(0.0)


static func radius() -> float:
	var good := Shot.carry_to_height(0.0, GOOD_POWER)
	return maxf(absf(carry() - good) * 0.5, HoleData.DEFAULT_GREEN_RADIUS * 0.5)


## Landings walk the fairway, not the crow-flies line, so a dogleg still shows
## where the ball would sit after a straight full swing down the strip.
static func spots(data: HoleData) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if data == null or data.centerline.size() < 2:
		return out
	var length := data.length()
	if length <= 0.0:
		return out
	var step := carry()
	var stop := length - data.green_radius
	var along := step
	while along < stop:
		out.append(HoleGenerator.point_along(data, along / length))
		along += step
	return out


func refresh(data: HoleData) -> void:
	for child in get_children():
		child.queue_free()
	if data == null:
		return
	var pad := radius()
	for at in spots(data):
		add_child(_disk(data.lift(at), pad))


func _disk(at: Vector3, pad: float) -> MeshInstance3D:
	var look: Dictionary = Surface.LOOK[Surface.Type.GREEN]
	var color: Color = look["base"]
	color.a = 0.42
	var disk := MeshFactory.disk(pad, color, Palette.GLOW_SOFT)
	disk.position = at + Vector3.UP * LIFT
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := disk.material_override as StandardMaterial3D
	if mat != null:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return disk
