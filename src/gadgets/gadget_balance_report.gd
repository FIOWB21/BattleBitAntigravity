# Приложение к существующему воспроизводимому отчёту оружия.
class_name GadgetBalanceReport
extends RefCounted


static func generate() -> String:
	return _medical_bag() + _ammo_crate() + _repair_tool() + _charges() + _spotting() + _beacon() + _launcher()


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


static func _repair_tool() -> String:
	var data: RepairToolData = load("res://src/gadgets/data/repair_tool.tres") as RepairToolData
	return "\n## Ремонт Engineer — шаг 3.4c\n\n" \
		+ "`%s`: дальность луча %.1f м, %.1f HP/с; нагрев %.0f%%/с, охлаждение %.0f%%/с. " % [
			data.id, data.reach, data.repair_per_second, data.heat_per_second * 100.0, data.cooling_per_second * 100.0] \
		+ "При 100%% ремонт блокируется до %.0f%% тепла. Из холодного состояния до перегрева %.1f с, " % [
			data.resume_heat * 100.0, 1.0 / data.heat_per_second] \
		+ "полный цикл охлаждения до разблокировки %.2f с. " % ((1.0 - data.resume_heat) / data.cooling_per_second) \
		+ "Лечится только живая RepairSurface техники; стена и дальность блокируют луч, полное/нулевое HP не чинится. " \
		+ "Нагрев только за фактическое время ремонта, скрытый инструмент охлаждается; пропуски тиков не дают прошлого ремонта. " \
		+ "Удержание ЛКМ из слота 3; гранаты и магазины не расходуются. " \
		+ "Баланс предварительный. Сцена проверки с примитивной целью: `src/gadgets/scenes/engineer_lab.tscn`.\n"


static func _charges() -> String:
	var config: ChargeConfig = load("res://src/gadgets/data/mine_config.tres") as ChargeConfig
	var data: GadgetData = load("res://src/gadgets/data/mine.tres") as GadgetData
	return "\n## Мина и C4 Engineer — шаг 3.4d\n\n" \
		+ "Оба заряда: %.0f урона в центре, линейное падение до нуля на %.1f м; технике ×%.0f. " % [
			config.blast.damage, config.blast.radius, config.vehicle_multiplier] \
		+ "Стены закрывают взрыв, один HealthComponent получает один урон. Взведение %.1f с. " % config.arming_time \
		+ "Мина срабатывает на RepairSurface в сфере %.1f м; C4 только по команде. " % config.trigger_radius \
		+ "ЛКМ размещает, ПКМ взрывает только заряды владельца из выбранного слота мины/C4. " \
		+ "Лимит %d активных зарядов на владельца, старейший удаляется без взрыва. " % config.max_active \
		+ "Заряды %d, кулдаун %.1f с, R %.1f с по контракту Gadget. " % [
			data.max_charges, data.cooldown, data.reload_time] \
		+ "Собственные примитивные сцены: `mine.tscn`, `c4.tscn`; полигоны `mine_lab.tscn`, `c4_lab.tscn`. Баланс предварительный.\n"


static func _spotting() -> String:
	var data: SpottingData = load("res://src/gadgets/data/spotting_device.tres") as SpottingData
	return "\n## Засветка Recon — шаг 3.4e\n\n" \
		+ "`%s`: серверный луч %.0f м выбирает живого противника; стены закрывают приобретение цели. " % [data.id, data.reach] \
		+ "HUD-метка для команды наблюдателя видна сквозь стены %.1f с, повтор обновляет срок. " % data.duration \
		+ "Пул %d меток на мир; переполнение отклоняет действие без расхода заряда. " % data.capacity \
		+ "Смерть/удаление/переход цели в команду наблюдателя снимают метку. " \
		+ "Заряды %d, кулдаун %.1f с, R %.1f с; ЛКМ из слота 3. " % [data.max_charges, data.cooldown, data.reload_time] \
		+ "Принадлежность задаётся серверными CombatAffiliation; назначение команд матча и RPC не реализуются. " \
		+ "Собственные бинокль/мишень; полигон `recon_spot_lab.tscn`. Баланс предварительный.\n"


static func _beacon() -> String:
	var config: BeaconConfig = load("res://src/gadgets/data/beacon_config.tres") as BeaconConfig
	var data: GadgetData = load("res://src/gadgets/data/spawn_beacon.tres") as GadgetData
	return "\n## Маяк Recon — шаг 3.4f\n\n" \
		+ "`%s`: %.0f HP, один маяк на владельца; новый удаляет предыдущий без взрыва. " % [data.id, config.max_health] \
		+ "Только SPAWN_SELECT той же положительной команды/отряда, зафиксированных сервером при деплое. " \
		+ "Проверяются %d позиции в %.1f м: земля, проход от маяка и стоячая капсула без пересечений. " % [
			config.offsets.size(), config.offsets[0].length()] \
		+ "Нет свободной позиции — нет возрождения; уничтожение сразу запрещает спавн. " \
		+ "Возвращает полное здоровье без пополнения патронов/гранат; кнопка Squad beacon на текущем экране выбора. " \
		+ "Заряды %d, кулдаун %.1f с, R %.1f с. " % [data.max_charges, data.cooldown, data.reload_time] \
		+ "Собственная примитивная сцена и `recon_beacon_lab.tscn`; создание отрядов/режима матча не реализуется. Баланс предварительный.\n"


static func _launcher() -> String:
	var data: LauncherGadgetData = load("res://src/gadgets/data/underslung_launcher.tres") as LauncherGadgetData
	return "\n## Подствольник Assault — шаг 3.4g\n\n" \
		+ "`%s` в слоте 3: существующая `%s`, %.0f м/с, гравитация %.1f м/с²; контактный взрыв. " % [
			data.id, data.projectile.id, data.projectile.speed, -data.projectile.gravity.y] \
		+ "Урон %.0f→0 на %.1f м, запал %.1f с. Общий ProjectileSystem и штатные Explosion/эффекты. " % [
			data.projectile.damage, data.projectile.radius, data.projectile.fuse] \
		+ "Заряды %d, кулдаун %.1f с, R %.1f с по контракту Gadget без отдельного резерва. " % [
			data.max_charges, data.cooldown, data.reload_time] \
		+ "Заполненный пул не расходует заряд; патроны винтовки и ручные гранаты независимы. " \
		+ "ЛКМ — один выстрел на нажатие, HUD показывает заряд/перезарядку. " \
		+ "Собственный примитив под существующей моделью винтовки, `assault_launcher_lab.tscn`. Баланс предварительный.\n"
