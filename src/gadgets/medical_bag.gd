# Обычное лечение всех живых целей; раненые не реанимируются.
class_name MedicalBag
extends Deployable

signal healed(health: HealthComponent, amount: float)

const TIME_EPSILON: float = 0.000001

@export var config: MedicalBagConfig

var remaining: float = 0.0
@onready var aura: GadgetAura = $Aura


func _ready() -> void:
	if config != null and config.is_valid():
		remaining = config.lifetime
		aura.set_radius(config.radius)


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if not is_inside_tree() or not Game.is_server_or_offline(multiplayer) or _despawned:
		return
	if config == null or not config.is_valid() or not is_finite(delta) or delta <= 0.0:
		return
	var elapsed: float = minf(delta, remaining)
	remaining = maxf(0.0, remaining - elapsed)
	for health: HealthComponent in aura.targets:
		if not is_instance_valid(health):
			continue
		if not aura.contains_target(health, global_position, config.radius) or health.current >= health.max_health:
			continue
		var before: float = health.current
		health.heal(config.heal_per_second * elapsed)
		healed.emit(health, health.current - before)
	if remaining <= TIME_EPSILON:
		despawn()
