class_name PlayerShop
extends RefCounted
## Clubhouse browsing: stations, NPC talk, apparel try-on, and the aisle camera.

const _ShopInspect := preload("res://scripts/shop/shop_inspect.gd")

var inspect
var dressing := false
var dress_saved_yaw := 0.0


func setup(player: Player) -> void:
	inspect = _ShopInspect.new()
	player.add_child(inspect)


func open_doors(player: Player) -> void:
	if player.flow == null or not player.flow.has_shop():
		return
	player.flow.arrive_at_clubhouse()


func open_station(player: Player, station: ShopStation) -> void:
	if station == null or player.flow == null or not player.flow.has_shop():
		return
	stop_talk(player)
	player.shopping = true
	player.shop_choice = 0
	player.shop_dept = station.dept
	Sfx.play("shop_open", player)
	if station.cashier != null:
		station.cashier.address(player)
	begin_inspect(player, station)


func start_talk(player: Player, npc: ClubhouseNpc) -> void:
	if npc == null:
		return
	close_shop(player)
	if player._talk_npc != null and player._talk_npc != npc:
		player._talk_npc.stop_address()
	player._talk_npc = npc
	npc.address(player)
	player.talking = true
	player.talk_name = npc.npc_name
	player.talk_line = npc.next_line()
	Sfx.play("talk", player)


func stop_talk(player: Player) -> void:
	if player._talk_npc != null:
		player._talk_npc.stop_address()
		player._talk_npc = null
	player.talking = false
	player.talk_line = ""


func close_shop(player: Player) -> void:
	end_inspect(player)
	player.shopping = false
	if player.flow == null:
		return
	var house = player.flow.get("clubhouse")
	if house == null or not is_instance_valid(house):
		return
	for station in house.stations:
		if station.cashier != null:
			station.cashier.stop_address()


func trying_on_apparel(player: Player) -> bool:
	return player.shopping and player.shop_dept == Shop.Dept.APPAREL


func begin_inspect(player: Player, station: ShopStation) -> void:
	dressing = true
	dress_saved_yaw = player.look_yaw()
	face_aisle(player, station)
	preview_item(player)


func end_inspect(player: Player) -> void:
	if dressing:
		player.set_look_yaw(dress_saved_yaw)
		dressing = false
	if player.body != null:
		player.body.rotation = Vector3.ZERO
		player.body.clear_try_on()
	if inspect != null:
		inspect.clear()


func face_aisle(player: Player, station: ShopStation) -> void:
	if station == null:
		return
	var aisle := station.global_transform.basis.z
	aisle.y = 0.0
	if aisle.length_squared() < 0.0001:
		return
	aisle = aisle.normalized()
	player.set_look_yaw(wrapf(rad_to_deg(atan2(-aisle.x, -aisle.z)), -180.0, 180.0))
	player.set_look_pitch(0.0)


func preview_item(player: Player) -> void:
	if player.flow == null or not player.flow.has_shop():
		if player.body != null:
			player.body.clear_try_on()
		if inspect != null:
			inspect.clear()
		return
	var item: Dictionary = player.flow.shop_item(player.shop_choice, player.shop_dept)
	if trying_on_apparel(player):
		if inspect != null:
			inspect.clear()
		if player.body != null:
			player.body.rotation = Vector3.ZERO
			player.body.try_on(item)
		return
	if player.body != null:
		player.body.clear_try_on()
		player.body.rotation = Vector3.ZERO
	if inspect != null:
		inspect.show_item(item)


func turn(player: Player, look: Vector2, _delta: float) -> void:
	if inspect == null:
		return
	inspect.spin(look, not trying_on_apparel(player))
	if trying_on_apparel(player) and player.body != null:
		player.body.rotation.y = deg_to_rad(inspect.yaw)


func cycle(player: Player, step := 1) -> void:
	if player.flow == null or not player.flow.has_shop():
		return
	player.shop_choice = posmod(player.shop_choice + step, player.flow.shop_count(player.shop_dept))
	Sfx.play("ui_move", player)
	preview_item(player)


func confirm(player: Player) -> void:
	if player.flow == null or not player.flow.has_shop():
		return
	var item: Dictionary = player.flow.shop_item(player.shop_choice, player.shop_dept)
	if item.is_empty():
		return
	player.flow.buy_shop_item(String(item["id"]), player)


func prompt(player: Player) -> String:
	if player.flow == null or not player.flow.has_shop():
		return ""
	var item: Dictionary = player.flow.shop_item(player.shop_choice, player.shop_dept)
	var browse := player.input.hint("swap_weapon")
	var inspect_hint := player.input.hint("map")
	if String(item.get("kind", "")) == "next":
		return "%s to leave for the next hole   %s to browse" % [
			player.input.hint("interact"), browse
		]
	if player.flow.shop_owned(String(item["id"]), player):
		return "%s   owned   %s to browse   %s to turn   %s for info" % [
			String(item["name"]), browse, player.input.hint("look"), inspect_hint
		]
	if not player.flow.shop_can_buy(String(item["id"]), player):
		return "%s   %s   %s to browse   %s to turn   %s for info" % [
			String(item["name"]), GameState.format_money(int(item["price"])),
			browse, player.input.hint("look"), inspect_hint
		]
	return "%s to buy %s  %s   %s to browse   %s to turn   %s for info" % [
		player.input.hint("interact"), String(item["name"]),
		GameState.format_money(int(item["price"])), browse,
		player.input.hint("look"), inspect_hint
	]


func view_transform(player: Player) -> Transform3D:
	return _ShopInspect.view_transform(player.global_position, player.look_yaw())


func cam_fov() -> float:
	return _ShopInspect.CAM_FOV
