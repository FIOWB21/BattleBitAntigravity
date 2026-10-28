class_name MapData
extends Resource

@export var id: StringName = &"testbed"
@export var scene: PackedScene
@export var spawn_path: NodePath = ^"PlayerSpawn"
@export var offline_paths: Array[NodePath] = [^"Player", ^"HUD", ^"DebugOverlay", ^"Targets", ^"AmmoBox"]
@export var spawn_spacing: float = 2.0
@export var spawn_columns: int = 3
@export var spawn_row_spacing: float = 4.0
@export var snapshot_config: SnapshotConfig = preload("res://src/net/default_snapshot.tres")


func is_valid() -> bool:
	return not id.is_empty() and scene != null and not spawn_path.is_empty() \
		and spawn_columns > 0 and is_finite(spawn_spacing) and spawn_spacing > 0.0 \
		and is_finite(spawn_row_spacing) and spawn_row_spacing > 0.0 \
		and snapshot_config != null and snapshot_config.is_valid()


func spawn_offset(index: int) -> Vector3:
	var slot: int = index % spawn_columns
	@warning_ignore("integer_division")
	var column: int = (slot + 1) / 2 * (1 if slot % 2 == 1 else -1)
	@warning_ignore("integer_division")
	var row: int = index / spawn_columns
	return Vector3(float(column) * spawn_spacing, 0.0, float(row - absi(column)) * spawn_row_spacing)
