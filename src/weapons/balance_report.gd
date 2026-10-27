# Текст отчёта зависит только от игровых ресурсов и явно заданного сценария.
class_name BalanceReport
extends RefCounted

const TARGET_HEALTH: float = 100.0
const DISTANCES: Array[float] = [5.0, 10.0, 25.0, 50.0, 100.0, 200.0]
const CATEGORY_NAMES: Array[String] = ["AR", "SMG", "LMG", "DMR", "SNIPER", "SHOTGUN", "PISTOL", "LAUNCHER"]


static func generate(catalog: WeaponCatalog, hitboxes: HitboxConfig, tick_rate: int) -> String:
	var output: String = "# Баланс оружия — шаг 2.12\n\n"
	output += "Сгенерировано `tools/ttk_report.gd` из `src/weapons/data/balanced_catalog.tres`. "
	output += "Повторная генерация (PowerShell): `& $env:GODOT --headless --path . -s res://tools/ttk_report.gd`.\n\n"
	output += "Состав согласован пользователем: **17 единиц**, включая подствольный гранатомёт. "
	output += "Временные `sample_*` не входят в каталог и сохраняются для прежних тестов/комплекта.\n\n"
	output += _methodology(hitboxes, tick_rate)
	output += _profiles(catalog, tick_rate)
	output += _ttk_table(catalog, hitboxes.torso_mult, tick_rate, "торс")
	output += _ttk_table(catalog, hitboxes.head_mult, tick_rate, "голова")
	output += _handling(catalog)
	output += _explosives(catalog)
	output += _playtest()
	return output


static func _methodology(hitboxes: HitboxConfig, tick_rate: int) -> String:
	var output: String = "## Методика\n\n"
	output += "Цель: %.0f HP, без брони/регенерации; симуляция %d Гц. " % [TARGET_HEALTH, tick_rate]
	output += "Первый выстрел — t=0; все выстрелы и все дробины попадают в выбранную зону. "
	output += "TTK — нижняя граница без ADS, смены, перезарядки, промахов и сетевой задержки.\n\n"
	output += "Урон = `damage_at(distance) × pellets × множитель хитбокса`; "
	output += "число выстрелов = `ceil(HP / урон)`. Интервал = `max(1, ceil(60 / RPM × Гц))` тиков; "
	output += "для SEMI минимум 2 тика, чтобы отпустить спуск. TTK = `(выстрелы − 1) × интервал / Гц`. "
	output += "Ячейка: **выстрелы / секунды**; 0.000 означает убийство первым выстрелом.\n\n"
	output += "Множители из `default_hitboxes.tres`: торс %.2f, голова %.2f. " % [hitboxes.torso_mult, hitboxes.head_mult]
	output += "Поля WeaponData.headshot_mult/limb_mult повторно не применяются: это соответствует DamageCalc. "
	output += "Используется первый режим профиля; SEMI требует идеальных повторных нажатий. "
	output += "`—` означает: снарядный профиль, цель вне hitscan_range, неверные параметры, "
	output += "недостаточно одного магазина либо требуется повторный запуск очереди.\n\n"
	output += "Ориентир средней дистанции для AR: **25–50 м, 0.25–0.40 с в торс**. "
	output += "У дробовиков таблица предполагает попадание всех дробин даже вдали; реальная эффективность ниже. "
	output += "Гранатомёт не получает фиктивный hitscan-TTK: полёт, гравитация и место взрыва меняют результат.\n\n"
	return output


static func _profiles(catalog: WeaponCatalog, tick_rate: int) -> String:
	var output: String = "## Профили\n\n"
	output += "| ID | Категория | Урон близко→далеко | Дистанции, м | RPM заданный / фактический | Магазин / запас | Перезарядка / пустая, с |\n"
	output += "|---|---|---|---|---|---|---|\n"
	for data: WeaponData in catalog.weapons:
		var rpm: float = WeaponData.SECONDS_PER_MINUTE * tick_rate / TtkCalculator.interval_ticks(data, tick_rate)
		output += "| %s | %s | %.1f→%.1f ×%d | %.0f→%.0f | %.0f / %.1f | %d / %d | %.2f / %.2f |\n" % [
			data.id, CATEGORY_NAMES[data.category], data.damage_near, data.damage_far, data.pellets,
			data.range_near, data.range_far, data.rpm, rpm, data.mag_size,
			data.mag_size * data.reserve_mags, data.reload_time, data.reload_empty_time]
	return output + "\nУ LAUNCHER поля прямого урона равны 0: урон берётся из ProjectileData (см. ниже).\n\n"


static func _ttk_table(catalog: WeaponCatalog, multiplier: float, tick_rate: int, zone: String) -> String:
	var output: String = "## TTK: %s\n\n| ID |" % zone
	for distance: float in DISTANCES:
		output += " %.0f м |" % distance
	output += "\n|---|" + "---|".repeat(DISTANCES.size()) + "\n"
	for data: WeaponData in catalog.weapons:
		output += "| %s |" % data.id
		for distance: float in DISTANCES:
			var ttk: float = TtkCalculator.seconds(data, distance, TARGET_HEALTH, multiplier, tick_rate)
			var shots: int = TtkCalculator.shots_to_kill(data, distance, TARGET_HEALTH, multiplier)
			output += " %d / %.3f |" % [shots, ttk] if is_finite(ttk) else " — |"
		output += "\n"
	return output + "\n"


static func _handling(catalog: WeaponCatalog) -> String:
	var output: String = "## Обращение и устойчивость\n\n"
	output += "| ID | ADS, с | Скорость | ADS-конус, ° | Добавка за выстрел, ° | Присяд / лёжа | Отдача после паттерна, ° |\n"
	output += "|---|---|---|---|---|---|---|\n"
	for data: WeaponData in catalog.weapons:
		output += "| %s | %.2f | %.2f | %.3f | %.2f | %.2f / %.2f | %.2f |\n" % [data.id,
			data.ads_time, data.move_speed_mult, data.spread_ads_deg, data.spread_per_shot_deg,
			data.spread_crouch_mult, data.spread_prone_mult, data.recoil_fallback_deg.x]
	output += "\nLMG: большой магазин для длительного огня, сильнее выигрыш от присяда/положения лёжа, "
	output += "ниже скорость, дольше ADS и перезарядка. Психологическое подавление оценивается плейтестом; "
	output += "отдельная механика подавления этим шагом не вводится. SMG быстрее убивают вблизи, "
	output += "но раньше теряют урон. Снайперские сохраняют одно попадание в голову на всей дальности hitscan.\n\n"
	return output


static func _explosives(catalog: WeaponCatalog) -> String:
	var output: String = "## Подствольный гранатомёт\n\n"
	for data: WeaponData in catalog.weapons:
		var projectile: ProjectileData = data.projectile_data
		if projectile == null:
			continue
		output += "`%s`: начальная скорость %.1f м/с, гравитация %.1f м/с², сопротивление %.2f, " % [
			data.id, projectile.speed, projectile.gravity.y, projectile.drag]
		output += "радиус %.1f м, предельный запал %.1f с; детонация при контакте. " % [projectile.radius, projectile.fuse]
		output += "Множители головы не применяются; стена закрывает взрыв, самоповреждение разрешено.\n\n"
		output += "| Удаление от взрыва, м | Урон без препятствия |\n|---|---|\n"
		for distance: float in [0.0, 2.0, 4.0, 6.0]:
			output += "| %.0f | %.1f |\n" % [distance, projectile.damage_at(distance)]
	output += "\nПрофиль представляет боеприпас/баланс подствольника через имеющийся оружейный слот. "
	output += "Системы креплений и отдельной кнопки переключения подствольника нет в текущем шаге.\n\n"
	return output


static func _playtest() -> String:
	return "## Человеческая приёмка\n\n" \
		+ "🧑 Требуется проверка человеком **каждого из 17 профилей**; статус шага REVIEW до подтверждения. " \
		+ "Оценка ощущений пока не проведена. Все профили используют существующие процедурные модель/звук.\n\n" \
		+ "Запуск выбранного профиля (PowerShell): `& $env:GODOT --path . -s res://tools/weapon_balance_acceptance.gd -- --weapon=kestrel_ar`. " \
		+ "Заменить ID на любой из таблицы; исходные сцена и стандартный комплект на диске не изменяются. " \
		+ "Без `--weapon` скрипт автоматически проверяет стрельбу всех 17 профилей на полигоне.\n\n" \
		+ "Для каждого профиля: стрельба одиночными/очередями, ADS, движение, стоя/присяд/лёжа, " \
		+ "пустая и тактическая перезарядка; мишени на 5/10/25/50/100/200 м. " \
		+ "У снайперских проверить голову, у дробовиков распределение дроби, у гранатомёта дугу/взрыв/стену. " \
		+ "Записать отзыв и поправить соответствующий `.tres` в `src/weapons/data/catalog/`, " \
		+ "затем повторить генерацию отчёта и `tools/check.sh`.\n"
