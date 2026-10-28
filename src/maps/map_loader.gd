class_name MapLoader
extends Node3D

signal map_loaded(map_id: String)
signal map_failed(reason: String)

@export var maps: Array[MapData] = [preload("res://src/maps/testbed/network_testbed.tres")]

var current_map: Node3D
var current_data: MapData
var spawn_pose: Transform3D
var players: NetworkPlayers


func _ready() -> void:
	players = NetworkPlayers.new()
	players.name = "NetworkPlayers"
	players.loader = self
	add_child(players)
	Net.connected_to_server.connect(_on_connected)
	Net.disconnected.connect(unload_map)


func find_map(map_id: String) -> MapData:
	for data: MapData in maps:
		if data != null and String(data.id) == map_id:
			return data
	return null


func load_map(map_id: String) -> Error:
	var data: MapData = find_map(map_id)
	if data == null or not data.is_valid():
		map_failed.emit("unknown_or_invalid_map: " + map_id)
		return ERR_DOES_NOT_EXIST
	if current_map != null:
		return OK if current_data == data else ERR_ALREADY_IN_USE
	var candidate: Node = data.scene.instantiate()
	var marker: Marker3D = candidate.get_node_or_null(data.spawn_path) as Marker3D
	if not candidate is Node3D or marker == null:
		candidate.free()
		map_failed.emit("missing_player_spawn: " + map_id)
		return ERR_INVALID_DATA
	for path: NodePath in data.offline_paths:
		var offline: Node = candidate.get_node_or_null(path)
		if offline != null:
			offline.free()
	current_data = data
	current_map = candidate as Node3D
	current_map.name = "Map"
	add_child(current_map)
	spawn_pose = marker.global_transform
	Game.set_state(Game.State.IN_GAME)
	map_loaded.emit(map_id)
	return OK


func unload_map() -> void:
	players.clear()
	if current_map != null:
		remove_child(current_map)
		current_map.queue_free()
	current_map = null
	current_data = null
	Game.set_state(Game.State.MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_connected() -> void:
	if load_map(Game.map_id) != OK:
		Net.disconnect_with_error.call_deferred("map_load_failed")
		return
	players.map_ready.rpc_id(Net.SERVER_ID, Game.map_id)
