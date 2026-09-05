class_name PlayerShop
extends RefCounted
## Clubhouse browsing: stations, NPC talk, and the item inspect camera.

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
	player.velocity = Vector3.ZERO
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
	if player.body != null:
		player.body.clear_try_on()
		player.body.rotation = Vector3.ZERO
	if player.flow == null or not player.flow.has_shop():
		if inspect != null:
			inspect.clear()
		return
	if inspect != null:
		inspect.show_item(player.flow.shop_item(player.shop_choice, player.shop_dept))


func turn(player: Player, look: Vector2, _delta: float) -> void:
	if inspect == null:
		return
	inspect.spin(look)


func cycle(player: Player, step := 1) -> void:
	if player.flow == null or not player.flow.has_shop():
		return
	var count: int = player.flow.shop_count(player.shop_dept)
	if count <= 0:
		return
	player.shop_choice = posmod(player.shop_choice + step, count)
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
	var browse := _browse_tail(player)
	if item.is_empty():
		return browse
	if String(item.get("kind", "")) == "next":
		return "%s to leave for the next hole   %s" % [player.input.hint("interact"), browse]
	if player.flow.shop_owned(String(item["id"]), player):
		return "%s   owned   %s" % [String(item["name"]), browse]
	if not player.flow.shop_can_buy(String(item["id"]), player):
		return "%s   %s   %s" % [
			String(item["name"]), GameState.format_money(int(item["price"])), browse
		]
	return "%s to buy %s  %s   %s" % [
		player.input.hint("interact"), String(item["name"]),
		GameState.format_money(int(item["price"])), browse
	]


func view_transform(player: Player) -> Transform3D:
	var target := player.global_position + Vector3.UP * _ShopInspect.HOLD.y
	if inspect != null and is_instance_valid(inspect):
		target = inspect.global_position
	return _ShopInspect.view_transform(target, player.look_yaw())


func _browse_tail(player: Player) -> String:
	return "%s to browse   %s to turn   %s for info   %s to leave" % [
		player.input.hint("swap_weapon"), player.input.hint("look"),
		player.input.hint("map"), player.input.hint("swap_gear"),
	]


func cam_fov() -> float:
	return _ShopInspect.CAM_FOV
