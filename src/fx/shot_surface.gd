# Тип поверхности задаётся метаданными фактического коллайдера.
class_name ShotSurface
extends RefCounted

enum Type { CONCRETE, EARTH, METAL, WOOD, FLESH, WATER }
const NAMES: Array[StringName] = [&"concrete", &"earth", &"metal", &"wood", &"flesh", &"water"]


static func resolve(hit: HitResult) -> Type:
	if hit.health_component != null or hit.hitbox != null:
		return Type.FLESH
	if not is_instance_valid(hit.collider):
		return Type.CONCRETE
	var name: String = str(hit.collider.get_meta(&"surface_type", &"concrete")).to_lower()
	if name == "dirt" or name == "ground":
		return Type.EARTH
	var index: int = NAMES.find(StringName(name))
	return index as Type if index >= 0 else Type.CONCRETE


static func accepts_decal(surface: Type) -> bool:
	return surface != Type.FLESH and surface != Type.WATER


static func normal_basis(normal: Vector3) -> Basis:
	var up: Vector3 = normal.normalized() if not normal.is_zero_approx() else Vector3.UP
	var helper: Vector3 = Vector3.RIGHT if absf(up.dot(Vector3.FORWARD)) > 0.99 else Vector3.FORWARD
	var right: Vector3 = up.cross(helper).normalized()
	return Basis(right, up, right.cross(up)).orthonormalized()
