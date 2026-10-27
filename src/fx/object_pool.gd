# Фиксированное кольцо: при исчерпании переиспользуется самый старый объект.
class_name ObjectPool
extends Node

var items: Array[Node] = []
var acquired_count: int = 0
var _cursor: int = 0


func prewarm(capacity: int, factory: Callable) -> void:
	if not items.is_empty():
		return
	for index: int in range(maxi(capacity, 0)):
		var item: Node = factory.call() as Node
		add_child(item)
		items.append(item)


func acquire() -> Node:
	if items.is_empty():
		return null
	var item: Node = items[_cursor]
	_cursor = (_cursor + 1) % items.size()
	acquired_count += 1
	return item
