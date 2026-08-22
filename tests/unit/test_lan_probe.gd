extends GutTest
## LAN reachability on one machine. If these pass while two Macs still cannot
## join, the packets are being dropped outside the game and the netcode is not
## the thing to change.

const PORT := 47801


func test_the_probe_port_sits_beside_the_game_port() -> void:
	assert_eq(LanProbe.probe_port(NetSession.DEFAULT_PORT), 7778, "never the game port")


func test_enet_completes_a_loopback_handshake() -> void:
	var server := ENetMultiplayerPeer.new()
	server.set_bind_ip("0.0.0.0")
	assert_eq(server.create_server(PORT, 7), OK, "the host must bind on IPv4")
	var client := ENetMultiplayerPeer.new()
	assert_eq(client.create_client("127.0.0.1", PORT), OK)
	var connected := await _handshake(server, client)
	server.close()
	client.close()
	assert_true(connected, "ENet must connect over loopback")


func test_the_probe_answers_over_loopback() -> void:
	var host := _probe()
	assert_eq(host.serve(PORT), OK)
	var joiner := _probe()
	assert_eq(joiner.probe("127.0.0.1", PORT), OK)
	await wait_for_signal(joiner.answered, 2.0)
	assert_false(joiner.is_probing(), "an answered probe closes itself")


func test_the_probe_gives_up_when_nothing_answers() -> void:
	var joiner := _probe()
	joiner.wait_seconds = 0.2
	assert_eq(joiner.probe("127.0.0.1", PORT + 40), OK, "sending never blocks")
	await wait_for_signal(joiner.gave_up, 2.0)
	assert_false(joiner.is_probing(), "a silent probe closes itself")


func test_serving_twice_keeps_one_socket() -> void:
	var host := _probe()
	assert_eq(host.serve(PORT), OK)
	assert_eq(host.serve(PORT), OK, "re-hosting frees the old bind first")
	assert_true(host.is_serving())
	host.stop_serving()
	assert_false(host.is_serving())


func _probe() -> LanProbe:
	var node := LanProbe.new()
	add_child_autofree(node)
	return node


func _handshake(server: MultiplayerPeer, client: MultiplayerPeer) -> bool:
	for _frame in 240:
		server.poll()
		client.poll()
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			return true
		await get_tree().process_frame
	return false
