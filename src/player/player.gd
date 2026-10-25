# Узел игрока (CharacterBody3D), связывающий LocalInputReader и PlayerMotor.
class_name Player
extends CharacterBody3D

const DEFAULT_MOVEMENT_PATH: String = "res://src/player/default_movement.tres"

@export var movement_config: MovementConfig = preload(DEFAULT_MOVEMENT_PATH)
@export var is_local_player: bool = true
@export var stance: int = MovementConfig.STANCE_STAND

var motor: PlayerMotor = PlayerMotor.new()
var input_reader: LocalInputReader = LocalInputReader.new()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D


func _ready() -> void:
	if movement_config == null:
		movement_config = load(DEFAULT_MOVEMENT_PATH) as MovementConfig
	floor_max_angle = deg_to_rad(movement_config.max_slope_angle) + PlayerMotor.SLOPE_EPSILON_RAD
	input_reader.yaw = rotation.y


func _physics_process(delta: float) -> void:
	if not is_local_player:
		return
	var inp: PlayerInput = input_reader.read_input()
	step_simulation(inp, delta)
	Game.debug["player_position"] = global_position


func step_simulation(inp: PlayerInput, delta: float) -> void:
	motor.simulate(self, inp, movement_config, stance, delta)
