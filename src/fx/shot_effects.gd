# Представление слушает симуляцию; ни один эффект не вызывает оружие или здоровье.
class_name ShotEffects
extends Node3D

@export var config: ShotFxConfig = preload("res://src/fx/default_shot_fx.tres")

var flashes: ObjectPool
var tracers: ObjectPool
var shells: ObjectPool
var impacts: ObjectPool
var decals: ShotDecals
var audio: ShotAudio
var marker: HitMarker
var assets: ShotFxAssets
var shots_presented: int = 0
var whizzes_presented: int = 0

var _listener: Camera3D
var _view: WeaponAdsView
var _local_shooter: bool = false
var _sources: Dictionary[WeaponHitscan, Weapon] = {}


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	set_process(false)


func setup(listener: Camera3D, local_shooter: bool, view: WeaponAdsView = null) -> void:
	_listener = listener
	_local_shooter = local_shooter
	_view = view
	if assets != null:
		return
	assets = ShotFxAssets.new()
	assets.build(config)
	flashes = _pool(config.flash_capacity, _create_flash)
	tracers = _pool(config.tracer_capacity, _create_visual.bind(ShotVisual.Kind.TRACER))
	shells = _pool(config.shell_capacity, _create_visual.bind(ShotVisual.Kind.SHELL))
	impacts = _pool(config.impact_capacity, _create_visual.bind(ShotVisual.Kind.IMPACT))
	decals = ShotDecals.new()
	add_child(decals)
	decals.setup(config, assets.hole)
	audio = ShotAudio.new()
	add_child(audio)
	audio.setup(config)
	if local_shooter:
		var canvas: CanvasLayer = CanvasLayer.new()
		canvas.layer = 11
		add_child(canvas)
		marker = HitMarker.new()
		marker.config = config
		canvas.add_child(marker)
	set_process(true)


func _pool(capacity: int, factory: Callable) -> ObjectPool:
	var pool: ObjectPool = ObjectPool.new()
	add_child(pool)
	pool.prewarm(capacity, factory)
	return pool


func _create_flash() -> MuzzleFlash:
	var flash: MuzzleFlash = MuzzleFlash.new()
	flash.setup(config, assets)
	return flash


func _create_visual(kind: ShotVisual.Kind) -> ShotVisual:
	var visual: ShotVisual = ShotVisual.new()
	visual.setup(config, assets, kind)
	return visual


func bind_weapon(weapon: Weapon, hitscan: WeaponHitscan) -> void:
	if _sources.has(hitscan):
		_sources[hitscan] = weapon
		return
	_sources[hitscan] = weapon
	hitscan.shot_traced.connect(_on_traced.bind(hitscan))
	hitscan.damage_applied.connect(present_damage)


func _on_traced(tick: int, pellet: int, direction: Vector3,
		hit: HitResult, source: WeaponHitscan) -> void:
	present_trace(_sources[source], tick, pellet, source.shot_origin, direction, hit)


# Можно вызвать для косметического события; сетевой транспорт сюда не входит.
func present_trace(weapon: Weapon, _tick: int, pellet: int, from: Vector3,
		direction: Vector3, hit: HitResult) -> void:
	if assets == null or weapon == null or weapon.data == null:
		return
	var end: Vector3 = hit.point if hit.hit else from + direction * weapon.data.hitscan_range
	var pose: Transform3D = _muzzle_pose(from, direction)
	if pellet == 0:
		shots_presented += 1
		_present_muzzle(weapon, pose)
	if shots_presented % maxi(config.tracer_every, 1) == 0:
		var tracer: ShotVisual = tracers.acquire() as ShotVisual
		if tracer != null:
			tracer.play_tracer(pose.origin, end)
	if hit.hit:
		_present_impact(hit)
	if not _local_shooter and is_instance_valid(_listener) and pellet == 0:
		var point: Vector3 = ShotAudio.whiz_point(from, end, _listener.global_position, config)
		if point.is_finite():
			audio.play_at(assets.whiz_sound, point)
			whizzes_presented += 1


func _muzzle_pose(from: Vector3, direction: Vector3) -> Transform3D:
	if _local_shooter and is_instance_valid(_view) and is_instance_valid(_view.model):
		return _view.model.global_transform * Transform3D(Basis.IDENTITY, config.muzzle_offset)
	var helper: Vector3 = Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP
	var orientation: Basis = Basis.looking_at(direction, helper)
	return Transform3D(orientation, from + orientation * config.world_muzzle_offset)


func _present_muzzle(weapon: Weapon, pose: Transform3D) -> void:
	if _local_shooter:
		var material: BaseMaterial3D = assets.flash.material as BaseMaterial3D
		var settings: ViewmodelConfig = weapon.data.viewmodel_config
		material.use_fov_override = true
		material.fov_override = settings.fov if settings != null else ViewmodelRig.DEFAULT_CONFIG.fov
		material.no_depth_test = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.render_priority = ViewmodelRig.RENDER_PRIORITY
	var flash: MuzzleFlash = flashes.acquire() as MuzzleFlash
	if flash != null:
		flash.pulse(pose, Engine.get_process_frames())
	var shell: ShotVisual = shells.acquire() as ShotVisual
	if shell != null:
		shell.play_shell(pose * Transform3D(Basis.IDENTITY, config.shell_offset - config.muzzle_offset))
	var sound: AudioStream = weapon.data.fire_sound
	audio.play_at(sound if sound != null else assets.fire_sound, pose.origin)


func _present_impact(hit: HitResult) -> void:
	var surface: ShotSurface.Type = ShotSurface.resolve(hit)
	var impact: ShotVisual = impacts.acquire() as ShotVisual
	if impact != null:
		impact.play_impact(hit.point, hit.normal, surface)
	decals.stamp(hit.point, hit.normal, surface)


func present_damage(event: DamageEvent) -> void:
	if marker == null or event.damage <= 0.0:
		return
	var headshot: bool = event.zone == HitboxZone.HEAD
	marker.confirm(headshot)
	if is_instance_valid(_listener):
		audio.play_at(assets.headshot_sound if headshot else assets.hit_sound, _listener.global_position)


func advance(delta: float) -> void:
	if assets == null or not is_finite(delta) or delta <= 0.0:
		return
	for item: MuzzleFlash in flashes.items:
		item.advance(delta, Engine.get_process_frames())
	for item: ShotVisual in tracers.items:
		item.advance(delta)
	for item: ShotVisual in shells.items:
		item.advance(delta)
	for item: ShotVisual in impacts.items:
		item.advance(delta)


func _process(delta: float) -> void:
	advance(delta)
