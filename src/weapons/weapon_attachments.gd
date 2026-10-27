# Изменение комплекта разрешено серверу между действиями; боезапас не создаётся.
class_name WeaponAttachments
extends RefCounted

var _weapon: Weapon
var _base: WeaponData
var _items: Array[AttachmentData] = []


func setup(weapon: Weapon, base: WeaponData) -> void:
	_weapon = weapon
	_base = base
	_items.clear()


func items() -> Array[AttachmentData]:
	return _items.duplicate()


func equip(attachment: AttachmentData) -> bool:
	if attachment == null:
		return false
	var selected: Array[AttachmentData] = []
	for item: AttachmentData in _items:
		if item.slot != attachment.slot:
			selected.append(item)
	selected.append(attachment)
	return _apply(selected)


func remove(slot: int) -> bool:
	var selected: Array[AttachmentData] = []
	for item: AttachmentData in _items:
		if item.slot != slot:
			selected.append(item)
	return selected.size() != _items.size() and _apply(selected)


func _apply(selected: Array[AttachmentData]) -> bool:
	if not is_instance_valid(_weapon) or not _weapon.is_inside_tree():
		return false
	if not _weapon.multiplayer.is_server() or _weapon.state != Weapon.State.IDLE:
		return false
	var resolved: WeaponData = WeaponStats.resolve(_base, selected)
	if resolved == null:
		return false
	_items = selected
	_weapon.data = resolved
	var capacity: int = resolved.mag_size + int(resolved.chamber_enabled and _weapon.ammo_in_mag > 0)
	var overflow: int = maxi(_weapon.ammo_in_mag - capacity, 0)
	_weapon.ammo_in_mag -= overflow
	_weapon.reserve_ammo += overflow
	_weapon.stats_changed.emit()
	if overflow > 0:
		_weapon.ammo_changed.emit(_weapon.ammo_in_mag, _weapon.reserve_ammo)
	return true
