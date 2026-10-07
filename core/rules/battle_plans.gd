class_name BattlePlans
extends RefCounted
## Battle plans (S11 `battle_plan` orders, S16): whom a fleet's plan attacks.
##
## A plan's `attack` (`Fleet_WillAttackPlayer@10e8:6db6`): 0 nobody, 1 enemies, 2 enemies and
## neutrals, 3 everyone, ATTACK_PLAYER + n player n alone.

const ATTACK_ENEMIES := 1
const ATTACK_NOT_FRIENDS := 2
const ATTACK_EVERYONE := 3
const ATTACK_PLAYER := 4
const ATTACK_MASK := 0x1F


## The battle plan numbered `number` of `owner`, or {} when there is none.
static func plan(owner: Player, number: int) -> Dictionary:
	for p: Variant in owner.battle_plans:
		if p is Dictionary and int(p.get("number", -1)) == number:
			return p
	return {}


## The fleet's battle plan attacks `player`'s ships and minefields.
static func attacks(state: GameState, fleet: Fleet, player: int) -> bool:
	var owner := state.player(fleet.owner)
	var attack := int(plan(owner, fleet.battle_plan).get("attack", 0)) & ATTACK_MASK
	var relation := owner.relations[player] if player < owner.relations.size() else "neutral"
	match attack:
		ATTACK_ENEMIES:
			return relation == "enemy"
		ATTACK_NOT_FRIENDS:
			return relation != "friend"
		ATTACK_EVERYONE:
			return true
	return attack == ATTACK_PLAYER + player
