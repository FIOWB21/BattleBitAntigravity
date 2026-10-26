# Процедурный учебный ящик: пополнение при входе в зону, без клиентской логики.
class_name AmmoBox
extends Area3D

signal supplied(body: Node3D, amount: int)

@export_range(0.0, 1.0) var supply_fraction: float = 1.0


func _ready() -> void:
	body_entered.connect(supply)


func supply(body: Node3D) -> int:
	if not is_inside_tree() or not multiplayer.is_server() or not is_instance_valid(body):
		return 0
	var receiver: AmmoReceiver = body.get_node_or_null("AmmoReceiver") as AmmoReceiver
	if receiver == null:
		return 0
	var added: int = receiver.add_ammo(supply_fraction)
	if added > 0:
		supplied.emit(body, added)
	return added
