class_name StandardRuleset
extends RefCounted
## The Standard formulas: 2.6i's rules with the known bugs fixed (S25). Formula ids follow the
## specs.

const ARMOR_DAMAGE := "battle.armor_damage"
const STARBASE_DAMAGE := "battle.starbase_damage"
const MINE_TOP_UP := "minefield.top_up"


static func build() -> Ruleset:
	var ruleset := Ruleset.new()
	ruleset.register(ARMOR_DAMAGE, ArmorDamage.ships)
	ruleset.register(STARBASE_DAMAGE, ArmorDamage.starbase)
	ruleset.register(MINE_TOP_UP, Minefields.top_up_share)
	return ruleset
