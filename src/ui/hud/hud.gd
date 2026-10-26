# Базовый игровой HUD: полоска здоровья, прицел-точка, индикатор стойки и заглушка боезапаса.
class_name HUD
extends CanvasLayer

const DEFAULT_MAX_HEALTH: float = 100.0
const DEFAULT_CLIP_AMMO: int = 30
const DEFAULT_RESERVE_AMMO: int = 120

var current_health: float = DEFAULT_MAX_HEALTH
var max_health: float = DEFAULT_MAX_HEALTH
var current_stance: int = PlayerStance.STAND
var current_ammo: int = DEFAULT_CLIP_AMMO
var reserve_ammo: int = DEFAULT_RESERVE_AMMO

var health_bar: ProgressBar = null
var health_label: Label = null
var stance_label: Label = null
var ammo_label: Label = null
var crosshair_dot: ColorRect = null

var _bound_health: HealthComponent = null
var _bound_stance: StanceController = null


func _ready() -> void:
	_cache_nodes()
	_update_health_ui(current_health, max_health)
	_update_stance_ui(current_stance)
	set_ammo(current_ammo, reserve_ammo)
	if _bound_health == null:
		_auto_bind_from_parent()


func _exit_tree() -> void:
	unbind_all()


func bind_player(player: Node) -> void:
	if player == null:
		return
	var hc: HealthComponent = player.get_node_or_null("HealthComponent") as HealthComponent
	if hc != null:
		bind_health_component(hc)
	var sc: StanceController = player.get_node_or_null("StanceController") as StanceController
	if sc != null:
		bind_stance_controller(sc)


func bind_health_component(hc: HealthComponent) -> void:
	_unbind_health()
	_bound_health = hc
	if _bound_health == null:
		return
	if not _bound_health.health_changed.is_connected(_on_health_changed):
		_bound_health.health_changed.connect(_on_health_changed)
	if not _bound_health.died.is_connected(_on_died):
		_bound_health.died.connect(_on_died)
	_on_health_changed(_bound_health.current, _bound_health.max_health)


func bind_stance_controller(sc: StanceController) -> void:
	_unbind_stance()
	_bound_stance = sc
	if _bound_stance == null:
		return
	if not _bound_stance.stance_changed.is_connected(_on_stance_changed):
		_bound_stance.stance_changed.connect(_on_stance_changed)
	_on_stance_changed(_bound_stance.current_stance)


func unbind_all() -> void:
	_unbind_health()
	_unbind_stance()


func set_ammo(in_clip: int, in_reserve: int) -> void:
	_cache_nodes()
	current_ammo = maxi(in_clip, 0)
	reserve_ammo = maxi(in_reserve, 0)
	if ammo_label != null:
		ammo_label.text = "%d / %d" % [current_ammo, reserve_ammo]


static func stance_name_for(stance_value: int) -> String:
	match stance_value:
		PlayerStance.STAND:
			return "STAND"
		PlayerStance.CROUCH:
			return "CROUCH"
		PlayerStance.PRONE:
			return "PRONE"
		_:
			return "STAND"


func _on_health_changed(current: float, max_value: float) -> void:
	_update_health_ui(current, max_value)


func _on_died(_killer_id: int) -> void:
	_update_health_ui(0.0, max_health)


func _on_stance_changed(new_stance: int) -> void:
	_update_stance_ui(new_stance)


func _update_health_ui(current: float, max_value: float) -> void:
	_cache_nodes()
	max_health = maxf(max_value, 1.0)
	current_health = clampf(current, 0.0, max_health)
	if health_bar != null:
		health_bar.min_value = 0.0
		health_bar.max_value = max_health
		health_bar.value = current_health
	if health_label != null:
		health_label.text = "%d / %d" % [roundi(current_health), roundi(max_health)]


func _update_stance_ui(stance_value: int) -> void:
	_cache_nodes()
	current_stance = stance_value
	if stance_label != null:
		stance_label.text = stance_name_for(stance_value)


func _cache_nodes() -> void:
	if health_bar == null:
		health_bar = get_node_or_null("Root/BottomLeftPanel/MarginContainer/VBoxContainer/HealthBar") as ProgressBar
	if health_label == null:
		health_label = get_node_or_null("Root/BottomLeftPanel/MarginContainer/VBoxContainer/HealthLabel") as Label
	if stance_label == null:
		stance_label = get_node_or_null("Root/BottomLeftPanel/MarginContainer/VBoxContainer/StanceLabel") as Label
	if ammo_label == null:
		ammo_label = get_node_or_null("Root/BottomRightPanel/MarginContainer/AmmoLabel") as Label
	if crosshair_dot == null:
		crosshair_dot = get_node_or_null("Root/CrosshairContainer/CrosshairDot") as ColorRect


func _auto_bind_from_parent() -> void:
	var p: Node = get_parent()
	if p == null:
		return
	var player: Node = p.get_node_or_null("Player")
	if player != null:
		bind_player(player)


func _unbind_health() -> void:
	if _bound_health != null:
		if _bound_health.health_changed.is_connected(_on_health_changed):
			_bound_health.health_changed.disconnect(_on_health_changed)
		if _bound_health.died.is_connected(_on_died):
			_bound_health.died.disconnect(_on_died)
		_bound_health = null


func _unbind_stance() -> void:
	if _bound_stance != null:
		if _bound_stance.stance_changed.is_connected(_on_stance_changed):
			_bound_stance.stance_changed.disconnect(_on_stance_changed)
		_bound_stance = null
