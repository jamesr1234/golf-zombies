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
	# #region agent log
	_dbg_probe(delta)
	# #endregion


# #region agent log
const DBG_PATH := "/Users/jamesritchie/golf-zombies/.cursor/debug-3dfb49.log"

var _dbg_n := 0
var _dbg_t := 0.0


func _dbg_probe(delta: float) -> void:
	_dbg_t += delta
	if _dbg_n >= 8 or _dbg_t < 2.0:
		return
	_dbg_t = 0.0
	_dbg_n += 1
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var near_led: MeshInstance3D = null
	var best := 1000000.0
	for node in get_tree().root.find_children("Leds", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var d := global_position.distance_to(mi.global_position)
		if d < best:
			best = d
			near_led = mi
	if near_led == null:
		return
	var span := 2.0 * tan(deg_to_rad(fov) * 0.5)
	var box := near_led.global_transform * near_led.mesh.get_aabb()
	var f := FileAccess.open(DBG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(DBG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "3dfb49",
		"runId": "probe-widen",
		"hypothesisId": "FGH",
		"location": "scripts/player/player_camera.gd",
		"message": "led pixel width probe",
		"data": {
			"viewport": [int(size.x), int(size.y)],
			"msaa_3d": vp.msaa_3d,
			"screen_space_aa": vp.screen_space_aa,
			"use_taa": vp.use_taa,
			"fov": snappedf(fov, 0.1),
			"near_far": [snappedf(near, 0.01), snappedf(far, 1.0)],
			"led": String(near_led.get_parent().name),
			"shader": (near_led.material_override as ShaderMaterial) != null,
			"has_custom0": (near_led.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0,
			"dist_m": snappedf(best, 0.1),
			"bar_px": snappedf((0.03 / best) / span * size.x, 0.01),
			"widened_px": snappedf(maxf((0.03 / best) / span * size.x, 2.2), 0.01),
			"px_at_15m": snappedf((0.03 / 15.0) / span * size.x, 0.01),
			"px_at_40m": snappedf((0.03 / 40.0) / span * size.x, 0.01),
			"led_bottom_y": snappedf(box.position.y, 0.001),
		},
		"timestamp": int(Time.get_unix_time_from_system() * 1000.0),
	}))
	f.close()
# #endregion
