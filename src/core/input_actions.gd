# Константы действий карты ввода (InputMap).
class_name InputActions
extends RefCounted

const MOVE_FORWARD: StringName = &"move_forward"
const MOVE_BACK: StringName = &"move_back"
const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const JUMP: StringName = &"jump"
const SPRINT: StringName = &"sprint"
const CROUCH: StringName = &"crouch"
const PRONE: StringName = &"prone"
const LEAN_LEFT: StringName = &"lean_left"
const LEAN_RIGHT: StringName = &"lean_right"
const FIRE: StringName = &"fire"
const AIM: StringName = &"aim"
const RELOAD: StringName = &"reload"
const SWITCH_WEAPON_NEXT: StringName = &"switch_weapon_next"
const SWITCH_WEAPON_PREV: StringName = &"switch_weapon_prev"
const SWITCH_WEAPON_LAST: StringName = &"switch_weapon_last"
const SLOT_1: StringName = &"slot_1"
const SLOT_2: StringName = &"slot_2"
const SLOT_3: StringName = &"slot_3"
const SLOT_4: StringName = &"slot_4"
const SLOT_5: StringName = &"slot_5"
const USE_GADGET: StringName = &"use_gadget"
const INTERACT: StringName = &"interact"
const MELEE: StringName = &"melee"
const THROW_GRENADE: StringName = &"throw_grenade"
const SCOREBOARD: StringName = &"scoreboard"
const CHAT: StringName = &"chat"
const VOICE: StringName = &"voice"
const MAP: StringName = &"map"
const PAUSE_MENU: StringName = &"pause_menu"
const SQUAD_MENU: StringName = &"squad_menu"
const SPOT: StringName = &"spot"
const VEHICLE_SEAT_NEXT: StringName = &"vehicle_seat_next"
const VEHICLE_EXIT: StringName = &"vehicle_exit"

const ALL_ACTIONS: Array[StringName] = [
	MOVE_FORWARD,
	MOVE_BACK,
	MOVE_LEFT,
	MOVE_RIGHT,
	JUMP,
	SPRINT,
	CROUCH,
	PRONE,
	LEAN_LEFT,
	LEAN_RIGHT,
	FIRE,
	AIM,
	RELOAD,
	SWITCH_WEAPON_NEXT,
	SWITCH_WEAPON_PREV,
	SWITCH_WEAPON_LAST,
	SLOT_1,
	SLOT_2,
	SLOT_3,
	SLOT_4,
	SLOT_5,
	USE_GADGET,
	INTERACT,
	MELEE,
	THROW_GRENADE,
	SCOREBOARD,
	CHAT,
	VOICE,
	MAP,
	PAUSE_MENU,
	SQUAD_MENU,
	SPOT,
	VEHICLE_SEAT_NEXT,
	VEHICLE_EXIT,
]
