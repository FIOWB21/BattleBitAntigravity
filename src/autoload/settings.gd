# Глобальный менеджер пользовательских настроек (user://settings.cfg).
extends Node

const DEFAULT_CONFIG_PATH: String = "user://settings.cfg"

const SECTION_CONTROLS: String = "controls"
const SECTION_VIDEO: String = "video"
const SECTION_AUDIO: String = "audio"

const KEY_SENSITIVITY: String = "sensitivity"
const KEY_INVERT_Y: String = "invert_y"
const KEY_CAMERA_EFFECTS: String = "camera_effects"
const KEY_FOV: String = "fov"
const KEY_VOLUME: String = "volume"
const KEY_GRAPHICS: String = "graphics"

const DEFAULT_SENSITIVITY: float = 0.2
const DEFAULT_INVERT_Y: bool = false
const DEFAULT_CAMERA_EFFECTS: bool = true
const DEFAULT_FOV: float = 90.0
const MIN_FOV: float = 60.0
const MAX_FOV: float = 120.0
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
	_config.set_value(SECTION_CONTROLS, KEY_INVERT_Y, DEFAULT_INVERT_Y)
	_config.set_value(SECTION_VIDEO, KEY_CAMERA_EFFECTS, DEFAULT_CAMERA_EFFECTS)
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


func get_invert_y() -> bool:
	return bool(_config.get_value(SECTION_CONTROLS, KEY_INVERT_Y, DEFAULT_INVERT_Y))


func set_invert_y(value: bool) -> void:
	_config.set_value(SECTION_CONTROLS, KEY_INVERT_Y, value)
	_notify_changed()


func get_camera_effects_enabled() -> bool:
	return bool(_config.get_value(SECTION_VIDEO, KEY_CAMERA_EFFECTS, DEFAULT_CAMERA_EFFECTS))


func set_camera_effects_enabled(value: bool) -> void:
	_config.set_value(SECTION_VIDEO, KEY_CAMERA_EFFECTS, value)
	_notify_changed()


func get_fov() -> float:
	var raw_fov: float = float(_config.get_value(SECTION_VIDEO, KEY_FOV, DEFAULT_FOV))
	return clampf(raw_fov, MIN_FOV, MAX_FOV)


func set_fov(value: float) -> void:
	_config.set_value(SECTION_VIDEO, KEY_FOV, clampf(value, MIN_FOV, MAX_FOV))
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
