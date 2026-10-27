# Один активный ящик на серверную сущность владельца в текущем мире.
class_name AmmoCrate
extends Deployable

signal supplied(player: Player, rounds: int, grenades: int)

const ACTIVE_GROUP: StringName = &"active_ammo_crates"
const TIME_EPSILON: float = 0.000001

@export var config: AmmoCrateConfig

var _elapsed: float = 0.0
@onready var aura: GadgetAura = $Aura


func _ready() -> void:
	if config == null or not config.is_valid():
		return
	aura.set_radius(config.radius)
	if not Game.is_server_or_offline(multiplayer):
		return
	# Поиск выполняется при деплое, а не в кадровом цикле; разные миры изолированы.
	for node: Node in get_tree().get_nodes_in_group(ACTIVE_GROUP):
		var previous: AmmoCrate = node as AmmoCrate
		if previous != null and previous.get_parent() == get_parent() \
				and owner_id > 0 and previous.owner_id == owner_id:
			previous.visible = false
			previous.despawn()
	add_to_group(ACTIVE_GROUP)


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if not is_inside_tree() or not Game.is_server_or_offline(multiplayer) or _despawned:
		return
	if config == null or not config.is_valid() or not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta
	var pulses: int = floori((_elapsed + TIME_EPSILON) / config.interval)
	if pulses <= 0:
		return
	_elapsed = maxf(0.0, _elapsed - pulses * config.interval)
	for health: HealthComponent in aura.targets:
		if not is_instance_valid(health) or not aura.contains_target(health, global_position, config.radius):
			continue
		var player: Player = aura.targets[health] as Player
		if player != null:
			_supply(player, pulses)


func _supply(player: Player, pulses: int) -> void:
	var rounds: int = 0
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		var weapon: Weapon = player.inventory.weapon_at(slot)
		if weapon != null:
			rounds += weapon.add_reserve_ammo(mini(weapon.reserve_capacity(),
				floori(weapon.reserve_capacity() * config.ammo_fraction) * pulses))
	var stock: GrenadeStockConfig = player.equipment.projectiles.stock
	var grenades: int = 0
	if stock != null and stock.is_valid():
		grenades = player.equipment.projectiles.add_grenades(
			mini(stock.capacity, config.grenades_per_pulse * pulses))
	if rounds > 0 or grenades > 0:
		supplied.emit(player, rounds, grenades)
