# Общие параметры гранат и реактивных снарядов; косметика не участвует в уроне.
class_name ProjectileData
extends Resource

enum Kind { FRAG, SMOKE, FLASH, ROCKET }

@export var id: StringName = &"frag"
@export var kind: Kind = Kind.FRAG
@export var gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
@export_range(0.0, 10.0) var drag: float = 0.08
@export var speed: float = 16.0
@export var upward_speed: float = 3.0
@export var fuse: float = 3.0
@export var impact_detonation: bool = false
@export_range(0.0, 1.0) var restitution: float = 0.5
@export_range(0.0, 1.0) var friction: float = 0.2
@export var rest_speed: float = 0.8
@export_range(0.0, 1.0) var rest_min_up_dot: float = 0.5
@export var contact_offset: float = 0.01
@export var max_contacts: int = 4
@export_flags_3d_physics var collision_mask: int = 1 | 2 | 16 | 64
@export_flags_3d_physics var occlusion_mask: int = 1 | 16 | 64
@export var radius: float = 8.0
@export var damage: float = 150.0
@export var throw_interval: float = 0.8
@export var effect_duration: float = 0.5
@export var sensory_duration: float = 3.0
@export var color: Color = Color(0.9, 0.4, 0.08)


func damage_at(distance: float, visible_to_blast: bool = true) -> float:
	if not visible_to_blast or radius <= 0.0 or not is_finite(distance):
		return 0.0
	return maxf(damage, 0.0) * clampf(1.0 - maxf(distance, 0.0) / radius, 0.0, 1.0)
