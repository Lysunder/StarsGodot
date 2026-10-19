class_name ModApi
extends RefCounted
## What a script mod's entry script gets while the mods load (MODDING.md §6, §7): `_mod_init(api)`
## may replace or add formulas and change the turn's phases. Everything it does is recorded in the
## game's content (ContentRegistry), never in a global, and only while the mods load.
##
## Script mods are trusted code (MODDING.md §12): they load only once the player trusts that
## version of the mod (ModLoader.trusted). They must keep the determinism rules (MODDING.md §8):
## integer math, randomness only from their own stream (`stream`, through TurnContext.rng), no
## clocks, files or OS calls, and collections in a defined order.

## The mod this api belongs to.
var mod_id: String
## The game's formulas, to replace or add to (Ruleset).
var formulas: Ruleset
## The random stream this mod draws from in its phases: "mod.<id>" (RngStreams).
var stream: String

var _content: ContentRegistry


func _init(p_mod_id: String, content: ContentRegistry) -> void:
	mod_id = p_mod_id
	_content = content
	formulas = content.ruleset
	stream = "mod." + p_mod_id


## Runs `phase` right after the phase with id `target` (S02 ids, or another mod's).
func insert_after(target: String, phase: Phase) -> void:
	_content.phase_edits.append(["insert_after", target, phase, mod_id])


func insert_before(target: String, phase: Phase) -> void:
	_content.phase_edits.append(["insert_before", target, phase, mod_id])


## Runs `phase` instead of the phase with id `target`.
func replace_phase(target: String, phase: Phase) -> void:
	_content.phase_edits.append(["replace", target, phase, mod_id])


## Leaves the phase with id `target` out of the turn.
func disable_phase(target: String) -> void:
	_content.phase_edits.append(["disable", target, null, mod_id])
