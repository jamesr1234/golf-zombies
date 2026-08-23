extends GutTest
## Both modes must draw the world into a SubViewport rather than straight into
## the window. The window is the full native resolution, which on a retina
## laptop is several times the design resolution, and it carries the project's
## multisampling as well. The neon look leans on glow and fog, so the cost
## scales with pixels rather than with what is on screen, and online used to
## pay it while split-screen did not.

const ONLINE := "res://scenes/net/online_main.tscn"
const SPLIT := "res://scenes/main.tscn"
const ONLINE_SEAT := "Screen/Viewport"
const SPLIT_SEAT := "Screens/Top/Viewport"


func _seat(scene_path: String, seat_path: String) -> SubViewport:
	var root := (load(scene_path) as PackedScene).instantiate()
	autofree(root)
	return root.get_node_or_null(seat_path) as SubViewport


func test_the_online_seat_draws_into_a_subviewport() -> void:
	var seat := _seat(ONLINE, ONLINE_SEAT)
	assert_not_null(seat, "the online world must not render into the window")
	assert_not_null(seat.get_node_or_null("World"), "the world belongs in the seat")
	assert_not_null(seat.get_node_or_null("Camera"), "so does the camera that renders it")
	assert_not_null(seat.get_node_or_null("Hud"), "and the hud drawn over it")


func test_the_online_seat_draws_at_the_design_resolution() -> void:
	var seat := _seat(ONLINE, ONLINE_SEAT)
	assert_eq(seat.size.x, int(ProjectSettings.get_setting("display/window/size/viewport_width")))
	assert_eq(seat.size.y, int(ProjectSettings.get_setting("display/window/size/viewport_height")))


## Multisampling is a project setting, so it lands on the window and not on a
## SubViewport. Split-screen has always dodged it; online now does too.
func test_neither_seat_pays_for_the_window_multisampling() -> void:
	assert_eq(_seat(ONLINE, ONLINE_SEAT).msaa_3d, Viewport.MSAA_DISABLED)
	assert_eq(_seat(SPLIT, SPLIT_SEAT).msaa_3d, Viewport.MSAA_DISABLED)


func test_the_two_modes_agree_on_how_the_world_is_drawn() -> void:
	var online := _seat(ONLINE, ONLINE_SEAT)
	var split := _seat(SPLIT, SPLIT_SEAT)
	assert_eq(online.render_target_update_mode, split.render_target_update_mode)
	assert_eq(online.size.x, split.size.x, "both seats span the design width")
