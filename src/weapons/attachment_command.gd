# Временный вход лодаута через консоль, до появления отдельного меню.
class_name AttachmentCommand
extends RefCounted

const PROFILES: Dictionary[String, AttachmentData] = {
	"sight": preload("res://src/weapons/attachments/test_sight.tres"),
	"muzzle": preload("res://src/weapons/attachments/test_muzzle.tres"),
	"barrel": preload("res://src/weapons/attachments/test_barrel.tres"),
	"grip": preload("res://src/weapons/attachments/test_grip.tres"),
	"magazine": preload("res://src/weapons/attachments/test_magazine.tres"),
}
const SLOT_NAMES: Array[String] = ["sight", "muzzle", "barrel", "grip", "magazine"]


static func execute(args: PackedStringArray) -> String:
	if args.is_empty() or args.size() > 2:
		return "Usage: attachment list | equip <sight|muzzle|barrel|grip|magazine> | remove <slot>"
	var health: HealthComponent = Game.debug.get("local_health_component") as HealthComponent
	if not is_instance_valid(health) or not health.get_parent() is Player:
		return "Error: no local player"
	var player: Player = health.get_parent() as Player
	if player.inventory == null or player.inventory.phase != Inventory.Phase.READY:
		return "Error: inventory is busy"
	if player.weapon == null or health.is_dead or (player.equipment != null and player.equipment.melee.busy):
		return "Error: weapon unavailable"
	var weapon: Weapon = player.weapon
	if args.size() == 1 and args[0] == "list":
		return _describe(weapon)
	if args.size() != 2:
		return "Error: expected action and attachment/slot"
	var success: bool = false
	if args[0] == "equip" and PROFILES.has(args[1]):
		success = weapon.attachments.equip(PROFILES[args[1]])
	elif args[0] == "remove" and args[1] in SLOT_NAMES:
		success = weapon.attachments.remove(SLOT_NAMES.find(args[1]))
	return _describe(weapon) if success else "Error: attachment rejected (server, idle weapon, valid slot required)"


static func _describe(weapon: Weapon) -> String:
	var names: PackedStringArray = []
	for attachment: AttachmentData in weapon.attachments.items():
		names.append(String(attachment.id))
	return "attachments=[%s] hip=%.3f deg ADS=%.3f deg bloom=%.3f mag=%d" % [
		", ".join(names), weapon.data.spread_hip_deg, weapon.data.spread_ads_deg,
		weapon.data.spread_per_shot_deg, weapon.data.mag_size]
