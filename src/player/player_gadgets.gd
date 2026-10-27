# Ввод и состояние слотов уже существуют в PlayerInput/Inventory; ОС здесь не опрашивается.
class_name PlayerGadgets
extends Node

var _player: Player
var _gadgets: Dictionary[int, Gadget] = {}
var _placement: GroundDeployment = GroundDeployment.new()
var _ctx: GadgetContext = GadgetContext.new()
var _exclude: Array[RID] = []
var _last_tick: int = -1
var _fire_held: bool = false


func setup(player: Player) -> void:
	_player = player
	_ctx.spawn_parent = player.get_parent() as Node3D
	_ctx.source_id = player.get_multiplayer_authority()
	_exclude = player.get_hitscan_exclude_rids().duplicate()
	if not _exclude.has(player.get_rid()):
		_exclude.append(player.get_rid())
	if not LoadoutValidator.validate(player.class_data, player.inventory.loadout).is_empty():
		return
	for slot: int in [Loadout.Slot.GADGET_1, Loadout.Slot.GADGET_2]:
		var profile: GadgetData = player.inventory.loadout.item_at(slot) as GadgetData
		if profile == null or not profile.is_valid():
			continue
		var gadget: Gadget = Gadget.new()
		gadget.data = profile
		add_child(gadget)
		_gadgets[slot] = gadget


func gadget_at(slot: int) -> Gadget:
	return _gadgets.get(slot) as Gadget


func simulate(inp: PlayerInput) -> void:
	if not Game.is_server_or_offline(multiplayer) or inp.tick <= _last_tick:
		return
	_last_tick = inp.tick
	var fire: bool = inp.pressed(PlayerInput.BTN_FIRE)
	var pressed: bool = fire and not _fire_held
	_fire_held = fire
	for slot: int in _gadgets:
		_gadgets[slot].simulate(inp.tick)
	var active: Gadget = gadget_at(_player.inventory.active_slot)
	if active == null or not _can_act():
		return
	if inp.pressed(PlayerInput.BTN_RELOAD):
		active.reload(inp.tick)
	if not pressed or not active.can_use():
		return
	if not _placement.solve(_player.get_world_3d().direct_space_state,
			_player.global_position, inp.yaw, active.data.placement, _exclude):
		return
	_ctx.tick = inp.tick
	_ctx.spawn_transform = _placement.pose
	active.use(_ctx)


func _can_act() -> bool:
	return not (_player.health_component as HealthComponent).is_dead \
		and not _player.equipment.melee.busy and not _player.motor.is_sprinting \
		and _player.inventory.phase == Inventory.Phase.READY
