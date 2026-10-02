class_name TurnPipeline
extends RefCounted
## The ordered phases of a turn (spec S02; MODDING §7). Mods insert, replace or disable phases
## by id.

var _phases: Array[Phase] = []
var _disabled := {}


func add(phase: Phase) -> void:
	assert(index_of(phase.id) < 0, "duplicate phase id %s" % phase.id)
	_phases.append(phase)


func insert_before(target_id: String, phase: Phase) -> void:
	_phases.insert(_require(target_id), phase)


func insert_after(target_id: String, phase: Phase) -> void:
	_phases.insert(_require(target_id) + 1, phase)


func replace(target_id: String, phase: Phase) -> void:
	_phases[_require(target_id)] = phase


func disable(target_id: String) -> void:
	_require(target_id)
	_disabled[target_id] = true


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for p in _phases:
		out.append(p.id)
	return out


func phase(target_id: String) -> Phase:
	return _phases[_require(target_id)]


func index_of(target_id: String) -> int:
	for i in _phases.size():
		if _phases[i].id == target_id:
			return i
	return -1


func run(ctx: TurnContext) -> void:
	for p in _phases:
		if not _disabled.has(p.id):
			p.run(ctx)


func _require(target_id: String) -> int:
	var i := index_of(target_id)
	assert(i >= 0, "no phase %s" % target_id)
	return i
