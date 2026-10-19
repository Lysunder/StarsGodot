extends RefCounted
## Validator test fixture: reads the clock and changes a phase that doesn't exist.


func _mod_init(api: ModApi) -> void:
	api.disable_phase("no.such.phase")


func roll() -> int:
	return Time.get_ticks_msec() % 6
