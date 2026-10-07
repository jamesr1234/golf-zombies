class_name TouchControls
extends Control
## Phone controls for the web demo. The left half is a floating move stick, the
## right half drags the camera, and a few round buttons hold the same p1_*
## actions the keyboard does, so gameplay code never knows it is a touch screen.

const LOOK_SENS := 0.9
const MOVE_ACTIONS := ["p1_move_left", "p1_move_right", "p1_move_forward", "p1_move_back"]
## Emulated touch-to-mouse clicks would otherwise fire these on every tap.
const MOUSE_ACTIONS := ["shoot", "swing", "aim", "zoom"]
const RIM := Color(Palette.ICE, 0.55)
const FILL := Color(Palette.NIGHT, 0.35)
const HELD := Color(Palette.CYAN, 0.45)

const _HINT := PlayerInput.TOUCH_HINTS

var stick := TouchStick.new()
var fire := TouchButton.new(_HINT["shoot"], ["p1_shoot"], Vector2(0.2, 0.22), 70.0)
var jump := TouchButton.new(_HINT["jump"], ["p1_jump"], Vector2(0.1, 0.42), 52.0)
var reload := TouchButton.new(_HINT["reload"], ["p1_reload"], Vector2(0.4, 0.42), 40.0)
var proceed := TouchButton.new("CONTINUE", ["p1_interact"], Vector2(0.0, 0.0), 90.0)
## Only shown while the prompt names them, so the screen stays uncluttered.
var action := TouchButton.new(_HINT["interact"], ["p1_interact"], Vector2(0.42, 0.2), 48.0)
var pick_up := TouchButton.new(_HINT["drop"], ["p1_sprint"], Vector2(0.62, 0.2), 44.0)
var left_hand := TouchButton.new(_HINT["melee"], ["p1_melee"], Vector2(0.62, 0.42), 44.0)
var right_hand := TouchButton.new(_HINT["shield"], ["p1_shield"], Vector2(0.42, 0.62), 44.0)
var grapple := TouchButton.new(_HINT["grapple"], ["p1_grapple"], Vector2(0.2, 0.62), 44.0)
var _contextual: Array[TouchButton] = [action, pick_up, left_hand, right_hand, grapple]
var _buttons: Array[TouchButton] = [
	fire, jump, reload, proceed, action, pick_up, left_hand, right_hand, grapple,
]
## Browsers hand out any integer as a finger id, negative ones included.
var _look_finger := 0
var _looking := false
## Where each finger was last seen. With two fingers down a browser's drag
## relative is measured from whichever finger moved last, not from this one.
var _last_at := {}
## Only actions this layer pressed get released, so a keyboard stays usable.
var _holding := {}
var _shell: Splitscreen
var _font: Font = HudStyle.READOUT_FONT


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shell = owner as Splitscreen
	PlayerInput.touch = true
	# The keyboard deadzone would swallow a thumb that is not slammed to the rim.
	for action_name in MOVE_ACTIONS:
		if InputMap.has_action(action_name):
			InputMap.action_set_deadzone(action_name, 0.0)
	# A phone turns every tap into a left click, and left click is shoot and swing.
	# The player's own setup runs after this and puts those clicks back, so strip
	# again once the whole tree is ready.
	_strip_mouse_buttons()
	_strip_mouse_buttons.call_deferred()
	# The shell finds its MatchFlow in its own _ready, which runs after ours.
	_listen_for_end.call_deferred()


func _exit_tree() -> void:
	PlayerInput.touch = false
	PlayerInput.touch_move = Vector2.ZERO
	PlayerInput.touch_sprint = false
	PlayerInput.touch_stick_held = false
	PlayerInput.touch_taps.clear()


func _listen_for_end() -> void:
	if _shell != null and _shell.flow() != null:
		_shell.flow().run_ended.connect(_on_run_ended)


func _process(_delta: float) -> void:
	var player := _player()
	var ended := _shell != null and _shell.is_ended()
	var golfing := player != null and player.is_golfing()
	fire.label = _HINT["swing"] if golfing else _HINT["shoot"]
	var prompt := player.get_prompt() if player != null and not ended else ""
	for button in _contextual:
		if not button.is_held():
			button.visible = prompt.contains(button.label)
	reload.visible = not ended and not golfing
	fire.visible = not ended
	jump.visible = not ended
	proceed.visible = ended
	if ended and stick.is_held():
		_release_stick()
	_apply_move()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_down(touch.index, touch.position)
		else:
			_on_up(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_on_drag(drag.index, drag.position)


func _button_at(at: Vector2) -> TouchButton:
	for button in _buttons:
		if button.contains(at):
			return button
	return null


func _on_down(index: int, at: Vector2) -> void:
	_layout()
	_last_at[index] = at
	var on_stick := at.distance_to(_stick_center()) <= _stick_radius() * 1.3
	# The stick wins over a button that happens to sit on top of it.
	if on_stick or (_in_move_zone(at) and _button_at(at) == null):
		if not stick.is_held():
			stick.radius = _stick_radius()
			stick.grab(index, _stick_center())
			stick.drag(at)
			_apply_move()
		return
	var button := _button_at(at)
	if button != null:
		if button.is_held():
			button.release()
		_aim_fire(button)
		button.press(index)
		_note_button(button)
		return
	if not _looking:
		_looking = true
		_look_finger = index


func _on_up(index: int) -> void:
	_last_at.erase(index)
	for button in _buttons:
		if button.is_held() and button.finger == index:
			button.release()
	if stick.is_held() and stick.finger == index:
		_release_stick()
	if _looking and _look_finger == index:
		_looking = false


func _on_drag(index: int, at: Vector2) -> void:
	var slide: Vector2 = at - _last_at.get(index, at)
	_last_at[index] = at
	if stick.is_held() and stick.finger == index:
		stick.drag(at)
		_apply_move()
		return
	# Holding fire and sliding the same thumb still turns the camera.
	var looking := _looking and index == _look_finger
	if looking or (fire.is_held() and index == fire.finger):
		var player := _player()
		if player != null:
			player.add_mouse_look(slide * LOOK_SENS)


func _apply_move() -> void:
	var v := stick.vector()
	PlayerInput.touch_stick_held = stick.is_held()
	PlayerInput.touch_move = v
	PlayerInput.touch_sprint = stick.sprinting()
	_hold(MOVE_ACTIONS[0], -v.x)
	_hold(MOVE_ACTIONS[1], v.x)
	_hold(MOVE_ACTIONS[2], -v.y)
	_hold(MOVE_ACTIONS[3], v.y)
	_hold("p1_sprint", 1.0 if stick.sprinting() else 0.0)


func _hold(action_name: String, amount: float) -> void:
	if amount > 0.0:
		Input.action_press(action_name, amount)
		_holding[action_name] = true
	elif _holding.has(action_name):
		Input.action_release(action_name)
		_holding.erase(action_name)


func _aim_fire(button: TouchButton) -> void:
	if button != fire:
		return
	var player := _player()
	var golfing := player != null and player.is_golfing()
	fire.actions = PackedStringArray(["p1_swing"] if golfing else ["p1_shoot"])
	for prefix in ["p1", "p2"]:
		Input.action_release("%s_shoot" % prefix)
		Input.action_release("%s_swing" % prefix)


func _note_button(button: TouchButton) -> void:
	for action_name in button.actions:
		PlayerInput.note_tap(action_name.trim_prefix("p1_"))


func _release_stick() -> void:
	stick.release()
	_apply_move()


func _layout() -> void:
	for button in _buttons:
		button.place(size)
	proceed.center = size * 0.5 + Vector2(0.0, size.y * 0.25)


func _stick_center() -> Vector2:
	var reach := _stick_radius()
	return Vector2(reach * 1.8, size.y - reach * 1.8)


func _stick_radius() -> float:
	return clampf(minf(size.x, size.y) * 0.22, 80.0, 130.0)


## Left side of the screen, wide enough for a thumb in landscape.
func _in_move_zone(at: Vector2) -> bool:
	return at.x < size.x * 0.45 or at.distance_to(_stick_center()) <= _stick_radius() * 1.6


func _draw() -> void:
	_layout()
	var center := _stick_center()
	var reach := _stick_radius()
	draw_circle(center, reach, FILL)
	draw_arc(center, reach, 0.0, TAU, 48, RIM, 3.0)
	var knob := stick.tip if stick.is_held() else center
	draw_circle(knob, reach * 0.42, HELD)
	var caption := "MOVE"
	var caption_width := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(
		_font, center + Vector2(-caption_width * 0.5, reach + 22.0), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.ICE
	)
	for button in _buttons:
		if not button.visible:
			continue
		draw_circle(button.center, button.radius, HELD if button.is_held() else FILL)
		draw_arc(button.center, button.radius, 0.0, TAU, 48, RIM, 3.0)
		var font_size := 18 if button.radius >= 50.0 else 13
		var width := _font.get_string_size(button.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			_font, button.center + Vector2(-width * 0.5, font_size * 0.35), button.label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.ICE
		)


func _player() -> Player:
	return _shell.human() if _shell != null else null


func _on_run_ended(won: bool) -> void:
	var score := _shell.flow().score
	DemoEnd.record(won, score.results[0], score.pars[0])


func _strip_mouse_buttons() -> void:
	for prefix in ["p1", "p2"]:
		for suffix in MOUSE_ACTIONS:
			var action_name := "%s_%s" % [prefix, suffix]
			if not InputMap.has_action(action_name):
				continue
			for event in InputMap.action_get_events(action_name):
				if event is InputEventMouseButton:
					InputMap.action_erase_event(action_name, event)
