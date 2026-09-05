class_name CreatorMode
extends Node3D
## The hole creator. The hole under the player is a real one, built by the same
## HoleBuilder that builds every other hole, so what gets laid out here is
## exactly what gets played.

const MENU := "res://scenes/ui/main_menu.tscn"
const BROWSER := "res://scenes/creator/hole_browser.tscn"
const GAMEPLAY := "res://scenes/main.tscn"

enum Tool { FAIRWAY, PLACE, GROUP }

var hole: CustomHole
var tool: Tool = Tool.FAIRWAY

var _world: CreatorWorld
var _camera: CreatorCamera
var _marks: CreatorMarks
var _held: Node3D
var _ui: CreatorUi
var _fairway: FairwayTool
var _place: PlaceTool
var _group: GroupTool
var _leaving := false
var _view: CreatorView
## Keys and pad buttons both live here, kept off the camera's flight controls.
var _pad: CreatorPad


func _enter_tree() -> void:
	InputActions.register_all()


func _ready() -> void:
	hole = GameSettings.take_creator_hole()
	_world = CreatorWorld.new(self)
	_fairway = FairwayTool.new(hole)
	_place = PlaceTool.new(hole)
	_group = GroupTool.new(hole)
	for handler in [_fairway, _place, _group]:
		handler.refused.connect(_on_refused)
	_fairway.changed.connect(_rebuild)
	_place.changed.connect(_refresh_props)
	_group.changed.connect(_refresh_ui)
	_group.saved.connect(_on_group_saved)

	_camera = CreatorCamera.create()
	add_child(_camera)
	_camera.current = true
	_held = Node3D.new()
	_held.name = "Held"
	add_child(_held)
	_marks = CreatorMarks.create()
	add_child(_marks)
	_ui = CreatorUi.create()
	add_child(_ui)
	_ui.save_requested.connect(_save)
	_ui.group_requested.connect(_group.save)
	_ui.exit_requested.connect(_leave)
	_ui.playtest_requested.connect(playtest)
	_ui.overview_requested.connect(overview)
	_ui.name_requested.connect(ask_save)
	_ui.merge_requested.connect(ask_group)
	_ui.width_picked.connect(_on_width_picked)
	_ui.width_cancelled.connect(_back_to_browser)
	_view = CreatorView.new(self, _marks, _ui, _fairway, _place, _group)
	_pad = CreatorPad.new(self)

	_rebuild()
	_camera.frame(_world.data)
	if hole.needs_width:
		_ui.ask_width()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The bed hangs off the tree root, which is still settling on the frame a
	# scene change lands.
	Music.play_lounge.call_deferred()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if _leaving:
		return
	if _ui.picking_width():
		_camera.frozen = true
		_pad.poll(false, delta)
		return
	_camera.frozen = _ui.is_typing() or _ui.menu_is_open()
	# The name field runs its own pad handling, so the creator lets go while a
	# prompt is up rather than reading the same button twice.
	_pad.poll(not _ui.is_typing(), delta)
	_camera.fly(delta)
	_aim()
	_view.draw(_world.data)
	_refresh_ui()


func _rebuild() -> void:
	_place.release()
	_world.rebuild(hole)
	_refresh_ui()


func _refresh_props() -> void:
	_world.refresh_props(hole)
	_refresh_ui()


func _aim() -> void:
	if not is_inside_tree():
		return
	var at := _camera.aim_point()
	if tool == Tool.PLACE:
		var data := _world.data
		if data != null:
			_place.aim_gate = HeightField.along_t(data, at)
			_place.height = data.height
		var world := get_world_3d()
		_place.space = world.direct_space_state if world != null else null
		_place.aim(_held, _world.nav(), at)
	else:
		_place.release()
	if tool == Tool.GROUP:
		_group.aim(at)


func _refresh_ui() -> void:
	_view.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or _ui.is_typing() or _ui.picking_width():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera.take_mouse((event as InputEventMouseMotion).relative)
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		_on_click(button)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		_pad.on_key(key)


func _on_click(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			confirm()
		MOUSE_BUTTON_RIGHT:
			cancel()
		MOUSE_BUTTON_WHEEL_UP:
			_scroll(1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			_scroll(-1.0)


func _scroll(steps: float) -> void:
	if tool == Tool.GROUP:
		_group.grow(steps)
	else:
		_camera.nudge_reach(steps)


func confirm() -> void:
	match tool:
		Tool.PLACE:
			if _place.set_gate() if _place.is_gating() else _place.place():
				Sfx.play("ui_confirm", self)
		Tool.GROUP:
			_group.toggle()
		_:
			if _fairway.place():
				Sfx.play("ui_confirm", self)


func cancel() -> void:
	match tool:
		Tool.PLACE:
			if _place.clear_gate() if _place.is_gating() else (
				_place.clear_zip() if _place.is_zipping() else _place.erase(_camera.aim_point())
			):
				Sfx.play("ui_back", self)
		Tool.GROUP:
			_group.clear()
		_:
			if _fairway.undo():
				Sfx.play("ui_back", self)


func step_piece(delta: int) -> void:
	match tool:
		Tool.PLACE:
			_place.step_piece(delta)
		Tool.FAIRWAY:
			_fairway.step_pick(delta)
		_:
			pass


func step_shelf(delta: int) -> void:
	_place.step_shelf(delta)


func turn(steps: int) -> void:
	_place.turn(steps)


func spins_free() -> bool:
	return tool == Tool.PLACE and not _place.yaw_snap


func spin(dir: float, delta: float) -> void:
	_place.spin(dir, delta)


## Left and right read as whatever the tool in hand cares about, since turning a
## piece and sizing the group ring are never both on offer.
func side(delta: int) -> void:
	match tool:
		Tool.PLACE:
			_place.turn(delta)
		Tool.GROUP:
			_group.grow(float(delta))
		_:
			_camera.nudge_reach(float(delta))


func overview() -> void:
	_camera.overview(_world.data)


func draw_weapon_line() -> void:
	switch_tool(Tool.PLACE)
	_place.start_gate(_camera.aim_point())


## Circle / F: the extra the tool in hand needs, so one button covers merge
## and a weapon line instead of parking those on two face buttons.
func snap_surface() -> void:
	if tool != Tool.PLACE:
		return
	_place.toggle_surface_snap()
	Sfx.play("ui_move", self)
	_refresh_ui()


func toggle_yaw_snap() -> void:
	_place.toggle_yaw_snap()
	Sfx.play("ui_move", self)
	_ui.flash("ROTATION SNAP ON" if _place.yaw_snap else "ROTATION SNAP OFF")
	_refresh_ui()


func context() -> void:
	match tool:
		Tool.GROUP:
			ask_group()
		Tool.PLACE:
			draw_weapon_line()
		_:
			pass


func ask_group() -> void:
	_ui.ask_group(HoleStore.suggest_structure_title())


func ask_save() -> void:
	_ui.ask_save(hole.title)


func toggle_menu() -> void:
	_ui.toggle_menu()


func menu_is_open() -> bool:
	return _ui.menu_is_open()


func move_menu(delta: int) -> void:
	_ui.move_menu(delta)


func pick_menu() -> void:
	_ui.pick_menu()


func cycle_tool(delta: int) -> void:
	switch_tool(posmod(int(tool) + delta, Tool.size()))


func switch_tool(next: Tool) -> void:
	if tool == next:
		return
	tool = next
	_place.release()
	Sfx.play("ui_move", self)
	_refresh_ui()


func _save(title: String) -> void:
	hole.title = title if not title.strip_edges().is_empty() else hole.title
	if HoleStore.save_hole(hole):
		var slot := HoleStore.course_slot(hole.title)
		if slot >= 0 and hole.is_playable():
			_ui.flash("SAVED %s   REPLACES HOLE %d" % [hole.title.to_upper(), slot + 1])
		else:
			_ui.flash("SAVED %s" % hole.title.to_upper())
	else:
		_ui.flash("COULD NOT SAVE THAT HOLE")


## Straight from the workbench onto the tee, so a shape can be judged by playing
## it rather than by looking at it.
func playtest() -> void:
	if not hole.is_playable():
		_ui.flash("THE HOLE NEEDS AT LEAST %d PIECES" % FairwayPiece.MIN_PIECES)
		return
	if not HoleStore.save_hole(hole):
		_ui.flash("COULD NOT SAVE THAT HOLE")
		return
	GameSettings.play_custom(hole)
	_go(GAMEPLAY)


func _on_width_picked(size: FairwayPiece.Width) -> void:
	hole.fairway_size = size
	hole.needs_width = false
	_rebuild()
	_camera.frame(_world.data)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _back_to_browser() -> void:
	GameSettings.reset()
	_go(BROWSER)


func _leave() -> void:
	GameSettings.reset()
	_go(MENU)


func _go(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(path)


## The merge swapped loose pieces for one structure, so the props have to be
## rebuilt before the change shows.
func _on_group_saved(path: String) -> void:
	_refresh_props()
	_ui.flash("MERGED INTO %s" % HoleStore.structure_title(path))


func _on_refused(reason: String) -> void:
	Sfx.play("ui_deny", self)
	_ui.flash(reason)
