# Воспроизводимая генерация отчёта из каталога .tres, без изменения игровых данных.
extends SceneTree


func _initialize() -> void:
	var catalog: WeaponCatalog = load("res://src/weapons/data/balanced_catalog.tres") as WeaponCatalog
	var hitboxes: HitboxConfig = load("res://src/player/default_hitboxes.tres") as HitboxConfig
	if catalog == null or hitboxes == null:
		printerr("TTK REPORT FAIL: resources unavailable")
		quit(1)
		return
	var output: String = BalanceReport.generate(catalog, hitboxes, Engine.physics_ticks_per_second)
	var file: FileAccess = FileAccess.open("res://docs/BALANCE.md", FileAccess.WRITE)
	if file == null:
		printerr("TTK REPORT FAIL: cannot write BALANCE.md")
		quit(1)
		return
	file.store_string(output)
	file.close()
	print("TTK REPORT OK: profiles=", catalog.weapons.size(), " tick_rate=", Engine.physics_ticks_per_second)
	quit(0)
