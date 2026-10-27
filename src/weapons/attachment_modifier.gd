# Одна арифметическая операция над числовым параметром оружия.
class_name AttachmentModifier
extends Resource

enum Operation { ADD, MUL }

@export var stat: StringName
@export var op: Operation = Operation.ADD
@export var value: float = 0.0
