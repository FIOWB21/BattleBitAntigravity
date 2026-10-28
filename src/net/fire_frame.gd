# A preallocated record of server aim, separate from target hitboxes.
class_name FireFrame
extends RefCounted

var tick: int = -1
var seed: int = 0
var view_tick: int = 0
var requested: bool = false
var recorded: bool = false
var consumed: bool = false
var allowed: bool = false
var aim: Transform3D = Transform3D.IDENTITY
var spread: float = 0.0
var weapon: Weapon
var hitscan: WeaponHitscan


func reset(input_tick: int) -> void:
	tick = input_tick
	view_tick = 0
	requested = false
	recorded = false
	consumed = false
	allowed = false
	weapon = null
	hitscan = null
