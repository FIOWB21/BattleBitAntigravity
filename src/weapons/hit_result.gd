# Результат трассировки луча хитскана (точка, нормаль, зона хитбокса, множитель урона и цель).
class_name HitResult
extends RefCounted

var hit: bool = false
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.ZERO
var zone: int = HitboxZone.NONE
var damage_mult: float = 0.0
var target: Object = null
var health_component: HealthComponent = null
var hitbox: HitboxZone = null
var entity: Node = null
var collider: Object = null
var rid: RID = RID()

var point: Vector3:
	get:
		return position
	set(value):
		position = value
