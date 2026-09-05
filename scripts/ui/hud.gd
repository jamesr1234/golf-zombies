class_name Hud
extends CanvasLayer
## One HUD per split-screen half. Polls its own player so nothing has to be
## re-wired when a player goes down, starts golfing or swaps weapons.

const LOW_HEALTH := 0.45
const DOWNED_TINT := Color(0.55, 0.02, 0.35, 0.38)
const HURT_TINT := Color(0.45, 0.0, 0.3, 0.22)
const HIT_FLASH := Color(0.95, 0.04, 0.08, 0.7)
const UNDERWATER_TINT := Color(0.02, 0.18, 0.42, 0.4)
const REVIVE_TINT := Palette.LIME
const BLEED_TINT := Palette.MAGENTA
const DRUNK_SHADER := preload("res://assets/shaders/drunk_vision.gdshader")
const CALLOUT_TIME := 1.35
const SWEET_CALLOUT := "Nice shot!"

@onready var score_label: Label = $Root/Score
@onready var timer_label: Label = $Root/Timer
@onready var money_label: Label = $Root/Money
@onready var ammo_label: Label = $Root/Ammo
@onready var prompt_label: Label = $Root/Prompt
@onready var health_bar: ProgressBar = $Root/HealthBar
@onready var status_bar: ProgressBar = $Root/StatusBar
@onready var crosshair: Control = $Root/Crosshair
@onready var vignette: ColorRect = $Root/Vignette
@onready var swing_meter: SwingMeterUi = $Root/SwingMeter
@onready var message: Control = $Root/Message
@onready var message_title: Label = $Root/Message/Panel/Lines/Title
@onready var message_body: Label = $Root/Message/Panel/Lines/Body
@onready var shop_panel: Control = $Root/Shop
@onready var shop_title: Label = $Root/Shop/Panel/Lines/Title
@onready var shop_body: Label = $Root/Shop/Panel/Lines/Body
@onready var hole_map: HoleMap = $Root/HoleMap
@onready var board_hud: PokerBoardHud = $Root/PokerBoard
@onready var poker_result: PokerResultHud = $Root/PokerResult
@onready var poker_act: PokerActHud = $Root/PokerAct

var player: Player
var flow
var _fade: ColorRect
var _drunk: ColorRect
var _drunk_mat: ShaderMaterial
var _shop_info_shown := false
var _callout_left := 0.0
var _sweet_golf: GolfController


func _ready() -> void:
	add_to_group("hud")
	HudStyle.apply(self)
	_fade = ColorRect.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	$Root.add_child(_fade)
	_drunk_mat = ShaderMaterial.new()
	_drunk_mat.shader = DRUNK_SHADER
	_drunk = ColorRect.new()
	_drunk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drunk.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drunk.material = _drunk_mat
	_drunk.visible = false
	$Root.add_child(_drunk)
	$Root.move_child(_drunk, 0)


func cover_black() -> void:
	if _fade == null:
		return
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)


func reveal() -> void:
	if _fade == null:
		return
	var fade := _fade
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.45)


func setup(p_player: Player, p_flow) -> void:
	player = p_player
	flow = p_flow
	if flow.has_signal("message_changed") and not flow.message_changed.is_connected(show_message):
		flow.message_changed.connect(show_message)
	message.visible = false


func show_message(title: String, body: String, shown: bool) -> void:
	message.visible = shown
	message_title.text = HudStyle.chrome(title)
	message_body.text = body


func flash_callout(title: String) -> void:
	show_message(title, "", true)
	_callout_left = CALLOUT_TIME


func _process(delta: float) -> void:
	_tick_callout(delta)
	if player == null or flow == null:
		return
	score_label.text = HudStyle.chrome(flow.scorecard_text())
	if flow.has_method("scoreboard_text"):
		var board: String = flow.scoreboard_text()
		if board != "":
			score_label.text = HudStyle.chrome(flow.scorecard_text() + "\n" + board)
	_update_timer()
	_update_money()
	_update_vitals()
	_update_weapon()
	_update_golf()
	_update_shop()
	_update_board()
	_update_act()
	_update_map()
	_update_drunk()
	prompt_label.text = HudStyle.chrome(player.get_prompt())


func _update_vitals() -> void:
	var health := player.health
	if player.is_in_mech() and player.mech != null:
		health_bar.value = player.mech.hp_fraction() * 100.0
	else:
		health_bar.value = health.fraction() * 100.0
	if health.is_downed():
		status_bar.visible = true
		if health.revive_progress > 0.0:
			status_bar.value = health.revive_fraction() * 100.0
			status_bar.modulate = REVIVE_TINT
		else:
			status_bar.value = health.bleed_fraction() * 100.0
			status_bar.modulate = BLEED_TINT
	else:
		status_bar.visible = false
	if health.is_downed():
		vignette.visible = true
		vignette.color = DOWNED_TINT
	elif player.is_hit_flashing():
		vignette.visible = true
		vignette.color = HIT_FLASH
	elif player.is_underwater():
		vignette.visible = true
		vignette.color = UNDERWATER_TINT
	elif health.fraction() < LOW_HEALTH:
		vignette.visible = true
		vignette.color = HURT_TINT
	else:
		vignette.visible = false


func _update_weapon() -> void:
	if player.is_in_mech() and player.mech != null and not player.is_golfing():
		var suit: MechSuit = player.mech
		if suit.is_reloading():
			ammo_label.text = HudStyle.chrome("Mech   reloading   HP %d/8" % suit.hp)
		else:
			ammo_label.text = HudStyle.chrome("Mech   %d / 8   HP %d/8" % [
				suit.shells(), suit.hp
			])
		return
	if player.is_placing():
		var held := 0
		var card = player.wallet() if player.has_method("wallet") else flow.score
		var gear := "Barrier"
		if card != null:
			if player.place.kind == "ladder":
				gear = "Ladder"
				held = card.ladder_charges
			else:
				held = card.barrier_charges
		var weapon := player.weapon
		var current := weapon.stats()
		if current == null:
			ammo_label.text = HudStyle.chrome("%s x%d" % [gear, held])
		else:
			ammo_label.text = HudStyle.chrome("%s   %d / %d   %s x%d" % [
				current.display_name, weapon.mag(), weapon.reserve(), gear, held
			])
		return
	var extra := ""
	if player.buzz.held > 0 and not player.is_holding_beer():
		extra += "   Beer x%d" % player.buzz.held
	if (
		player.cart != null and player.cart.passenger == player and player.cart.mines > 0
		and not player.is_holding_mines()
	):
		extra += "   Mines x%d" % player.cart.mines
	if player.buzz.active() > 0:
		extra += "   Buzz x%d" % player.buzz.active()
	if player.is_holding_mines() and player.cart != null:
		ammo_label.text = HudStyle.chrome("Mines x%d%s" % [player.cart.mines, extra])
		return
	if player.is_holding_beer():
		ammo_label.text = HudStyle.chrome("Beer   x%d%s" % [player.buzz.held, extra])
		return
	var weapon := player.weapon
	var current := weapon.stats()
	if current == null:
		ammo_label.text = HudStyle.chrome(extra.strip_edges())
		return
	if weapon.is_scoped():
		extra = "   %dx%s" % [roundi(weapon.zoom_mult()), extra]
	if weapon.is_reloading():
		ammo_label.text = HudStyle.chrome("%s   reloading%s" % [current.display_name, extra])
	else:
		ammo_label.text = HudStyle.chrome("%s %d/%d   %d / %d%s" % [
			current.display_name,
			weapon.index + 1,
			weapon.loadout.size(),
			weapon.mag(),
			weapon.reserve(),
			extra,
		])


func _update_golf() -> void:
	var golfing := player.is_golfing()
	crosshair.visible = (
		not golfing and player.health.is_alive()
		and not player.shopping and not player.talking and not player.wants_map()
		and not player.is_swimming() and not player.is_placing()
		and not player.is_poker_seated()
	)
	swing_meter.visible = golfing
	if player.golf != null:
		_listen_sweet(player.golf)
	if golfing:
		swing_meter.meter = player.golf.meter
		swing_meter.putting = (
			player.golf.ball != null and player.golf.ball.is_putting()
		)
		swing_meter.queue_redraw()
		if swing_meter.putting:
			ammo_label.text = HudStyle.chrome(golf_club_text(true))


func _tick_callout(delta: float) -> void:
	if _callout_left <= 0.0:
		return
	_callout_left = maxf(0.0, _callout_left - delta)
	if _callout_left <= 0.0 and message_title.text == HudStyle.chrome(SWEET_CALLOUT):
		show_message("", "", false)


func _listen_sweet(golf: GolfController) -> void:
	if _sweet_golf == golf:
		return
	if _sweet_golf != null and is_instance_valid(_sweet_golf):
		if _sweet_golf.sweet_struck.is_connected(_on_sweet_struck):
			_sweet_golf.sweet_struck.disconnect(_on_sweet_struck)
	_sweet_golf = golf
	if not golf.sweet_struck.is_connected(_on_sweet_struck):
		golf.sweet_struck.connect(_on_sweet_struck)


func _on_sweet_struck() -> void:
	flash_callout(SWEET_CALLOUT)


static func golf_club_text(putting: bool) -> String:
	return "Putter" if putting else ""


## Parked on the full clock during warm-up, so you can see what you are about to
## start before you step on the tee.
func _update_timer() -> void:
	var poker_t := player.poker.timer_left(player) if player.has_method("is_poker_seated") else -1.0
	if poker_t >= 0.0:
		timer_label.visible = true
		timer_label.text = HudStyle.chrome(GameState.format_clock(poker_t))
		var color := Palette.ICE
		if poker_t <= 10.0:
			color = Palette.MAGENTA
		elif poker_t <= 30.0:
			color = Palette.AMBER
		timer_label.label_settings.font_color = color
		timer_label.label_settings.shadow_color = Color(color, HudStyle.GLOW_ALPHA)
		return
	var show: bool = true
	if flow.has_method("shows_timer"):
		show = bool(flow.shows_timer())
	else:
		show = not flow.finished and (not flow.is_between_holes() or flow.phase == 0)
	if not show:
		timer_label.visible = false
		return
	timer_label.visible = true
	timer_label.text = HudStyle.chrome(GameState.format_clock(flow.hole_time_left))
	var color := Palette.ICE
	if flow.hole_time_left <= 10.0:
		color = Palette.MAGENTA
	elif flow.hole_time_left <= 30.0:
		color = Palette.AMBER
	timer_label.label_settings.font_color = color
	timer_label.label_settings.shadow_color = Color(color, HudStyle.GLOW_ALPHA)


func _update_money() -> void:
	if player.poker != null:
		money_label.text = HudStyle.chrome(GameState.format_money(player.poker.shown_cash(player)))
		return
	var card = player.wallet() if player.has_method("wallet") else flow.score
	if card != null:
		money_label.text = HudStyle.chrome(GameState.format_money(card.money))


func _update_shop() -> void:
	if poker_result != null:
		poker_result.refresh(player)
	if player.talking:
		_shop_info_shown = false
		shop_panel.visible = true
		message.visible = false
		if poker_result != null:
			poker_result.visible = false
		shop_title.text = HudStyle.chrome(player.talk_name)
		shop_body.text = HudStyle.chrome(player.talk_line)
		return
	if player.poker.showing_result():
		_shop_info_shown = false
		shop_panel.visible = false
		message.visible = false
		return
	if player.poker.shows_panel(player):
		_shop_info_shown = false
		shop_panel.visible = true
		message.visible = false
		shop_title.text = HudStyle.chrome("Hold'em")
		shop_body.text = HudStyle.chrome(player.poker.panel_text(player))
		return
	var open: bool = player.shopping and flow.has_shop()
	shop_panel.visible = open
	if not open:
		_shop_info_shown = false
		return
	message.visible = false
	var inspect := player.wants_shop_info()
	if inspect and not _shop_info_shown:
		Sfx.play("map_open", self)
	_shop_info_shown = inspect
	shop_title.text = HudStyle.chrome(flow.shop_title(player.shop_dept))
	var body: String = flow.shop_details(
		player.shop_choice, player.shop_dept, player
	) if inspect else flow.shop_listing(player.shop_choice, player.shop_dept, player)
	shop_body.text = HudStyle.chrome(body)


func _update_board() -> void:
	if board_hud == null:
		return
	if player.poker.showing_result():
		board_hud.visible = false
		return
	board_hud.refresh(player)


func _update_act() -> void:
	if poker_act == null:
		return
	if player.talking or player.poker.showing_result():
		poker_act.visible = false
		return
	poker_act.refresh(player)


func _update_map() -> void:
	var show: bool = player.wants_map() and flow.hole != null
	if show and not hole_map.visible:
		Sfx.play("map_open", self)
	hole_map.visible = show
	if not show:
		return
	hole_map.hole = flow.hole
	hole_map.you = player.global_position
	hole_map.you_color = player.body_color
	hole_map.has_ball = false
	var owned: GolfBall = player.golf.ball if player.golf != null else null
	if owned == null:
		owned = flow.ball as GolfBall
	if owned != null:
		hole_map.has_ball = true
		hole_map.ball = owned.global_position
	hole_map.queue_redraw()


func _update_drunk() -> void:
	if _drunk == null or _drunk_mat == null:
		return
	var show := player.wants_drunk_fx()
	_drunk.visible = show
	if not show:
		return
	_drunk_mat.set_shader_parameter("blur_px", player.buzz.blur_amount())
	_drunk_mat.set_shader_parameter("split", player.buzz.split_amount())
	_drunk_mat.set_shader_parameter("tint", clampf(float(player.buzz.extra_beers()) * 0.12, 0.0, 0.55))
