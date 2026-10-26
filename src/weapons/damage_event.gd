# Данные одного попадания; урон рассчитан до изменения здоровья цели.
class_name DamageEvent
extends RefCounted

var attacker: int = 0
var target: Node = null
var zone: int = HitboxZone.NONE
var damage: float = 0.0
var weapon: StringName = &""
var distance: float = 0.0
var point: Vector3 = Vector3.ZERO
