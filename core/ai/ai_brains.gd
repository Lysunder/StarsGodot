class_name AiBrains
extends RefCounted
## The brains a personality can name (spec S22 "Personalities"): built into the game, by id.
## Script mods will add their own (M14).

const IDLE := "idle"
const IDS := [IDLE]


static func has(id: String) -> bool:
	return IDS.has(id)


## A new brain for `id`, or null for an unknown one.
static func create(id: String) -> AiPlayer:
	match id:
		IDLE:
			return AiPlayer.new()
	return null
