class_name PlayerSnapshot
extends RefCounted

const STANCE_MASK: int = 3
const GROUNDED: int = 1 << 2
const SPRINTING: int = 1 << 3
const AIMING: int = 1 << 4
const DEAD: int = 1 << 5
const DOWNED: int = 1 << 6
const RELOADING: int = 1 << 7
const FLAG_MASK: int = (1 << 8) - 1

var tick: int = 0
var peer_id: int = 0
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var flags: int = 0
var weapon_id: int = 0


func copy_from(source: PlayerSnapshot) -> void:
	tick = source.tick
	peer_id = source.peer_id
	position = source.position
	velocity = source.velocity
	yaw = source.yaw
	pitch = source.pitch
	flags = source.flags
	weapon_id = source.weapon_id
