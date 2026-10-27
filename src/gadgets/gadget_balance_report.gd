# Приложение к существующему воспроизводимому отчёту оружия.
class_name GadgetBalanceReport
extends RefCounted


static func generate() -> String:
	return _medical_bag() + _ammo_crate()


static func _medical_bag() -> String:
	var config: MedicalBagConfig = load("res://src/gadgets/data/medical_bag_config.tres") as MedicalBagConfig
	var gadget: GadgetData = load("res://src/gadgets/data/medkit.tres") as GadgetData
	return "\n## Гаджеты — шаг 3.4a\n\n" \
		+ "| Класс / ID | Радиус | Лечение | Время жизни | Заряды / кулдаун / перезарядка |\n" \
		+ "|---|---|---|---|---|\n" \
		+ "| Medic / %s | %.1f м | %.1f HP/с | %.1f с | %d / %.1f с / %.1f с |\n\n" % [
			gadget.id, config.radius, config.heal_per_second, config.lifetime,
			gadget.max_charges, gadget.cooldown, gadget.reload_time] \
		+ "Аптечка лечит всех живых в сфере по положению сущности, без множителей зон и проверки стен. " \
		+ "Раненые/мёртвые не поднимаются; максимум здоровья не превышается. " \
		+ "Размещение на земле: слот 3, одиночное нажатие ЛКМ; R восстанавливает заряд по базовому контракту Gadget. " \
		+ "Баланс предварительный. Сцена проверки: `src/gadgets/scenes/medic_lab.tscn`.\n"


static func _ammo_crate() -> String:
	var config: AmmoCrateConfig = load("res://src/gadgets/data/ammo_crate_config.tres") as AmmoCrateConfig
	var gadget: GadgetData = load("res://src/gadgets/data/ammo_box.tres") as GadgetData
	var stock: GrenadeStockConfig = load("res://src/player/default_grenade_stock.tres") as GrenadeStockConfig
	return "\n## Ящик Support — шаг 3.4b\n\n" \
		+ "`%s`: сфера %.1f м, каждые %.1f с — %.0f%% полного запаса каждого оружия " % [
			gadget.id, config.radius, config.interval, config.ammo_fraction * 100.0] \
		+ "(округление вниз) и %d граната. Магазины не меняются, вместимость не превышается. " % config.grenades_per_pulse \
		+ "Запас гранат: %d при старте / %d максимум; расход только при успешном броске. " % [stock.initial_count, stock.capacity] \
		+ "Лимит — один активный ящик на сущность владельца; новый немедленно отключает старый. " \
		+ "Срок жизни и общий объём снабжения не ограничены. " \
		+ "Зарядов %d, кулдаун %.1f с, перезарядка %.1f с. " % [gadget.max_charges, gadget.cooldown, gadget.reload_time] \
		+ "Снабжаются все живые игроки в сфере без LOS; раненые/мёртвые исключены. " \
		+ "Баланс предварительный. Сцена проверки: `src/gadgets/scenes/support_lab.tscn`.\n"
