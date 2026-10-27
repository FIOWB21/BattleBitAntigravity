# Дочерние сцены в точках модели. Вызывается при смене комплекта, не в кадре.
class_name AttachmentView
extends RefCounted

var _instances: Array[Node3D] = []


func apply(model: Node3D, attachments: Array[AttachmentData], rig: ViewmodelRig,
		settings: ViewmodelConfig) -> void:
	for instance: Node3D in _instances:
		if is_instance_valid(instance):
			instance.free()
	_instances.clear()
	for attachment: AttachmentData in attachments:
		if attachment.model_scene == null:
			continue
		var mount: Node3D = model.find_child(String(attachment.mount_name()), true, false) as Node3D
		if mount == null:
			continue
		var node: Node = attachment.model_scene.instantiate()
		if not node is Node3D:
			node.free()
			continue
		var instance: Node3D = node as Node3D
		mount.add_child(instance)
		_instances.append(instance)
		_prepare(instance, rig, settings)


func _prepare(node: Node, rig: ViewmodelRig, settings: ViewmodelConfig) -> void:
	if node is GeometryInstance3D:
		rig.prepare_geometry(node as GeometryInstance3D, settings)
	for child: Node in node.get_children():
		_prepare(child, rig, settings)
