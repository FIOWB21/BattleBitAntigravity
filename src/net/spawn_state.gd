# Shared reset of movement/presentation; gameplay refill is server-only.
class_name SpawnState
extends RefCounted


static func apply_pose(actor: Player, pose: Transform3D, tick: int) -> void:
	actor.global_transform = pose
	actor.velocity = Vector3.ZERO
	actor.motor.reset_for_spawn(actor.movement_config)
	actor.movement.blocked = false
	actor.stance_controller.current_lean = 0.0
	actor.stance_controller.current_lean_offset = 0.0
	actor.stance_controller.current_lean_angle = 0.0
	actor.stance_controller.set_stance_immediate(PlayerStance.STAND)
	actor.stance = PlayerStance.STAND
	actor.lean = 0.0
	actor.head.position.x = 0.0
	actor.head.rotation = Vector3.ZERO
	actor.input_reader.yaw = pose.basis.get_euler().y
	actor.input_reader.pitch = 0.0
	actor.ads.setup(actor.weapon.data if actor.weapon != null else null)
	actor.local_controller.prediction.reset_for_spawn(tick)
	actor.remote_view.reset_for_spawn(pose, tick)
	actor.reset_physics_interpolation()
	if actor.is_local_player:
		actor.capture_mouse()


static func refill(actor: Player) -> void:
	if not actor.multiplayer.is_server():
		return
	actor.inventory.reset_for_spawn()
	actor.equipment.projectiles.reset_for_spawn()
	actor.equipment.gadgets.reset_for_spawn()
