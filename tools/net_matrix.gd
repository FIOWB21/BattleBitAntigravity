extends SceneTree

const PINGS: Array[int] = [30, 100, 200]
const LOSSES: Array[float] = [0.0, 2.0, 5.0]
const REPORT_PATH: String = "res://docs/NET_REPORT.md"
var _results: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 1000
	for ping: int in PINGS:
		for loss: float in LOSSES:
			var scenario: RefCounted = load("res://tools/net_matrix_case.gd").new()
			var result: Dictionary = await scenario.run(self, ping, loss)
			print("NET MATRIX ", JSON.stringify(result))
			if not scenario.valid_result(result):
				printerr("NET MATRIX FAILED; report was not overwritten. Logs: ", scenario.directory)
				quit(1)
				return
			_results.append(result)
	var torture: RefCounted = load("res://tools/net_matrix_case.gd").new()
	var impaired: Dictionary = await torture.run(self, 100, 5.0, 20, 10.0, 10.0)
	if not torture.valid_result(impaired):
		printerr("NET MATRIX combined impairments FAILED: ", JSON.stringify(impaired))
		quit(1)
		return
	_results.append(impaired)
	_write_report()
	print("NET MATRIX OK ", REPORT_PATH)
	quit(0)


func _write_report() -> void:
	var lines: Array[String] = _introduction()
	lines.append("| RTT задан / измерен, мс | Потери, % | Реконсиляции | Средняя ошибка, м | Сравнений | Запросы / приняты / отклонены | Отклонено, % | Потери ввод / снапшот |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for result: Dictionary in _results:
		lines.append(_row(result))
	lines.append("")
	lines.append("Последняя строка: дополнительно jitter ±20 мс, дубли 10%, перестановка 10% с удержанием 50 мс. Остальные строки: jitter/дубли/перестановка = 0.")
	lines.append("")
	lines.append("Все сценарии: чистые логи, штатное последовательное завершение, без телепортаций, потери истории и переполнения очередей; клиент не исполнял серверную симуляцию. Это короткий локальный ENet-прогон; внешняя сеть, длительная нагрузка и субъективное управление человеком не проверены.")
	lines.append("")
	lines.append("Сырые результаты и логи (локальные, исключены из Git):")
	lines.append("")
	for result: Dictionary in _results:
		lines.append("- `%s`: RTT %d, loss %.0f%%, jitter %d." % [String(result["logs"]).trim_prefix("res://"), result["ping_ms"], result["loss_percent"], result["jitter_ms"]])
	lines.append("")
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
	var raw: FileAccess = FileAccess.open("res://.godot/net_matrix_results.json", FileAccess.WRITE)
	raw.store_string(JSON.stringify(_results, "\t"))
	raw.close()


func _introduction() -> Array[String]:
	return ["# NET_REPORT — шаг 4.12", "", "Запуск: `tools/net_matrix.sh`. Сформировано: " + Time.get_datetime_string_from_system(true) + " UTC.",
		"Движок: `" + Engine.get_version_info()["string"] + "`; ОС: " + OS.get_name() + "; физика 60 Гц, снапшоты 30 Гц; seed 412..415.", "",
		"Один dedicated-сервер и один клиент на loopback, настоящие ENet/RPC и производственные меню, карта, часы, PlayerInput, Prediction и серверное оружие. Настройки оружия меняются только в памяти стенда: 300 RPM, магазин 200, без отдачи. После прогрева 1.5 с: 180 тиков вправо + 180 влево с удержанием огня, затем 1.5 с на доставку и истечение запросов.", "",
		"RTT — добавленная задержка полного круга: половина на каждом исходящем направлении; измерение содержит также loopback и ожидание кадра. Процент потерь применяется независимо к каждому исходящему ненадёжному RPC. Надёжные запросы огня/патроны/чат/спавн/рукопожатие не искажаются.", "",
		"Реконсиляции — прирост счётчика после прогрева. Средняя ошибка — сумма расстояний между предсказанной и серверной позицией на подтверждённом тике / число сравнимых снапшотов за маршрут и дренирование; bootstrap без истории исключён. Исправления скорости могут иметь нулевую ошибку позиции.", "",
		"Отклонено = (отправленные надёжные fire − принятые сервером выстрелы) / отправленные fire × 100%. Это включает прямой отказ, истечение и отсутствие соответствующего ввода; перед замером pending=0. Это доля непринятых намерений, а не доля промахов по цели. Точность попаданий по цели здесь не измеряется.", ""]


func _row(result: Dictionary) -> String:
	var client: Dictionary = result["client"]
	var server: Dictionary = result["server"]
	var rejected: int = int(client["requests"]) - int(server["accepted"])
	return "| %d / %.1f | %.0f | %d | %.6f | %d | %d / %d / %d | %.2f | %d / %d |" % [
		result["ping_ms"], client["ping_ms"], result["loss_percent"], client["reconciliations"],
		client["mean_error_m"], client["samples"], client["requests"], server["accepted"], rejected,
		result["rejected_percent"], client["input_drops"], server["snapshot_drops"]]
