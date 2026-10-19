class_name StandardRuleset
extends RefCounted
## The Standard formulas: 2.6i's rules with the known bugs fixed (S25). Formula ids follow the
## specs.

const ARMOR_DAMAGE := "battle.armor_damage"
const STARBASE_DAMAGE := "battle.starbase_damage"
const MINE_TOP_UP := "minefield.top_up"
const SHIP_RATING := "score.ship_rating"
const PLAYER_SCORE := "score.player"


static func build() -> Ruleset:
	var ruleset := Ruleset.new()
	ruleset.register(ARMOR_DAMAGE, ArmorDamage.ships)
	ruleset.register(STARBASE_DAMAGE, ArmorDamage.starbase)
	ruleset.register(MINE_TOP_UP, Minefields.top_up_share)
	ruleset.register(SHIP_RATING, Score.ship_rating)
	ruleset.register(PLAYER_SCORE, Score.record)
	ruleset.register(PlanetEconomy.POP_GROWTH, PlanetEconomy.standard_growth)
	ruleset.register(ClassicCybertrons.MARKS_BASE, ClassicCybertrons.marks_base)
	ruleset.register(ClassicCybertrons.PACKET_RECORD, ClassicCybertrons.packet_record)
	ruleset.register(ClassicCybertrons.SECTOR_REACH, ClassicCybertrons.sector_reach)
	ruleset.register(ClassicCybertrons.LONG_TARGET, ClassicCybertrons.long_target)
	ruleset.register(ClassicMacinti.SCOUT_CAP_DESIGN, ClassicMacinti.scout_cap_design)
	ruleset.register(ClassicWorld.EMPTY_SLOT_TURN, ClassicWorld.no_empty_slot_turn)
	ruleset.register(ClassicMacinti.ALL_RICH, ClassicMacinti.all_rich)
	return ruleset
