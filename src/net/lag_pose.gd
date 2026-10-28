# Prewarmed collision snapshot; resources are copied only when a player joins.
class_name LagPose
extends RefCounted

var tick: int = -1
var body: Transform3D = Transform3D.IDENTITY
var stance: int = PlayerStance.STAND
var transforms: Array[Transform3D] = []
var shapes: Array[Shape3D] = []


func configure(source: Array[CollisionShape3D]) -> void:
	transforms.resize(source.size())
	for collision: CollisionShape3D in source:
		shapes.append(collision.shape.duplicate() as Shape3D)


func capture(at_tick: int, actor: Player, zones: Array[HitboxZone],
		collisions: Array[CollisionShape3D]) -> void:
	tick = at_tick
	body = actor.global_transform
	stance = actor.stance
	for index: int in range(zones.size()):
		zones[index].force_update_transform()
		transforms[index] = PhysicsServer3D.area_get_transform(zones[index].get_rid())
		if shapes[index] is SphereShape3D:
			(shapes[index] as SphereShape3D).radius = (collisions[index].shape as SphereShape3D).radius
		else:
			(shapes[index] as BoxShape3D).size = (collisions[index].shape as BoxShape3D).size
