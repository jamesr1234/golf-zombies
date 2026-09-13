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
var _history := CreatorHistory.new()


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
	_ui.group_requested.connect(_save_group)
	_ui.exit_requested.connect(_leave)
	_ui.playtest_requested.connect(playtest)
	_ui.overview_requested.connect(overview)
	_ui.name_requested.connect(ask_save)
	_ui.merge_requested.connect(ask_group)
	_ui.width_picked.connect(_on_width_picked)
	_ui.width_cancelled.connect(_back_to_browser)
	_ui.spawn_picked.connect(_on_spawn_picked)
	_ui.spawn_cancelled.connect(_on_spawn_cancelled)
	_ui.undo_requested.connect(undo_change)
	_ui.redo_requested.connect(redo_change)
	_ui.erase_requested.connect(erase_hole)
	_ui.erase_cancelled.connect(_on_erase_cancelled)
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
	if _ui.is_blocking():
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
	if _leaving or _ui.is_typing() or _ui.is_blocking():
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
			if _place.is_gating():
				if _commit(_place.set_gate):
					Sfx.play("ui_confirm", self)
			elif _place.is_hunting():
				if _commit(_place.set_aggro):
					Sfx.play("ui_confirm", self)
					_ask_spawn()
			elif _place.is_roaming():
				if _commit(_place.set_roam):
					Sfx.play("ui_confirm", self)
			elif _commit(_place.place):
				Sfx.play("ui_confirm", self)
		Tool.GROUP:
			_group.toggle()
		_:
			if _commit(_fairway.place):
				Sfx.play("ui_confirm", self)


func cancel() -> void:
	match tool:
		Tool.PLACE:
			if _place.is_gating():
				if _commit(_place.clear_gate):
					Sfx.play("ui_back", self)
			elif _place.is_zipping():
				if _place.clear_zip():
					Sfx.play("ui_back", self)
			elif _place.is_roaming():
				if _commit(_place.abort_spawn):
					Sfx.play("ui_back", self)
			elif _place.release_hold():
				Sfx.play("ui_back", self)
			else:
				var hover := _hover_point()
				# #region agent log
				var _aim := _camera.aim_point()
				var _ghost := _place.aim_at()
				var _from := _camera.global_position
				var _hit := _hover_hit()
				var _f := FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-2b6f56.log", FileAccess.READ_WRITE)
				if _f == null:
					_f = FileAccess.open("/Users/jamesritchie/golf-zombies/.cursor/debug-2b6f56.log", FileAccess.WRITE)
				if _f != null:
					var _hp := _hit.get("position", Vector3.ZERO) as Vector3
					var _col = _hit.get("collider")
					_f.seek_end()
					_f.store_line(JSON.stringify({
						"sessionId": "2b6f56", "runId": "post-fix", "hypothesisId": "B",
						"location": "creator_mode.gd:cancel",
						"message": "erase aim vs ray", "timestamp": Time.get_ticks_msec(),
						"data": {
							"aim": [snappedf(_aim.x, 0.01), snappedf(_aim.y, 0.01), snappedf(_aim.z, 0.01)],
							"ghost": [snappedf(_ghost.x, 0.01), snappedf(_ghost.y, 0.01), snappedf(_ghost.z, 0.01)],
							"hover": [snappedf(hover.x, 0.01), snappedf(hover.y, 0.01), snappedf(hover.z, 0.01)],
							"cam": [snappedf(_from.x, 0.01), snappedf(_from.y, 0.01), snappedf(_from.z, 0.01)],
							"reach": snappedf(_camera.reach, 0.01),
							"cam_to_aim": snappedf(_from.distance_to(_aim), 0.01),
							"aim_vs_ghost": snappedf(_aim.distance_to(_ghost), 0.01),
							"used_ray": not _hit.is_empty(),
							"ray_hit": not _hit.is_empty(),
							"ray_pos": [snappedf(_hp.x, 0.01), snappedf(_hp.y, 0.01), snappedf(_hp.z, 0.01)],
							"ray_name": String(_col.name) if _col is Node else "",
							"ray_path": String(_col.scene_file_path) if _col is Node else "",
							"cam_to_ray": snappedf(_from.distance_to(_hp), 0.01) if not _hit.is_empty() else -1.0,
							"aim_vs_ray": snappedf(_aim.distance_to(_hp), 0.01) if not _hit.is_empty() else -1.0,
							"hover_vs_aim": snappedf(hover.distance_to(_aim), 0.01),
						},
					}))
					_f.close()
				# #endregion
				_take_back(_place.erase.bind(hover))
		Tool.GROUP:
			_group.clear()
		_:
			_take_back(_fairway.undo)


func undo_change() -> void:
	if not _history.undo(hole):
		_on_refused("NOTHING TO UNDO")
		return
	_drop_place_flow()
	_rebuild()
	Sfx.play("ui_back", self)


func redo_change() -> void:
	if not _history.redo(hole):
		_on_refused("NOTHING TO REDO")
		return
	_drop_place_flow()
	_rebuild()
	Sfx.play("ui_confirm", self)


func _drop_place_flow() -> void:
	_place.roaming = -1
	_place.hunting = false
	_place.gating = -1
	_place.zip_from = Vector3.INF


func _take_back(action: Callable) -> void:
	if not _commit(action):
		return
	Sfx.play("ui_back", self)
	_rebuild()


func _commit(action: Callable) -> bool:
	var before := hole.to_dict()
	if not action.call():
		return false
	_remember(before)
	return true


func _remember(before: Dictionary) -> void:
	if hole.to_dict() == before:
		return
	_history.record(before)


## The piece under the crosshair, not the point hanging at camera reach. Reach
## often punches through the grass when looking down, so erase used to miss or
## grab a neighbour past the thing being looked at.
func _hover_point() -> Vector3:
	var hit := _hover_hit()
	if hit.is_empty():
		return _camera.aim_point()
	return hit["position"] as Vector3


func _hover_hit() -> Dictionary:
	var world := get_world_3d()
	if world == null or _camera == null:
		return {}
	var from := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(
		from, from + dir * 80.0, Layers.WORLD | Layers.PROP | Layers.SURFACE
	)
	return world.direct_space_state.intersect_ray(query)


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


## Circle / F: merge a group, draw a weapon line when a gun is already down,
## or park the ghost so the camera can walk around it before R2 places.
func context() -> void:
	match tool:
		Tool.GROUP:
			ask_group()
		Tool.PLACE:
			_place_context()
		_:
			pass


func _place_context() -> void:
	if _place.is_holding():
		_place.release_hold()
		Sfx.play("ui_back", self)
		_refresh_ui()
		return
	if _place.nearest_weapon(_camera.aim_point()) >= 0:
		draw_weapon_line()
		return
	if _place.hold():
		Sfx.play("ui_move", self)
		_ui.flash("HOLDING")
		_refresh_ui()


func ask_group() -> void:
	_ui.ask_group(HoleStore.suggest_structure_title())


func ask_save() -> void:
	_ui.ask_save(hole.title)


func erase_hole() -> void:
	var before := hole.to_dict()
	hole.erase()
	_remember(before)
	_drop_place_flow()
	_group.clear()
	_rebuild()
	_camera.frame(_world.data)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ui.flash("HOLE ERASED")
	Sfx.play("ui_back", self)


func _on_erase_cancelled() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _ask_spawn() -> void:
	_ui.ask_spawn()


func _on_spawn_picked(counts: Dictionary) -> void:
	if _commit(_place.finish_spawn.bind(counts)):
		_refresh_props()
	else:
		_commit(_place.abort_spawn)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_spawn_cancelled() -> void:
	_commit(_place.abort_spawn)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle_menu() -> void:
	_ui.toggle_menu()


func menu_is_open() -> bool:
	return _ui.menu_is_open()


func toggle_help() -> void:
	_ui.toggle_help()


func help_is_open() -> bool:
	return _ui.help_is_open()


func move_menu(delta: int) -> void:
	_ui.move_menu(delta)


func pick_menu() -> void:
	_ui.pick_menu()


func cycle_tool(delta: int) -> void:
	switch_tool(posmod(int(tool) + delta, Tool.size()))


func switch_tool(next: Tool) -> void:
	if tool == next:
		return
	var before := hole.to_dict()
	tool = next
	_place.release()
	_remember(before)
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
	var before := hole.to_dict()
	hole.fairway_size = size
	hole.needs_width = false
	_remember(before)
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
func _save_group(title: String) -> void:
	_commit(_group.save.bind(title))


func _on_group_saved(path: String) -> void:
	_refresh_props()
	_ui.flash("MERGED INTO %s" % HoleStore.structure_title(path))


func _on_refused(reason: String) -> void:
	Sfx.play("ui_deny", self)
	_ui.flash(reason)
