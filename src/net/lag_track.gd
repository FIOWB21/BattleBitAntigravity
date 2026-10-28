# One player's bounded history and temporary physics state, independent of movement.
class_name LagTrack
extends RefCounted

var actor: Player
var frames: Array[LagPose] = []
var zones: Array[HitboxZone] = []
var collisions: Array[CollisionShape3D] = []
var saved_transforms: Array[Transform3D] = []
var saved_shapes: Array[RID] = []
var rewound: bool = false


func configure(player: Player, capacity: int) -> void:
	actor = player
	zones = player.hitboxes.get_zones()
	for zone: HitboxZone in zones:
		collisions.append(zone.get_node("CollisionShape3D") as CollisionShape3D)
	saved_transforms.resize(zones.size())
	saved_shapes.resize(zones.size())
	for index: int in range(capacity):
		var pose: LagPose = LagPose.new()
		pose.configure(collisions)
		frames.append(pose)


func record(tick: int) -> void:
	frames[tick % frames.size()].capture(tick, actor, zones, collisions)


func rewind(tick: int) -> void:
	var pose: LagPose = frames[tick % frames.size()]
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	for zone: HitboxZone in zones:
		zone.force_update_transform()
	if pose.tick != tick:
		return
	for index: int in range(zones.size()):
		var area: RID = zones[index].get_rid()
		saved_transforms[index] = PhysicsServer3D.area_get_transform(area)
		saved_shapes[index] = PhysicsServer3D.area_get_shape(area, 0)
		PhysicsServer3D.area_set_transform(area, pose.transforms[index])
		PhysicsServer3D.area_set_shape(area, 0, pose.shapes[index].get_rid())
	rewound = true


func restore() -> void:
	if not rewound:
		return
	if is_instance_valid(actor) and actor.is_inside_tree():
		for index: int in range(zones.size()):
			var area: RID = zones[index].get_rid()
			PhysicsServer3D.area_set_transform(area, saved_transforms[index])
			PhysicsServer3D.area_set_shape(area, 0, saved_shapes[index])
	rewound = false
