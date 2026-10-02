extends GdUnitTestSuite
## Spec S06: planet value for a race, habitability points and advantage points. The preset races
## are the original's race wizard presets; Humanoid's 25 points left matches the original, the
## others come from the harness reference implementation (S06 "Worked examples").

const HUMANOID := {
	"prt": "JoaT",
	"low": [15, 15, 15],
	"center": [50, 50, 50],
	"high": [85, 85, 85],
	"growth": 15,
	"pe": 10,
	"fact": [10, 10, 10],
	"mine": [10, 5, 10],
	"research": [1, 1, 1, 1, 1, 1],
}

## [race, habitability points, advantage points left]
const PRESETS := [
	[HUMANOID, 3293786, 25],
	[
		{
			"prt": "IT",
			"lrt": ["IFE", "TT", "CE", "NAS"],
			"low": [10, 35, 13],
			"center": [33, 58, 33],
			"high": [56, 81, 53],
			"growth": 20,
			"pe": 10,
			"fact": [10, 9, 17],
			"mine": [10, 9, 10],
			"research": [0, 0, 2, 1, 1, 2],
			"cheap_factories": true,
		},
		1890954,
		32,
	],
	[
		{
			"prt": "WM",
			"lrt": ["ISB", "CE", "RS"],
			"low": [-1, 0, 70],
			"center": [-1, 50, 85],
			"high": [-1, 100, 100],
			"growth": 10,
			"pe": 10,
			"fact": [10, 10, 10],
			"mine": [9, 10, 6],
			"research": [2, 2, 2, 2, 1, 0],
		},
		4191058,
		43,
	],
	[
		{
			"prt": "SS",
			"lrt": ["ARM", "ISB"],
			"low": [-1, 12, 0],
			"center": [-1, 50, 50],
			"high": [-1, 88, 100],
			"growth": 10,
			"pe": 9,
			"fact": [10, 10, 10],
			"mine": [10, 15, 5],
			"research": [0, 0, 0, 0, 0, 0],
			"techs_at_3": true,
		},
		8420542,
		11,
	],
	[
		{
			"prt": "HE",
			"lrt": ["IFE", "UR", "OBRM", "BET"],
			"low": [-1, -1, -1],
			"center": [-1, -1, -1],
			"high": [-1, -1, -1],
			"growth": 6,
			"pe": 8,
			"fact": [12, 12, 15],
			"mine": [10, 9, 10],
			"research": [1, 1, 2, 2, 1, 0],
		},
		23958000,
		9,
	],
	[
		{
			"prt": "SD",
			"lrt": ["ARM", "MA", "NRSE", "CE", "NAS"],
			"low": [0, 0, 70],
			"center": [15, 50, 85],
			"high": [30, 100, 100],
			"growth": 7,
			"pe": 7,
			"fact": [11, 10, 18],
			"mine": [10, 10, 10],
			"research": [2, 0, 2, 2, 2, 2],
		},
		1248321,
		7,
	],
	[
		{
			"prt": "HE",
			"low": [17, 17, 17],
			"center": [50, 50, 50],
			"high": [83, 83, 83],
			"growth": 15,
			"pe": 10,
			"fact": [10, 10, 10],
			"mine": [10, 3, 10],
			"research": [1, 1, 1, 1, 1, 1],
		},
		2938342,
		12,
	],
]

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


## low/center/high as [g, t, r]; -1 everywhere for an immune axis.
static func _race(spec: Dictionary) -> Race:
	var race := Race.new()
	race.primary_trait = "trait.prt." + spec["prt"]
	var lesser: Array[String] = []
	for abbr: String in spec.get("lrt", []):
		lesser.append("trait.lrt." + abbr)
	lesser.sort()
	race.lesser_traits = lesser
	race.hab_low.assign(spec["low"])
	race.hab_center.assign(spec["center"])
	race.hab_high.assign(spec["high"])
	race.growth_rate = spec["growth"]
	race.resources_per_colonist = spec["pe"]
	race.factory_output = spec["fact"][0]
	race.factory_cost = spec["fact"][1]
	race.factories_operated = spec["fact"][2]
	race.mine_output = spec["mine"][0]
	race.mine_cost = spec["mine"][1]
	race.mines_operated = spec["mine"][2]
	race.research_costs.assign(spec["research"])
	race.cheap_factories = spec.get("cheap_factories", false)
	race.techs_start_at_3 = spec.get("techs_at_3", false)
	return race


func test_presets_hab_points() -> void:
	for preset: Array in PRESETS:
		var race := _race(preset[0])
		(
			assert_int(RaceMath.hab_points(race, _content))
			. override_failure_message("%s: hab points" % race.primary_trait)
			. is_equal(preset[1])
		)


func test_presets_advantage_points() -> void:
	for preset: Array in PRESETS:
		var race := _race(preset[0])
		(
			assert_int(RaceMath.advantage_points(race, _content))
			. override_failure_message(
				"%s %s: advantage points" % [race.primary_trait, race.lesser_traits]
			)
			. is_equal(preset[2])
		)


func test_planet_value() -> void:
	var humanoid := _race(HUMANOID)
	var insectoid := _race(PRESETS[2][0])
	## [environment, Humanoid value, Insectoid value]
	var cases := [
		[[50, 50, 50], 100, -15],
		[[15, 85, 50], 14, -15],
		[[70, 30, 60], 47, -10],
		[[10, 50, 50], -5, -15],
		[[0, 100, 0], -45, -15],
		[[20, 40, 90], -5, 84],
		[[1, 99, 99], -42, 17],
	]
	for c: Array in cases:
		var env: Array[int] = []
		env.assign(c[0])
		assert_int(Habitability.value(env, humanoid)).is_equal(c[1])
		assert_int(Habitability.value(env, insectoid)).is_equal(c[2])


func test_trait_param_lookup() -> void:
	var race := _race(PRESETS[1][0])  # IT with IFE, TT, CE, NAS
	assert_int(RaceMath.trait_param(race, _content, "race.hab_terraform_reach_1", 5)).is_equal(8)
	assert_int(RaceMath.trait_param(race, _content, "race.ap_nas_penalty", 0)).is_equal(0)
	assert_int(RaceMath.trait_param(_race(HUMANOID), _content, "race.ap_nas_penalty", 0)).is_equal(
		40
	)
	assert_int(RaceMath.trait_param(race, _content, "no.such.param", 7)).is_equal(7)


func test_invalid_race_is_negative() -> void:
	var spec: Dictionary = HUMANOID.duplicate(true)
	spec["lrt"] = ["IFE", "ISB", "UR", "MA"]  # four expensive traits
	assert_int(RaceMath.advantage_points(_race(spec), _content)).is_less(0)
