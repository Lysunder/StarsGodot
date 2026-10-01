class_name Waypoint
extends ModelObject
## One waypoint of a fleet (S03, S11, S12).
##
## The target is "none" (deep space), a planet (target_id = planet id), a fleet (target_owner,
## target_id = fleet number) or a space object of one kind (target_owner, target_id = number).

const TARGETS := ["none", "planet", "fleet", "minefield", "packet", "wormhole", "trader"]
const TASKS := [
	"none",
	"transport",
	"colonize",
	"remote_mine",
	"merge",
	"scrap",
	"lay_mines",
	"patrol",
	"route",
	"transfer",
]
## Warp value meaning "travel by stargate".
const WARP_STARGATE := 11

var x: int = 0
var y: int = 0
var target: String = "none"
var target_owner: int = -1
var target_id: int = -1
var warp: int = 0
var task: String = "none"
## Depends on the task (S11).
var task_data: Dictionary = {}

## Turn-only mark: stop following a fleet that jumped through a gate (S12).
var frozen: bool = false


func _init(p_x: int = 0, p_y: int = 0) -> void:
	x = p_x
	y = p_y


func _schema() -> Array:
	return [
		["x", Kind.INT],
		["y", Kind.INT],
		["target", Kind.ENUM, TARGETS],
		["target_owner", Kind.INT],
		["target_id", Kind.INT],
		["warp", Kind.INT],
		["task", Kind.ENUM, TASKS],
		["task_data", Kind.JSON],
	]
