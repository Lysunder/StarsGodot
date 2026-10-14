class_name Palette
extends RefCounted
## The colours that carry meaning (M11 step 10, accessibility): whose planets and ships, good and
## bad values, the minerals, the production estimate, the environment axes. Three palettes: the
## standard one, one for red-green colour blindness (protanopia, deuteranopia) and one for
## blue-yellow (tritanopia), built from the Okabe-Ito colours; the pairs that must stay apart were
## checked with the Machado 2009 simulation (CIELAB distance at least 20 in the palette's own
## kinds). UiSettings picks the palette; `color` reads it.

const STANDARD := "standard"
const RED_GREEN := "red_green"
const BLUE_YELLOW := "blue_yellow"
const MODES := [STANDARD, RED_GREEN, BLUE_YELLOW]
const MODE_NAMES := ["Standard", "Red-green safe", "Blue-yellow safe"]

## Roles. On the dark map: MINE, OTHER, FLEET, SELECTED, GOOD, BAD. As text or bars on the light
## panes: TEXT_GOOD, TEXT_BAD, TEXT_POOR, the cargo kinds, the queue estimate, the environment axes.
const MINE := "mine"
const OTHER := "other"
const FLEET := "fleet"
const SELECTED := "selected"
const GOOD := "good"
const BAD := "bad"
const TEXT_GOOD := "text_good"
const TEXT_BAD := "text_bad"
const TEXT_POOR := "text_poor"
const IRONIUM := "ironium"
const BORANIUM := "boranium"
const GERMANIUM := "germanium"
const COLONISTS := "colonists"
const FUEL := "fuel"
const QUEUE_ALL := "queue_all"
const QUEUE_SOME := "queue_some"
const QUEUE_NEVER := "queue_never"
const GRAVITY := "gravity"
const TEMPERATURE := "temperature"
const RADIATION := "radiation"
## Cargo kinds in cargo order (ironium, boranium, germanium, colonists, fuel).
const CARGO := [IRONIUM, BORANIUM, GERMANIUM, COLONISTS, FUEL]
const AXES := [GRAVITY, TEMPERATURE, RADIATION]

const COLORS := {
	STANDARD:
	{
		MINE: Color(0.3, 0.85, 0.35),
		OTHER: Color(0.9, 0.3, 0.25),
		FLEET: Color(0.45, 0.75, 1.0),
		SELECTED: Color(1.0, 0.9, 0.3),
		GOOD: Color(0.2, 0.85, 0.3),
		BAD: Color(0.9, 0.2, 0.2),
		TEXT_GOOD: Color("007f00"),
		TEXT_BAD: Color("ff0000"),
		TEXT_POOR: Color("7f7f00"),
		IRONIUM: Color("0000ff"),
		BORANIUM: Color("007f00"),
		GERMANIUM: Color("ffff00"),
		COLONISTS: Color("ffffff"),
		FUEL: Color("ff0000"),
		QUEUE_ALL: Color("007f00"),
		QUEUE_SOME: Color("0000ff"),
		QUEUE_NEVER: Color("ff0000"),
		GRAVITY: Color("0000c0"),
		TEMPERATURE: Color("c00000"),
		RADIATION: Color("00a000"),
	},
	RED_GREEN:
	{
		MINE: Color("56b4e9"),
		OTHER: Color("e69f00"),
		FLEET: Color("e8e8e8"),
		SELECTED: Color("f0e442"),
		GOOD: Color("56b4e9"),
		BAD: Color("e69f00"),
		TEXT_GOOD: Color("0072b2"),
		TEXT_BAD: Color("d55e00"),
		TEXT_POOR: Color("555555"),
		IRONIUM: Color("0072b2"),
		BORANIUM: Color("d55e00"),
		GERMANIUM: Color("f0e442"),
		COLONISTS: Color("ffffff"),
		FUEL: Color("cc79a7"),
		QUEUE_ALL: Color("0072b2"),
		QUEUE_SOME: Color("cc79a7"),
		QUEUE_NEVER: Color("d55e00"),
		GRAVITY: Color("0072b2"),
		TEMPERATURE: Color("d55e00"),
		RADIATION: Color("f0e442"),
	},
	BLUE_YELLOW:
	{
		MINE: Color("2ec27e"),
		OTHER: Color("e8453c"),
		FLEET: Color("e8e8e8"),
		SELECTED: Color("ffd24d"),
		GOOD: Color("2ec27e"),
		BAD: Color("e8453c"),
		TEXT_GOOD: Color("007a3d"),
		TEXT_BAD: Color("d00000"),
		TEXT_POOR: Color("7a5c00"),
		IRONIUM: Color("1f4fd1"),
		BORANIUM: Color("d55e00"),
		GERMANIUM: Color("f0e442"),
		COLONISTS: Color("ffffff"),
		FUEL: Color("a0008c"),
		QUEUE_ALL: Color("007a3d"),
		QUEUE_SOME: Color("a0008c"),
		QUEUE_NEVER: Color("d00000"),
		GRAVITY: Color("1f4fd1"),
		TEMPERATURE: Color("d00000"),
		RADIATION: Color("007a3d"),
	},
}

## The palette in use (UiSettings sets it).
static var mode: String = STANDARD


static func color(role: String) -> Color:
	return COLORS.get(mode, COLORS[STANDARD])[role]


## Cargo kind `i` (cargo order).
static func cargo(i: int) -> Color:
	return color(CARGO[i])


## Environment axis `axis` (gravity, temperature, radiation).
static func axis(i: int) -> Color:
	return color(AXES[i])
