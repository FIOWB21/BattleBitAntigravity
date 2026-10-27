# Только косметические параметры; оружейная симуляция этот ресурс не читает.
class_name ShotFxConfig
extends Resource

@export_group("Pools")
@export var flash_capacity: int = 8
@export var tracer_capacity: int = 32
@export var shell_capacity: int = 64
@export var impact_capacity: int = 64

@export_group("Muzzle")
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.015, -0.43)
@export var world_muzzle_offset: Vector3 = Vector3(0.2, -0.2, -0.65)
@export var shell_offset: Vector3 = Vector3(0.04, 0.02, -0.1)
@export var flash_lifetime: float = 0.06
@export var flash_particles: int = 6
@export var flash_size: float = 0.045
@export var flash_speed: Vector2 = Vector2(0.5, 2.0)
@export var flash_spread: float = 24.0
@export var flash_color: Color = Color(1.0, 0.66, 0.15)
@export var flash_energy: float = 2.0
@export var flash_range: float = 3.0

@export_group("Tracer and Shell")
@export var tracer_every: int = 3
@export var tracer_speed: float = 600.0
@export var tracer_length: float = 2.5
@export var tracer_width: float = 0.012
@export var tracer_color: Color = Color(1.0, 0.75, 0.25)
@export var shell_lifetime: float = 2.0
@export var shell_velocity: Vector3 = Vector3(2.2, 1.5, 0.5)
@export var shell_gravity: float = 9.8
@export var shell_spin: Vector3 = Vector3(8.0, 12.0, 4.0)
@export var shell_size: Vector2 = Vector2(0.008, 0.035)
@export var shell_color: Color = Color(0.65, 0.43, 0.12)

@export_group("Impact: concrete, earth, metal, wood, flesh, water")
@export var impact_lifetime: float = 0.24
@export var impact_speed: float = 0.6
@export var impact_offset: float = 0.012
@export var impact_colors: PackedColorArray = PackedColorArray([
	Color(0.65, 0.62, 0.55), Color(0.32, 0.2, 0.1), Color(1.0, 0.65, 0.12),
	Color(0.48, 0.28, 0.1), Color(0.6, 0.04, 0.03), Color(0.45, 0.75, 0.95)])
@export var impact_scales: Array[Vector3] = [Vector3(0.14, 0.08, 0.14),
	Vector3(0.18, 0.12, 0.18), Vector3(0.025, 0.3, 0.025),
	Vector3(0.05, 0.16, 0.04), Vector3(0.12, 0.07, 0.12), Vector3(0.3, 0.08, 0.3)]
@export var decal_size: Vector3 = Vector3(0.09, 0.08, 0.09)
@export var decal_texture_size: int = 64
@export var decal_color: Color = Color(0.12, 0.1, 0.08)

@export_group("Audio and Hit Feedback")
@export var audio_distance: float = 120.0
@export var audio_unit_size: float = 8.0
@export var audio_volume_db: float = -10.0
@export var sample_rate: int = 22050
@export var fire_duration: float = 0.18
@export var hit_duration: float = 0.045
@export var whiz_duration: float = 0.15
@export var hit_frequency: float = 1600.0
@export var headshot_frequency: float = 2400.0
@export var whiz_frequency: float = 900.0
@export var whiz_radius: float = 2.0
@export var whiz_min_distance: float = 0.15
@export var hit_marker_duration: float = 0.15
@export var hit_marker_inner: float = 6.0
@export var hit_marker_outer: float = 13.0
@export var hit_marker_width: float = 2.0
@export var headshot_color: Color = Color(1.0, 0.3, 0.15)
