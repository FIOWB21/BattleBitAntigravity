class_name PredictionConfig
extends Resource

@export_range(8, 512) var buffer_capacity: int = 128
@export_range(0.001, 0.1) var position_epsilon: float = 0.02
@export_range(0.001, 0.1) var velocity_epsilon: float = 0.02
@export_range(0.00001, 0.01) var state_epsilon: float = 0.0001
@export_range(0.01, 0.5) var smoothing_seconds: float = 0.1
@export_range(0.1, 10.0) var teleport_distance: float = 2.0
