# The engine interpolates the spawn transform; no snapshot stream in step 4.3.
class_name RemotePlayerView
extends Node3D

@export var capsule_color: Color = Color(0.22, 0.63, 0.88)

var capsule: MeshInstance3D


func setup(actor: Player) -> void:
	visible = not actor.is_local_player or Game.is_dedicated
	if actor.network_owner_id == 0:
		visible = false
		return
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var shape: CapsuleMesh = CapsuleMesh.new()
	shape.height = actor.movement_config.stand_height
	shape.radius = actor.movement_config.capsule_radius
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = capsule_color
	capsule = MeshInstance3D.new()
	capsule.mesh = shape
	capsule.material_override = material
	capsule.position.y = shape.height * 0.5
	add_child(capsule)
