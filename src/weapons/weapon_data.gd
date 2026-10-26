# Данные оружия; значения профилей временные и не задают финальный баланс.
class_name WeaponData
extends Resource

enum FireMode { SEMI, AUTO, BURST }
enum Category { AR, SMG, LMG, DMR, SNIPER, SHOTGUN, PISTOL, LAUNCHER }

const SECONDS_PER_MINUTE: float = 60.0

@export var id: StringName
@export var display_name: String
@export var category: Category = Category.AR
@export var fire_modes: Array[FireMode] = [FireMode.AUTO, FireMode.SEMI]
@export var rpm: float = 700.0
@export var burst_count: int = 3

@export_group("Damage")
@export var damage_near: float = 30.0
@export var damage_far: float = 18.0
@export var range_near: float = 25.0
@export var range_far: float = 80.0
@export var headshot_mult: float = 1.8
@export var limb_mult: float = 0.8
@export var pellets: int = 1
@export var penetration: float = 0.0
@export var hitscan_range: float = 1000.0

@export_group("Ammo")
@export var mag_size: int = 30
@export var reserve_mags: int = 5
@export var reload_time: float = 2.2
@export var reload_empty_time: float = 2.8
@export var chamber_enabled: bool = true
@export var reload_interrupt_on_switch: bool = true
@export var reload_interrupt_on_sprint: bool = true

@export_group("Handling")
@export var draw_time: float = 0.5
@export var ads_time: float = 0.2
@export var ads_fov_mult: float = 0.75
@export var ads_move_speed_mult: float = 0.65
@export var move_speed_mult: float = 1.0
@export var spread_hip_deg: float = 2.0
@export var spread_ads_deg: float = 0.3
@export var recoil_pattern: Array[Vector2] = []

@export_group("Recoil and Spread")
# Vector2: подъём pitch и поворот yaw в градусах на выстрел.
@export var recoil_fallback_deg: Vector2 = Vector2(0.6, 0.0)
@export var recoil_noise_deg: Vector2 = Vector2(0.15, 0.25)
@export var recoil_pause: float = 0.2
@export var recoil_recovery_deg_per_second: float = 12.0
@export var spread_per_shot_deg: float = 0.35
@export var spread_max_bloom_deg: float = 3.0
@export var spread_recovery_deg_per_second: float = 2.5
@export var spread_move_deg_per_mps: float = 0.25
@export var spread_crouch_mult: float = 0.7
@export var spread_prone_mult: float = 0.45
@export var spread_ads_extra_mult: float = 0.5
@export var spread_max_deg: float = 15.0

@export_group("Presentation")
@export var viewmodel_config: ViewmodelConfig
@export var viewmodel_hip_offset: Vector3 = Vector3(0.22, -0.22, -0.5)
@export var viewmodel_ads_offset: Vector3 = Vector3(0.0, -0.1, -0.5)
@export var scope_overlay_enabled: bool = true
@export var viewmodel_scene: PackedScene
@export var worldmodel_scene: PackedScene
@export var fire_sound: AudioStream


func cooldown() -> float:
	return SECONDS_PER_MINUTE / rpm


func damage_at(distance: float) -> float:
	var t: float = clampf(inverse_lerp(range_near, range_far, distance), 0.0, 1.0)
	return lerpf(damage_near, damage_far, t)
