# Параметры короткого удара и его отдельного косметического представления.
class_name MeleeData
extends Resource

@export var id: StringName = &"knife"
@export_range(0.1, 3.0) var reach: float = 1.5
@export var damage: float = 50.0
@export var hit_delay: float = 0.2
@export var duration: float = 0.7
@export var interval: float = 0.8
@export_range(0.0, 1.0) var rear_dot: float = 0.5
@export var rest_offset: Vector3 = Vector3(0.28, -0.28, -0.48)
@export var windup_offset: Vector3 = Vector3(0.38, -0.18, -0.32)
@export var strike_offset: Vector3 = Vector3(-0.08, -0.08, -0.85)
@export var windup_rotation: Vector3 = Vector3(0.3, -0.3, -0.6)
@export var strike_rotation: Vector3 = Vector3(-0.4, 0.2, 0.5)
@export var blade_size: Vector3 = Vector3(0.045, 0.012, 0.26)
@export var grip_size: Vector3 = Vector3(0.045, 0.04, 0.12)
@export var blade_color: Color = Color(0.7, 0.74, 0.78)
@export var grip_color: Color = Color(0.12, 0.16, 0.12)
@export var viewmodel_fov: float = 75.0


func is_backstab(attacker_position: Vector3, target: Transform3D) -> bool:
	var toward_attacker: Vector3 = attacker_position - target.origin
	toward_attacker.y = 0.0
	var forward: Vector3 = -target.basis.z
	forward.y = 0.0
	if toward_attacker.is_zero_approx() or forward.is_zero_approx():
		return false
	return forward.normalized().dot(toward_attacker.normalized()) <= -rear_dot
