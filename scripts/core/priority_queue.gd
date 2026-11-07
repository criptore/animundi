## Binary min-heap of (priority, int value) pairs, stored in packed arrays for speed.
## Ties pop in a deterministic order, so the same pushes always give the same pops.
extends RefCounted

var _priorities := PackedFloat32Array()
var _values := PackedInt32Array()


func size() -> int:
	return _values.size()


func push(priority: float, value: int) -> void:
	_priorities.append(priority)
	_values.append(value)
	var i := _values.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _priorities[parent] <= _priorities[i]:
			break
		_swap(i, parent)
		i = parent


## Removes and returns the value with the lowest priority. The queue must not be empty.
func pop() -> int:
	var top := _values[0]
	var last := _values.size() - 1
	_priorities[0] = _priorities[last]
	_values[0] = _values[last]
	_priorities.resize(last)
	_values.resize(last)
	var i := 0
	while true:
		var left := 2 * i + 1
		if left >= last:
			break
		var smallest := left
		var right := left + 1
		if right < last and _priorities[right] < _priorities[left]:
			smallest = right
		if _priorities[i] <= _priorities[smallest]:
			break
		_swap(i, smallest)
		i = smallest
	return top


func _swap(a: int, b: int) -> void:
	var p := _priorities[a]
	_priorities[a] = _priorities[b]
	_priorities[b] = p
	var v := _values[a]
	_values[a] = _values[b]
	_values[b] = v
