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

@export_group("Handling")
@export var draw_time: float = 0.5
@export var ads_time: float = 0.2
@export var ads_fov_mult: float = 0.75
@export var move_speed_mult: float = 1.0
@export var spread_hip_deg: float = 2.0
@export var spread_ads_deg: float = 0.3
@export var recoil_pattern: Array[Vector2] = []

@export_group("Presentation")
@export var viewmodel_scene: PackedScene
@export var worldmodel_scene: PackedScene
@export var fire_sound: AudioStream


func cooldown() -> float:
	return SECONDS_PER_MINUTE / rpm


func damage_at(distance: float) -> float:
	var t: float = clampf(inverse_lerp(range_near, range_far, distance), 0.0, 1.0)
	return lerpf(damage_near, damage_far, t)
