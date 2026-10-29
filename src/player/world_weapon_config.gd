# Presentation parameters only; no simulation or inventory state.
class_name WorldWeaponConfig
extends Resource

@export var held_offset: Vector3 = Vector3(0.24, -0.25, -0.25)
@export var aimed_offset: Vector3 = Vector3(0.1, -0.16, -0.3)
@export var reload_offset: Vector3 = Vector3(0.0, -0.12, 0.08)
@export var reload_rotation: Vector3 = Vector3(-0.4, 0.0, -0.65)
@export var reload_cycle_seconds: float = 1.0
@export var pistol_scale: Vector3 = Vector3(0.75, 0.8, 0.5)
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.015, -0.43)
@export var firing_seconds: float = 0.1
