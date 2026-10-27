# Профиль слота Assault ссылается на уже существующую контактную гранату.
class_name LauncherGadgetData
extends GadgetData

@export var projectile: ProjectileData


func is_valid() -> bool:
	return super.is_valid() and projectile != null \
		and projectile.kind == ProjectileData.Kind.FRAG and projectile.impact_detonation \
		and is_finite(projectile.speed) and projectile.speed > 0.0 \
		and is_finite(projectile.fuse) and projectile.fuse > 0.0 \
		and projectile.gravity.is_finite() and is_finite(projectile.drag) and projectile.drag >= 0.0 \
		and is_finite(projectile.radius) and projectile.radius > 0.0 \
		and is_finite(projectile.damage) and projectile.damage > 0.0 \
		and projectile.max_contacts > 0
