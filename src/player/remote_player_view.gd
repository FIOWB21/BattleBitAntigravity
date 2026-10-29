# Presentation samples server time independently of the authoritative body.
class_name RemotePlayerView
extends Node3D

@export var capsule_color: Color = Color(0.22, 0.63, 0.88)

var capsule: MeshInstance3D
var interpolator: RemoteInterpolator = RemoteInterpolator.new()
var sampled: PlayerSnapshot = PlayerSnapshot.new()
var weapon_id: int = 0
var flags: int = 0
var weapon_view: WorldWeaponView
var _actor: Player
var _shape: CapsuleMesh
var _aim: MeshInstance3D
var _stance: int = -1
var _spawn_tick: int = -1


func setup(actor: Player) -> void:
	_actor = actor
	visible = not actor.is_local_player or Game.is_dedicated
	if actor.network_owner_id == 0:
		visible = false
		return
	top_level = true
	global_transform = actor.global_transform
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var shape: CapsuleMesh = CapsuleMesh.new()
	shape.height = actor.movement_config.stand_height
	shape.radius = actor.movement_config.capsule_radius
	_shape = shape
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = capsule_color
	capsule = MeshInstance3D.new()
	capsule.mesh = shape
	capsule.material_override = material
	capsule.position.y = shape.height * 0.5
	add_child(capsule)
	_aim = MeshInstance3D.new()
	var marker: BoxMesh = BoxMesh.new()
	marker.size = Vector3(shape.radius, shape.radius * 0.5, shape.radius * 2.0)
	_aim.mesh = marker
	_aim.material_override = material
	add_child(_aim)
	_setup_weapon(actor)
	set_process(not actor.is_local_player and not Game.is_dedicated)


func _setup_weapon(actor: Player) -> void:
	if not actor.is_local_player and not Game.is_dedicated:
		weapon_view = WorldWeaponView.new()
		add_child(weapon_view)
		weapon_view.setup(actor)


func configure(config: SnapshotConfig) -> void:
	interpolator.configure(config, Engine.physics_ticks_per_second)


func push_snapshot(state: PlayerSnapshot) -> void:
	if not _actor.is_local_player and state.tick > _spawn_tick:
		interpolator.push(state)


func reset_for_spawn(pose: Transform3D, tick: int) -> void:
	_spawn_tick = tick
	interpolator.clear()
	global_transform = pose
	_stance = -1
	if weapon_view != null:
		weapon_view.reset()


func _process(delta: float) -> void:
	if not visible or not Net.is_connected:
		return
	var server_tick: float = float(Net.tick) + Engine.get_physics_interpolation_fraction()
	if not multiplayer.is_server():
		if not Net.clock.is_synchronized:
			return
		server_tick = Net.clock.estimated_server_tick(Time.get_ticks_usec())
	present_at(server_tick)
	if weapon_view != null:
		weapon_view.advance(delta)


func present_at(server_tick: float) -> bool:
	if not interpolator.sample_into(server_tick, sampled):
		return false
	global_position = sampled.position
	global_rotation = Vector3(0.0, sampled.yaw, 0.0)
	flags = sampled.flags
	weapon_id = sampled.weapon_id
	var stance: int = flags & PlayerSnapshot.STANCE_MASK
	if stance != _stance:
		_stance = stance
		var height: float = _actor.movement_config.capsule_height_for(stance)
		# Scale the cached mesh: CapsuleMesh cannot be shorter than its diameter.
		capsule.scale.y = height / _shape.height
		capsule.position.y = height * 0.5
	_aim.position = Vector3(0.0, _actor.movement_config.head_height_for(stance), -_shape.radius)
	_aim.rotation.x = sampled.pitch
	if weapon_view != null:
		weapon_view.apply_snapshot(sampled, _actor.movement_config.head_height_for(stance))
	return true


func accepts_shot(tick: int) -> bool:
	return tick > _spawn_tick and not _actor.is_local_player
