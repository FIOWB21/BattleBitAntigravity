# Только приёмочная примитивная цель; движения и симуляции машины здесь нет.
class_name RepairFixture
extends Node3D

@export var initial_damage: float = 200.0

@onready var health: HealthComponent = $Health
@onready var label: Label3D = $Label


func _ready() -> void:
	health.health_changed.connect(_on_health_changed)
	health.apply_damage(initial_damage)
	_on_health_changed(health.current, health.max_health)


func _on_health_changed(current: float, maximum: float) -> void:
	label.text = "VEHICLE REPAIR TARGET\n%.0f / %.0f HP" % [current, maximum]
