extends RefCounted
## Content for compat mode (D12): core plus the test-only harness_compat mod, which puts back the
## original's behaviour for the known bugs fixtures cannot avoid.

const COMPAT_MOD := "harness_compat"


static func load_mods() -> ModLoader.LoadResult:
	var loader := ModLoader.new()
	loader.allow_test_mods = true
	var sources := FolderModSource.discover("res://content")
	sources.append(FolderModSource.new("res://tests/" + COMPAT_MOD))
	return loader.load_mods(sources, PackedStringArray([COMPAT_MOD]))
