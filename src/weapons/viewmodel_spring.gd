# Точное решение критически затухающей пружины при постоянной цели за кадр.
class_name ViewmodelSpring
extends RefCounted

var value: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO


func reset() -> void:
	value = Vector3.ZERO
	velocity = Vector3.ZERO


func advance(target: Vector3, frequency: float, delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var omega: float = TAU * maxf(frequency, 0.0)
	var offset: Vector3 = value - target
	var coefficient: Vector3 = velocity + offset * omega
	var decay: float = exp(-omega * delta)
	value = target + (offset + coefficient * delta) * decay
	velocity = (velocity - coefficient * omega * delta) * decay
