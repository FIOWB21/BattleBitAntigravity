# Структура ввода игрока за один физический тик.
class_name PlayerInput
extends RefCounted

const BTN_JUMP: int = 1 << 0
const BTN_SPRINT: int = 1 << 1
const BTN_CROUCH: int = 1 << 2
const BTN_PRONE: int = 1 << 3
const BTN_FIRE: int = 1 << 4
const BTN_AIM: int = 1 << 5
const BTN_RELOAD: int = 1 << 6
const BTN_LEAN_L: int = 1 << 7
const BTN_LEAN_R: int = 1 << 8

var tick: int = 0
var move: Vector2 = Vector2.ZERO  # x: вправо, y: вперёд, длина <= 1
var yaw: float = 0.0
var pitch: float = 0.0
var buttons: int = 0
var weapon_slot: int = 0  # 1..5, 0 — нет команды.
var weapon_cycle: int = 0  # -1 / +1, обход заполненных слотов.
var last_weapon: bool = false
var throw_grenade: bool = false
var melee: bool = false


func pressed(btn: int) -> bool:
	return (buttons & btn) != 0
