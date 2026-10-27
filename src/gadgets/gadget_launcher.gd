# Только запуск в существующий пул; урон/траектория/эффекты остаются у ProjectileSystem.
class_name GadgetLauncher
extends Node3D

signal fired(projectile: Projectile)

var _launching: bool = false


func fire(gadget: Gadget, ctx: GadgetContext, aim: Transform3D,
		system: ProjectileSystem, exclude: Array[RID]) -> bool:
	if _launching or not Game.is_server_or_offline(multiplayer) or ctx == null \
			or gadget == null or not gadget.can_use_at(ctx.tick) or system == null:
		return false
	var data: LauncherGadgetData = gadget.data as LauncherGadgetData
	if data == null or not data.is_valid() or not aim.is_finite() or aim.basis.z.is_zero_approx():
		return false
	var profile: ProjectileData = data.projectile
	var velocity: Vector3 = -aim.basis.z.normalized() * profile.speed + Vector3.UP * profile.upward_speed
	_launching = true
	var projectile: Projectile = system.launch(profile, aim.origin, velocity, ctx.source_id, exclude)
	if projectile == null:
		_launching = false
		return false
	if not gadget.use(ctx):
		projectile.active = false
		_launching = false
		return false
	_launching = false
	fired.emit(projectile)
	return true
