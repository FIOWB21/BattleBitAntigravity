# Команда симуляции. Поза задаётся сервером, а не камерой представления.
class_name GadgetContext
extends RefCounted

var tick: int = 0
var source_id: int = 0
var spawn_parent: Node3D
var spawn_transform: Transform3D = Transform3D.IDENTITY
