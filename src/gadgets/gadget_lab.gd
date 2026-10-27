# Отдельный полигон проверки: исходный testbed не перезаписывается.
class_name GadgetLab
extends Node3D

@export var class_profile: ClassData
@export var gadget_profile: GadgetData
@export var primary_profile: WeaponData
@export var instructions: String = "3: select gadget | LMB: deploy | R: reload | damage 60: wound yourself"

var player: Player
var world: Node3D


func _ready() -> void:
	world = load("res://src/maps/testbed/testbed.tscn").instantiate() as Node3D
	player = world.get_node("Player") as Player
	player.class_data = class_profile
	var inventory: Inventory = player.get_node("Inventory") as Inventory
	inventory.loadout = inventory.loadout.duplicate() as Loadout
	inventory.loadout.gadget_1 = gadget_profile
	if primary_profile != null:
		inventory.loadout.primary = primary_profile
		(player.get_node("Weapon") as Weapon).data = primary_profile
	add_child(world)
	var hint: Label = Label.new()
	hint.text = instructions
	hint.position = Vector2(24.0, 100.0)
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	canvas.add_child(hint)
