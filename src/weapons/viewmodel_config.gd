class_name ViewmodelConfig
extends Resource

@export_range(1.0, 179.0) var fov: float = 75.0
@export var spring_frequency: float = 5.0
@export var sway_scale: float = 0.025
@export var sway_max_radians: float = 0.06
@export var bob_cycles_per_meter: float = 0.45
@export var bob_reference_speed: float = 5.0
@export var bob_offset: Vector3 = Vector3(0.008, 0.006, 0.0)
@export var kick_velocity: Vector3 = Vector3(0.0, 0.0, 0.8)
@export var kick_angular_velocity: Vector3 = Vector3(1.2, 0.0, 0.1)
@export var sprint_offset: Vector3 = Vector3(0.03, -0.08, 0.03)
@export var sprint_rotation: Vector3 = Vector3(-0.2, 0.15, -0.35)
@export var reload_offset: Vector3 = Vector3(0.0, -0.16, 0.06)
@export var reload_rotation: Vector3 = Vector3(-0.35, 0.1, -0.6)
@export var reload_curve: Curve
