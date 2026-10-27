# Частицы прогреты; свет живёт ровно один render-кадр после импульса.
class_name MuzzleFlash
extends Node3D

var particles: GPUParticles3D
var light: OmniLight3D
var _remaining: float = 0.0
var _frame: int = -1
var _config: ShotFxConfig


func setup(config: ShotFxConfig, assets: ShotFxAssets) -> void:
	_config = config
	particles = GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = config.flash_particles
	particles.lifetime = config.flash_lifetime
	particles.explosiveness = 1.0
	particles.local_coords = true
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = Vector3.FORWARD
	process.spread = config.flash_spread
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = config.flash_speed.x
	process.initial_velocity_max = config.flash_speed.y
	particles.process_material = process
	particles.draw_pass_1 = assets.flash
	add_child(particles)
	light = OmniLight3D.new()
	light.light_color = config.flash_color
	light.light_energy = config.flash_energy
	light.omni_range = config.flash_range
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	visible = false


func pulse(pose: Transform3D, frame: int) -> void:
	global_transform = pose
	_remaining = _config.flash_lifetime
	_frame = frame
	visible = true
	light.visible = true
	particles.restart()
	particles.emitting = true


func advance(delta: float, frame: int) -> void:
	if frame > _frame:
		light.visible = false
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining == 0.0 and frame > _frame:
		visible = false
