# Узел игрока (CharacterBody3D), связывающий LocalInputReader, StanceController, PlayerMotor и камеру.
class_name Player
extends CharacterBody3D

signal fall_damaged(amount: float)

const DEFAULT_MOVEMENT_PATH: String = "res://src/player/default_movement.tres"
const DEFAULT_HITBOXES_PATH: String = "res://src/player/default_hitboxes.tres"

@export var movement_config: MovementConfig = preload(DEFAULT_MOVEMENT_PATH)
@export var hitbox_config: HitboxConfig = preload(DEFAULT_HITBOXES_PATH)
@export var is_local_player: bool = true
@export var class_data: ClassData = preload("res://src/classes/data/assault.tres")
@export var stance: int = PlayerStance.STAND:
	set(value):
		stance = clampi(value, PlayerStance.STAND, PlayerStance.PRONE)
		if stance_controller != null and stance_controller.current_stance != stance:
			stance_controller.set_stance_immediate(stance)
		if hitboxes != null:
			var lean_off: float = stance_controller.current_lean_offset if stance_controller != null else 0.0
			hitboxes.update_for_stance(stance, lean_off)

var lean: float = 0.0
var last_fall_damage: float = 0.0
var motor: PlayerMotor = PlayerMotor.new()
var input_reader: LocalInputReader = LocalInputReader.new()
var ads: WeaponAds = WeaponAds.new()
var _base_fov: float = 90.0
var _mouse_captured: bool = false

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var camera_effects: CameraEffects = $Head/CameraEffects
@onready var stance_controller: StanceController = get_node_or_null("StanceController") as StanceController
@onready var health_component: Node = get_node_or_null("HealthComponent")
@onready var hitboxes: PlayerHitboxes = get_node_or_null("Hitboxes") as PlayerHitboxes
@onready var weapon: Weapon = get_node_or_null("Weapon") as Weapon
@onready var weapon_hitscan: WeaponHitscan = get_node_or_null("WeaponHitscan") as WeaponHitscan
@onready var ads_view: WeaponAdsView = get_node_or_null("Head/Camera3D/WeaponAdsView") as WeaponAdsView
@onready var inventory: Inventory = get_node_or_null("Inventory") as Inventory
@onready var equipment: PlayerEquipment = get_node_or_null("PlayerEquipment") as PlayerEquipment
@onready var life: PlayerLife = get_node_or_null("PlayerLife") as PlayerLife


func _ready() -> void:
	_setup_components()
	if equipment != null:
		equipment.setup(self)
	if life != null:
		life.setup(self)
	input_reader.yaw = rotation.y
	if head != null:
		input_reader.pitch = clampf(
			head.rotation.x,
			-LocalInputReader.MAX_PITCH_RAD,
			LocalInputReader.MAX_PITCH_RAD
		)
	if camera != null:
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.top_level = is_local_player
	if Events != null and not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	apply_settings()
	if is_local_player:
		Game.debug["local_health_component"] = health_component
		capture_mouse()
		update_camera_visuals(0.0)


func _setup_components() -> void:
	if movement_config == null:
		movement_config = load(DEFAULT_MOVEMENT_PATH) as MovementConfig
	if hitbox_config == null:
		hitbox_config = load(DEFAULT_HITBOXES_PATH) as HitboxConfig
	floor_max_angle = deg_to_rad(movement_config.max_slope_angle) + PlayerMotor.SLOPE_EPSILON_RAD
	if stance_controller == null:
		stance_controller = StanceController.new()
		stance_controller.name = "StanceController"
		add_child(stance_controller)
	stance_controller.setup(self, collision_shape, head, movement_config, stance)
	if health_component == null:
		health_component = HealthComponent.new()
		health_component.name = "HealthComponent"
		add_child(health_component)
	if hitboxes == null:
		hitboxes = PlayerHitboxes.new()
		hitboxes.name = "Hitboxes"
		add_child(hitboxes)
	hitboxes.setup(self, health_component as HealthComponent, movement_config, hitbox_config, stance)


func _exit_tree() -> void:
	if Events != null and Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.disconnect(_on_settings_changed)
	if Game != null and Game.debug.get("local_health_component", null) == health_component:
		Game.debug.erase("local_health_component")


func apply_settings() -> void:
	if Settings != null:
		_base_fov = Settings.get_fov()
	_apply_ads_projection()
	if camera_effects != null:
		camera_effects.sync_with_settings()


func _apply_ads_projection() -> void:
	if camera != null:
		camera.fov = ads.fov(_base_fov)
		input_reader.aim_sensitivity_scale = WeaponAds.sensitivity_scale(camera.fov, _base_fov)


func capture_mouse() -> void:
	_mouse_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	_mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	if DisplayServer.get_name() == "headless":
		return _mouse_captured
	return _mouse_captured and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player:
		return
	handle_input_event(event)


func handle_input_event(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE_MENU):
		release_mouse()
		return
	if not is_mouse_captured():
		return
	var previous_look: Vector2 = Vector2(input_reader.yaw, input_reader.pitch)
	input_reader.handle_input_event(event)
	if event is InputEventMouseMotion:
		if ads_view != null and ads_view.rig != null:
			ads_view.rig.motion.add_look_delta(Vector2(input_reader.yaw, input_reader.pitch) - previous_look)
		if head != null:
			head.rotation.x = input_reader.pitch


func _physics_process(delta: float) -> void:
	if not is_local_player:
		return
	var inp: PlayerInput = input_reader.read_input()
	step_simulation(inp, delta)
	Game.debug["player_position"] = global_position


func _process(delta: float) -> void:
	if not is_local_player:
		return
	update_camera_visuals(delta)


func step_simulation(inp: PlayerInput, delta: float) -> void:
	if life != null:
		life.interaction.simulate(inp, delta)
		inp = life.filter_input(inp)
	if inventory != null:
		inventory.simulate(inp, not (health_component is HealthComponent and health_component.is_dead)
			and not (equipment != null and equipment.melee.busy))
	rotation.y = inp.yaw
	if stance_controller != null:
		stance_controller.step(inp, delta)
		stance = stance_controller.current_stance
		lean = stance_controller.current_lean
		if hitboxes != null:
			hitboxes.update_for_dimensions(
				stance_controller.current_capsule_height,
				stance_controller.current_head_height,
				stance_controller.current_lean_offset
			)
	_step_ads(inp, delta)
	motor.simulate(self, inp, movement_config, stance, delta)
	if motor.landed_this_tick:
		last_fall_damage = motor.last_fall_damage
		if last_fall_damage > 0.0:
			apply_fall_damage(last_fall_damage)
	if head != null:
		head.rotation.x = clampf(
			inp.pitch,
			-LocalInputReader.MAX_PITCH_RAD,
			LocalInputReader.MAX_PITCH_RAD
		)
	if equipment != null:
		equipment.simulate_melee(inp)
		if equipment.projectiles != null and not equipment.melee.busy:
			equipment.projectiles.simulate(inp)
	_step_weapon(inp)


func _step_weapon(inp: PlayerInput) -> void:
	if weapon_hitscan != null:
		var aim: Transform3D = Transform3D(
			Basis.from_euler(Vector3(head.rotation.x, inp.yaw, head.rotation.z)), head.global_position)
		var blocked: bool = motor.is_sprinting or not is_on_floor()
		blocked = blocked or (equipment != null and equipment.melee.busy)
		if health_component is HealthComponent:
			blocked = blocked or (health_component as HealthComponent).is_dead
		weapon_hitscan.simulate(inp, aim, blocked, stance,
			Vector2(velocity.x, velocity.z).length(), motor.is_sprinting, ads.amount())


func _step_ads(inp: PlayerInput, delta: float) -> void:
	var allowed: bool = not (health_component is HealthComponent and health_component.is_dead)
	allowed = allowed and not (equipment != null and (equipment.melee.busy or inp.melee))
	if weapon != null:
		allowed = allowed and weapon.state != Weapon.State.SWITCHING_IN and weapon.state != Weapon.State.SWITCHING_OUT
	else:
		allowed = false
	ads.simulate(inp, delta, allowed)
	motor.movement_multiplier = ads.movement_multiplier()
	motor.aim_held = ads.target > 0.0


func get_hitscan_exclude_rids() -> Array[RID]:
	if hitboxes != null:
		return hitboxes.get_exclude_rids()
	return [get_rid()]


func apply_fall_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	if health_component == null:
		health_component = get_node_or_null("HealthComponent")
	if health_component != null:
		if health_component.has_method("apply_damage"):
			health_component.call("apply_damage", amount)
		elif health_component.has_method("take_damage"):
			health_component.call("take_damage", amount)
	fall_damaged.emit(amount)


func update_camera_visuals(delta: float) -> void:
	ads.update_visuals(delta)
	_apply_ads_projection()
	if ads_view != null:
		ads_view.apply_ads(ads.amount(true))
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if ads_view != null and ads_view.rig != null:
		ads_view.rig.advance(delta, horiz_speed, is_on_floor(), motor.is_sprinting)
	var eff_offset: Vector3 = Vector3.ZERO
	var eff_rot: Vector3 = Vector3.ZERO
	if camera_effects != null:
		camera_effects.update_effects(delta, horiz_speed, is_on_floor())
		eff_offset = camera_effects.current_offset
		eff_rot = camera_effects.current_rotation
	if camera == null or head == null:
		return
	if is_inside_tree():
		var body_xform: Transform3D = get_global_transform_interpolated()
		var base_origin: Vector3 = body_xform * head.position
		var look_euler: Vector3 = Vector3(
			input_reader.pitch + eff_rot.x,
			input_reader.yaw + eff_rot.y,
			head.rotation.z + eff_rot.z
		)
		if weapon_hitscan != null:
			look_euler = weapon_hitscan.handling.aim_rotation(
				input_reader.pitch, input_reader.yaw, head.rotation.z) + eff_rot
		var look_basis: Basis = Basis.from_euler(look_euler)
		camera.global_transform = Transform3D(look_basis, base_origin + look_basis * eff_offset)
	else:
		camera.position = eff_offset
		camera.rotation = eff_rot


func _on_settings_changed() -> void:
	apply_settings()
