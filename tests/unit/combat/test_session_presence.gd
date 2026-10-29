extends "res://tests/unit/combat/combat_fixture.gd"


func after_each() -> void:
	Net.session.clear()
	Net.nicknames.erase(42)
	super.after_each()


func test_departure_preserves_last_server_team_and_removes_all_actor_records() -> void:
	Net.session.admit(42, "Returning")
	actor.team_id = 2
	players.ready_peers[42] = true
	players._peer_left(42)
	assert_eq(actor.process_mode, Node.PROCESS_MODE_DISABLED)
	await get_tree().process_frame
	Net.session.forget(42)
	assert_eq(Net.session.team_for("RETURNING"), 2)
	assert_false(players.actors.has(42))
	assert_false(players.ready_peers.has(42))
	assert_false(players._slots.has(42))
	assert_true(players.lag_compensator.tracks.is_empty())
	assert_true(players.snapshots._actors.is_empty())
	assert_true(players.respawns.deadlines.is_empty())
	var returned: Player = players._spawn_player({"peer_id": 43, "pose": loader.spawn_pose,
		"team_id": Net.session.team_for("returning")}) as Player
	players._container.add_child(returned)
	assert_eq(returned.team_id, 2)
	assert_eq(returned.affiliation.team_id, 2, "Team exists before Player._ready configures affiliation")


func test_duplicate_departure_does_not_repeat_peer_left_or_lose_team() -> void:
	Net.session.admit(42, "Returning")
	Net.nicknames[42] = "Returning"
	actor.team_id = 3
	var departed: Array[int] = []
	var callback: Callable = func(peer: int) -> void: departed.append(peer)
	Net.peer_left.connect(callback)
	Net._revoke(42)
	Net._revoke(42)
	assert_eq(departed, [42])
	assert_eq(Net.session.team_for("Returning"), 3)
	assert_false(Net.nicknames.has(42))
	Net.peer_left.disconnect(callback)
	await get_tree().process_frame
