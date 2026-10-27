# Только параметры процедурного представления; игровые профили задают радиус/срок.
class_name ProjectileFxConfig
extends Resource

@export var effect_capacity: int = 16
@export var projectile_radius: float = 0.07
@export var projectile_color: Color = Color(0.24, 0.3, 0.12)
@export var blast_opacity: float = 0.75
@export var smoke_opacity: float = 0.97
@export var smoke_growth_time: float = 1.5
@export var smoke_fade_time: float = 2.0
@export var ring_frequency: float = 2400.0
@export var ring_volume_db: float = -24.0
@export var sample_rate: int = 22050
@export var blast_tone: float = 65.0
@export var blast_duration: float = 0.35
@export var blast_volume_db: float = -8.0
@export var stun_opacity: float = 0.35
@export var stun_color: Color = Color(0.2, 0.25, 0.3)
