extends SceneTree
## Turn generation benchmark (plan M15 performance target: a huge universe with 16 players turns
## in under 5 s). Plays an AI-only game (an idle human and 15 computer players of every brain in
## turn) and reports, every `report` turns, the time of the AI step, of the turn's generation, and
## the slowest phases and computer players so far.
##
## Usage: godot --headless --path . --script res://tools/bench.gd --
##   [turns] [size] [players] [report] [save path]
## size: tiny, small, medium, large or huge (default huge); players default 16. With a save path the
## game reached is saved there (to profile a late turn on its own).

const SEED := 777
const BRAINS := [
	"robotoids", "turindrones", "automitrons", "rototills", "cybertrons", "macinti", "baseline"
]
const SHOWN := 8

## Milliseconds spent in each phase and by each brain, over all turns.
var _phase_ms := {}
var _brain_ms := {}


## A phase that times the one it wraps.
class TimedPhase:
	extends Phase
	var inner: Phase
	var totals: Dictionary

	func _init(p_inner: Phase, p_totals: Dictionary) -> void:
		super(p_inner.id)
		inner = p_inner
		totals = p_totals

	func run(ctx: TurnContext) -> void:
		var t := Time.get_ticks_usec()
		inner.run(ctx)
		totals[id] = totals.get(id, 0) + (Time.get_ticks_usec() - t) / 1000.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var turns := int(args[0]) if args.size() > 0 else 50
	var size := NewGame.SIZES.find(args[1]) if args.size() > 1 else 4
	var players := int(args[2]) if args.size() > 2 else 16
	var report := int(args[3]) if args.size() > 3 else 10
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	var content: ContentRegistry = r.registry
	var options := NewGame.Options.new()
	options.size = size
	options.seed = SEED
	for i in players - 1:
		var brain: String = BRAINS[i % BRAINS.size()]
		var o := {"ai": brain, "level": 3, "personality": {}}
		if brain == AiBrains.BASELINE:
			o["personality"] = PersonalityFile.make("Baseline", AiBrains.BASELINE)
			o["ai"] = NewGame.personality_key(o["personality"])
		options.opponents.append(o)
	var t0 := Time.get_ticks_msec()
	var state := NewGame.create(content, options)
	state.player(0).active = false
	print(
		(
			"%s universe, %d players, %d planets: created in %d ms"
			% [NewGame.SIZES[size], players, state.planets.size(), Time.get_ticks_msec() - t0]
		)
	)
	var pipeline := StandardTurn.pipeline()
	for id in pipeline.ids():
		pipeline.replace(id, TimedPhase.new(pipeline.phase(id), _phase_ms))
	var ai_total := 0.0
	var gen_total := 0.0
	var ai_window := 0.0
	var gen_window := 0.0
	var worst_gen := 0.0
	for t in turns:
		var a := Time.get_ticks_usec()
		var sets := _ai_step(state, content)
		var ai_ms := (Time.get_ticks_usec() - a) / 1000.0
		var g := Time.get_ticks_usec()
		_generate(state, content, sets, pipeline)
		var gen_ms := (Time.get_ticks_usec() - g) / 1000.0
		ai_total += ai_ms
		gen_total += gen_ms
		ai_window += ai_ms
		gen_window += gen_ms
		worst_gen = maxf(worst_gen, gen_ms)
		if (t + 1) % report == 0 or t == turns - 1:
			var n := report if (t + 1) % report == 0 else (t + 1) % report
			print(
				(
					"turns to %d: AI %.0f ms, generation %.0f ms a turn (fleets %d)"
					% [state.turn, ai_window / n, gen_window / n, state.fleets.size()]
				)
			)
			ai_window = 0.0
			gen_window = 0.0
	print(
		(
			"average over %d turns: AI %.0f ms, generation %.0f ms; slowest generation %.0f ms"
			% [turns, ai_total / turns, gen_total / turns, worst_gen]
		)
	)
	if args.size() > 4:
		SaveStore.write(args[4], state, "bench")
	_top("phases", _phase_ms, turns)
	_top("computer players by brain", _brain_ms, turns)
	quit()


## ComputerPlayers.add_orders as it runs (same players, order and draws), timing each brain.
func _ai_step(state: GameState, content: ContentRegistry) -> Array[OrderSet]:
	var out: Array[OrderSet] = []
	var rng := state.rng.get_stream(RngStreams.CLASSIC)
	var shared := {}
	for p in state.players:
		if not ComputerPlayers.plays(p):
			continue
		var personality := ComputerPlayers.personality_for(p, content)
		var brain := AiBrains.create(personality["brain"])
		var ctx := AiContext.new(
			PlayerView.new(state, content, p.index), content, rng, personality, p.ai_level
		)
		ctx.shared = shared
		var t := Time.get_ticks_usec()
		brain.play(ctx)
		var key: String = personality["brain"]
		_brain_ms[key] = _brain_ms.get(key, 0.0) + (Time.get_ticks_usec() - t) / 1000.0
		out.append(ctx.orders)
		for f in ComputerPlayers.FILES_WRITTEN:
			rng.random(ComputerPlayers.FILE_SALT_RANGE)
	return out


## StandardTurn.generate with the timed pipeline.
func _generate(
	state: GameState, content: ContentRegistry, sets: Array[OrderSet], pipeline: TurnPipeline
) -> void:
	TurnMessages.clear(state)
	state.retired_fleet_numbers.clear()
	state.turn_start_tech.clear()
	for p in state.players:
		state.turn_start_tech[p.index] = p.tech_levels.duplicate()
	state.recycled.clear()
	state.dropped_colonists.clear()
	pipeline.run(TurnContext.new(state, content, sets))


func _top(title: String, totals: Dictionary, turns: int) -> void:
	var rows := []
	for k: String in totals:
		rows.append([totals[k], k])
	rows.sort()
	rows.reverse()
	print("slowest %s (ms a turn):" % title)
	for i in mini(SHOWN, rows.size()):
		print("  %8.1f  %s" % [rows[i][0] / turns, rows[i][1]])
