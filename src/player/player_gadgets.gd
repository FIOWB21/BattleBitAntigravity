# Ввод и состояние слотов уже существуют в PlayerInput/Inventory; ОС здесь не опрашивается.
class_name PlayerGadgets
extends Node

var _player: Player
var _gadgets: Dictionary[int, Gadget] = {}
var _tools: Dictionary[int, RepairTool] = {}
var _placement: GroundDeployment = GroundDeployment.new()
var _ctx: GadgetContext = GadgetContext.new()
var _exclude: Array[RID] = []
var _last_tick: int = -1
var _fire_held: bool = false
var _aim_held: bool = false
var charges: ChargeControl
var spots: SpotRegistry
var markers: SpotMarkers
var _spotter: SpottingDevice
var _held_view: GadgetHeldView
var launcher: GadgetLauncher
var launcher_view: LauncherStockView


func setup(player: Player) -> void:
	_player = player
	_ctx.spawn_parent = player.get_parent() as Node3D
	_ctx.source_id = player.get_multiplayer_authority()
	_ctx.owner_id = player.get_instance_id()
	_setup_spots(player)
	launcher = GadgetLauncher.new()
	add_child(launcher)
	_exclude = player.get_hitscan_exclude_rids().duplicate()
	charges = ChargeControl.new()
	add_child(charges)
	if player.equipment.projectiles.effects != null:
		charges.exploded.connect(player.equipment.projectiles.effects.present)
	if not _exclude.has(player.get_rid()):
		_exclude.append(player.get_rid())
	if not LoadoutValidator.validate(player.class_data, player.inventory.loadout).is_empty():
		return
	for slot: int in [Loadout.Slot.GADGET_1, Loadout.Slot.GADGET_2]:
		var profile: GadgetData = player.inventory.loadout.item_at(slot) as GadgetData
		if profile == null or not profile.is_valid():
			continue
		if profile is RepairToolData:
			_setup_repair(slot, profile as RepairToolData)
			continue
		var gadget: Gadget = Gadget.new()
		gadget.data = profile
		add_child(gadget)
		gadget.deployable_created.connect(charges.track)
		_gadgets[slot] = gadget
	if player.is_local_player and not Game.is_dedicated:
		_held_view = GadgetHeldView.new()
		player.camera.add_child(_held_view)
		_held_view.setup(player)
		launcher_view = LauncherStockView.new()
		add_child(launcher_view)
		launcher_view.setup(player)


func _setup_spots(player: Player) -> void:
	spots = SpotRegistry.for_world(player.get_parent())
	_spotter = SpottingDevice.new()
	add_child(_spotter)
	if player.is_local_player and not Game.is_dedicated:
		markers = SpotMarkers.new()
		add_child(markers)
		markers.setup(spots, player.affiliation, player.camera)


func _physics_process(delta: float) -> void:
	spots.advance(delta, Engine.get_physics_frames())


func gadget_at(slot: int) -> Gadget:
	return _gadgets.get(slot) as Gadget


func tool_at(slot: int) -> RepairTool:
	return _tools.get(slot) as RepairTool


func _setup_repair(slot: int, profile: RepairToolData) -> void:
	var tool: RepairTool = RepairTool.new()
	tool.data = profile
	add_child(tool)
	tool.setup(_exclude)
	_tools[slot] = tool
	if _player.is_local_player and not Game.is_dedicated:
		tool.view = RepairToolView.new()
		_player.camera.add_child(tool.view)
		tool.view.setup(tool)


func simulate(inp: PlayerInput) -> void:
	if not Game.is_server_or_offline(multiplayer) or inp.tick <= _last_tick:
		return
	_last_tick = inp.tick
	var fire: bool = inp.pressed(PlayerInput.BTN_FIRE)
	var pressed: bool = fire and not _fire_held
	_fire_held = fire
	var aimed: bool = inp.pressed(PlayerInput.BTN_AIM)
	var detonate_pressed: bool = aimed and not _aim_held
	_aim_held = aimed
	for slot: int in _gadgets:
		_gadgets[slot].simulate(inp.tick)
	_simulate_tools(inp)
	if _held_view != null:
		_held_view.set_active(_can_act())
	var active: Gadget = gadget_at(_player.inventory.active_slot)
	if active == null or not _can_act():
		return
	if detonate_pressed and active.data.id in [&"mine", &"c4"]:
		charges.detonate(_ctx.owner_id)
		return
	if inp.pressed(PlayerInput.BTN_RELOAD):
		active.reload(inp.tick)
	if not pressed or not active.can_use():
		return
	_use(active, inp)


func _use(active: Gadget, inp: PlayerInput) -> void:
	_ctx.tick = inp.tick
	_ctx.team_id = _player.affiliation.team_id
	_ctx.squad_id = _player.affiliation.squad_id
	if active.data is SpottingData:
		_spotter.use(active, _ctx, _player.affiliation, _aim(inp), spots, _exclude)
		return
	if active.data is LauncherGadgetData:
		launcher.fire(active, _ctx, _aim(inp), _player.equipment.projectiles.system, _exclude)
		return
	if not _placement.solve(_player.get_world_3d().direct_space_state,
			_player.global_position, inp.yaw, active.data.placement, _exclude):
		return
	_ctx.tick = inp.tick
	_ctx.spawn_transform = _placement.pose
	active.use(_ctx)


func _aim(inp: PlayerInput) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(_player.head.rotation.x,
		inp.yaw, _player.head.rotation.z)), _player.head.global_position)


func _simulate_tools(inp: PlayerInput) -> void:
	if _tools.is_empty():
		return
	var aim: Transform3D = Transform3D(Basis.from_euler(Vector3(
		_player.head.rotation.x, inp.yaw, _player.head.rotation.z)), _player.head.global_position)
	for slot: int in _tools:
		var allowed: bool = _player.inventory.active_slot == slot and _can_act()
		_tools[slot].simulate(inp, aim, allowed)
		if _tools[slot].view != null:
			_tools[slot].view.set_active(allowed)


func _can_act() -> bool:
	return not (_player.health_component as HealthComponent).is_dead \
		and not _player.equipment.melee.busy and not _player.motor.is_sprinting \
		and _player.inventory.phase == Inventory.Phase.READY
