# Глобальный менеджер пользовательских настроек (user://settings.cfg).
extends Node

const DEFAULT_CONFIG_PATH: String = "user://settings.cfg"

const SECTION_CONTROLS: String = "controls"
const SECTION_VIDEO: String = "video"
const SECTION_AUDIO: String = "audio"

const KEY_SENSITIVITY: String = "sensitivity"
const KEY_FOV: String = "fov"
const KEY_VOLUME: String = "volume"
const KEY_GRAPHICS: String = "graphics"

const DEFAULT_SENSITIVITY: float = 0.2
const DEFAULT_FOV: float = 90.0
const DEFAULT_VOLUME: float = 1.0
const DEFAULT_GRAPHICS: String = "high"

var _config: ConfigFile = ConfigFile.new()
var _config_path: String = DEFAULT_CONFIG_PATH


func _ready() -> void:
	reset_to_defaults()
	if FileAccess.file_exists(_config_path):
		load_settings(_config_path)


func reset_to_defaults() -> void:
	_config.clear()
	_config.set_value(SECTION_CONTROLS, KEY_SENSITIVITY, DEFAULT_SENSITIVITY)
	_config.set_value(SECTION_VIDEO, KEY_FOV, DEFAULT_FOV)
	_config.set_value(SECTION_AUDIO, KEY_VOLUME, DEFAULT_VOLUME)
	_config.set_value(SECTION_VIDEO, KEY_GRAPHICS, DEFAULT_GRAPHICS)


func load_settings(path: String = _config_path) -> Error:
	_config_path = path
	reset_to_defaults()
	var err: Error = _config.load(path)
	if err == OK and Events != null:
		Events.settings_changed.emit()
	return err


func save_settings(path: String = _config_path) -> Error:
	_config_path = path
	return _config.save(path)


func get_sensitivity() -> float:
	return float(_config.get_value(SECTION_CONTROLS, KEY_SENSITIVITY, DEFAULT_SENSITIVITY))


func set_sensitivity(value: float) -> void:
	_config.set_value(SECTION_CONTROLS, KEY_SENSITIVITY, value)
	_notify_changed()


func get_fov() -> float:
	return float(_config.get_value(SECTION_VIDEO, KEY_FOV, DEFAULT_FOV))


func set_fov(value: float) -> void:
	_config.set_value(SECTION_VIDEO, KEY_FOV, value)
	_notify_changed()


func get_volume() -> float:
	return float(_config.get_value(SECTION_AUDIO, KEY_VOLUME, DEFAULT_VOLUME))


func set_volume(value: float) -> void:
	_config.set_value(SECTION_AUDIO, KEY_VOLUME, value)
	_notify_changed()


func get_graphics() -> String:
	return str(_config.get_value(SECTION_VIDEO, KEY_GRAPHICS, DEFAULT_GRAPHICS))


func set_graphics(value: String) -> void:
	_config.set_value(SECTION_VIDEO, KEY_GRAPHICS, value)
	_notify_changed()


func get_setting(section: String, key: String, default_value: Variant = null) -> Variant:
	return _config.get_value(section, key, default_value)


func set_setting(section: String, key: String, value: Variant) -> void:
	_config.set_value(section, key, value)
	_notify_changed()


func _notify_changed() -> void:
	if Events != null:
		Events.settings_changed.emit()
