extends SceneTree
## The mod validator (plan M14; MODDING.md §13): checks a mod folder and says what it changes
## (ModValidator).
##
##   godot --headless --path <project> --script res://tools/validate_mod.gd -- <mod folder>
##     [--with <folder of a mod it needs>]...
##
## Validating a script mod runs its entry script: checking it is trusting it. Exits 1 when
## anything is wrong.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: validate_mod.gd -- <mod folder> [--with <mod folder>]...")
		quit(2)
		return
	var with: Array[String] = []
	for i in range(1, args.size() - 1):
		if args[i] == "--with":
			with.append(args[i + 1])
	var r := ModValidator.validate(args[0], with)
	for i in r.lines.size():
		print(("  " if i > 0 else "") + r.lines[i])
	for p in r.problems:
		printerr(p)
	print("OK: no problems found." if r.ok() else "%d problem(s) found." % r.problems.size())
	quit(0 if r.ok() else 1)
