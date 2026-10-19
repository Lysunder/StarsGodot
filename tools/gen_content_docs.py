"""Regenerates the reference tables in modding/content.md and modding/traits.md.

The tables come from the code and the base game's own content, so they stay in step with them:

- content types and fields: core/content/content_schemas.gd (TYPES, with its `#` field comments);
- part and hull stats and tags: every stat and tag the core content uses, and the core/ files that
  read each one;
- rule constants: content/core/content/constants.json with their English names;
- traits and trait parameters: content/core/content/traits.json, and the core/ files that read
  each parameter.

Only the text between the `<!-- BEGIN GENERATED: name -->` and `<!-- END GENERATED: name -->`
markers is replaced; the prose around the markers is written by hand. Run from the repository
root:

    python tools/gen_content_docs.py
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMAS = os.path.join(ROOT, "core", "content", "content_schemas.gd")
CORE_CONTENT = os.path.join(ROOT, "content", "core", "content")
CORE_LANG = os.path.join(ROOT, "content", "core", "lang", "en.json")

# What each part or hull stat means, in our words (S04, and the rule specs that read them).
STAT_DOCS = {
    "accuracy": "Torpedo base accuracy, percent.",
    "armor": "Armor points added to the ship.",
    "battle_move": "Whole steps added to the ship's battle movement.",
    "battle_move_halves": "Half steps of battle movement; n such parts add (n + 1) / 2.",
    "beam_damage_pct": "Capacitors: percent added to beam damage.",
    "beam_deflection": "Percent taken off incoming beam damage.",
    "cargo_capacity": "Cargo capacity added, kT.",
    "cloak": "Cloak units (S15 turns them into a percentage using ship mass).",
    "defense": "Planetary defense coverage value.",
    "driver_warp": "Mass driver: the warp it throws packets at.",
    "fuel_capacity": "Fuel capacity added, mg.",
    "fuel_generation": "Fuel made each year, mg.",
    "gate_mass": "Stargate: the heaviest ship it can send, kT (-1: any).",
    "gate_range": "Stargate: how far it can send, ly (-1: any distance).",
    "initiative": "Battle initiative added.",
    "installations": "Bombs: installations destroyed per bomb.",
    "jamming": "Percent removed from enemy torpedo accuracy, applied once per part.",
    "kill_rate": "Bombs: population killed, tenths of a percent per bomb.",
    "min_kill": "Bombs: minimum colonists killed per bomb.",
    "mine_laying_pct": "Hull: not read by any rule yet; the doubling comes from the hull tag "
    "`mine_layer`.",
    "mines_heavy": "Heavy mines laid per year.",
    "mines_speed_bump": "Speed bump mines laid per year.",
    "mines_standard": "Standard mines laid per year.",
    "mining_rate": "Remote mining rate.",
    "pen_range": "Penetrating scanner range, ly.",
    "power": "Weapon damage.",
    "range": "Weapon range, battle squares.",
    "remote_terraform": "Remote terraforming per year.",
    "repair_bonus": "Hull: repair bonus to the fleet it travels with.",
    "scan_range": "Normal scanner range, ly.",
    "shield": "Shield points added to the ship.",
    "terraform": "Terraforming reach, in environment units (S10).",
    "torpedo_accuracy": "Battle computers: percent added to torpedo accuracy.",
}

TAG_DOCS = {
    "antimatter_generator": "Marks the fuel-making electrical part.",
    "builtin_scanner": "Hull has a small built-in scanner.",
    "capacitor": "Beam capacitor (stacks with other capacitors).",
    "capital_missile": "Capital missile (S16).",
    "colonizer": "Colonization module: the ship can colonize.",
    "energy_dampener": "Slows every ship in the battle.",
    "full_default_warp": "Engine whose default warp is not eased down to a nearby free speed (S15).",
    "fuel_transport": "Hull counts as a fuel transport.",
    "gatling": "Beam that hits every target in its square.",
    "genesis_device": "Genesis Device (S09).",
    "jump_gate": "Ship part that works like a stargate.",
    "lbu": "Bomb that only destroys installations.",
    "mass_driver": "Orbital part that throws mineral packets.",
    "mine_layer": "Hull doubles the mines its mine layers lay.",
    "normal": "Normal (population-killing) bomb.",
    "orbital_adjuster": "Mining robot that terraforms remotely.",
    "orbital_construction": "Orbital construction module.",
    "penetrating": "Planetary scanner with a penetrating range.",
    "radiating": "Engine that kills some colonists in the cargo hold each year.",
    "retro": "Retro bomb: undoes terraforming.",
    "sapper": "Beam that only damages shields.",
    "smart": "Smart bomb: its own kill rate and defense coverage (S17).",
    "stargate": "Orbital stargate.",
    "steals_from_fleets": "Scanner that sees (and lets the owner steal) fleet cargo.",
    "steals_from_planets": "Scanner that can also steal from planets.",
    "tachyon_detector": "Lowers enemy cloaking.",
    "terraform_basic": "Basic terraforming item.",
    "terraform_gravity": "Terraforms gravity.",
    "terraform_radiation": "Terraforms radiation.",
    "terraform_temperature": "Terraforms temperature.",
    "terraform_total": "Terraforms every axis.",
    "warp10_safe": "Engine takes no damage at warp 10.",
}


# Type descriptions for types whose schema has no comment.
TYPE_DOCS = {
    "battle_plan_default": "a battle plan every player starts with (S16)",
    "constant": "a named integer the rules read (see Rule constants below)",
    "hull": "a ship or starbase hull (S04)",
    "message": "a turn message type (S21); its wording is the string `<id>.text`",
    "name_list": "a list of names: planet names and race names (S07)",
    "part": "a ship or starbase part, or a planetary item (S04)",
    "part_upgrade": "starting designs swap a part in `from` for the first candidate the player "
    "can use (S07)",
    "production_item": "a standard production queue item that is not a ship or starbase (S09)",
    "race_preset": "a ready-made race offered in the race wizard (S06); fields left out keep the "
    "default race's values",
    "starting_design": "a design template for starting fleets and starbases (S07)",
    "starting_setup": "what a trait changes about a player's start (S07); the game uses the "
    "primary trait's setup for `tech`, the homeworld and starbases, and adds the "
    "lesser traits' `tech_bonus` and `fleets`",
    "tech_field": "a research field (S05)",
    "trait": "a primary or lesser racial trait (S06); see traits.md",
}

# Field notes for fields whose schema has no comment, keyed "<type>.<path>".
FIELD_DOCS = {
    "hull.starbase": "true for starbase hulls",
    "hull.tech": "minimum tech level per field to build it",
    "hull.mass": "mass in kT",
    "hull.armor": "armor points",
    "hull.fuel": "fuel capacity, mg",
    "hull.cargo": "cargo capacity, kT",
    "hull.initiative": "battle initiative",
    "hull.pictures": "the first of the hull's design pictures",
    "hull.rank": "starbases: replacing a starbase by one of lower rank clears ship items from "
    "the queue (S09)",
    "hull.dock": "starbases: largest ship mass the dock can build (-1 any, 0 no dock)",
    "hull.stats": "see Stats and tags below",
    "hull.slots[].accepts": "part categories the slot takes",
    "hull.slots[].max": "how many parts fit",
    "hull.slots[].required": "accepted, but no rule reads it yet",
    "hull.required_traits": "the race needs at least one of these",
    "hull.forbidden_traits": "the race may have none of these",
    "part.category": "the kind of part, and which hull slots take it",
    "part.tech": "minimum tech level per field to build it",
    "part.mass": "mass in kT",
    "part.stats": "see Stats and tags below",
    "part.fuel_table": "engines: fuel use at warp 0 to 10",
    "part.miniaturize": "false: its price never drops with tech (S09)",
    "part.required_traits": "the race needs at least one of these",
    "part.forbidden_traits": "the race may have none of these",
    "trait.kind": "primary or lesser",
    "trait.order": "position among the traits of its kind (race wizard, random races)",
    "trait.cost": "advantage points used; negative gives points back",
    "trait.params": "trait parameters (traits.md)",
    "trait.excludes": "traits not to combine with this one (no rule checks it yet)",
    "tech_field.order": "position of the field (0 to 5 in the base game)",
    "constant.value": "the value",
    "name_list.names": "the names, in order",
    "message.params": "the kind of each parameter, in order (see Message parameter kinds)",
    "production_item.order": "the item's number in the original's list",
    "production_item.effect": "what building it does",
    "production_item.auto": "a standing (auto) item (S09)",
    "production_item.builds": "auto items: the plain item a partly built unit becomes",
    "production_item.minimum": "auto terraforming: only while still needed",
    "production_item.best": "scanner: the best one the owner can build",
    "production_item.part": "the part whose price it costs, or that it installs",
    "production_item.mineral": "packets: which mineral",
    "race_preset.order": "position in the wizard's list",
    "race_preset.primary_trait": "the race's primary trait",
    "race_preset.lesser_traits": "the race's lesser traits",
    "race_preset.hab_low": "lowest habitable value per axis (gravity, temperature, "
    "radiation); -1 immune",
    "race_preset.hab_center": "centre of the habitable range per axis; -1 immune",
    "race_preset.hab_high": "highest habitable value per axis; -1 immune",
    "race_preset.growth_rate": "maximum growth rate, percent",
    "race_preset.research_costs": "per field: 0 expensive, 1 normal, 2 cheap",
    "race_preset.leftover_points": "what unspent advantage points buy",
    "starting_design.hull": "the design's hull",
    "starting_design.slots": "one entry per hull slot, in order; {} leaves a slot empty",
    "starting_design.slots[].part": "the part",
    "starting_design.slots[].count": "how many",
    "starting_design.picture": "the design's picture",
    "starting_setup.trait": "the trait this setup belongs to",
    "starting_setup.tech": "primary trait: starting tech level per field",
    "starting_setup.tech_bonus": "lesser trait: tech levels added",
    "starting_setup.tech_bonus_outside_tutorial": "lesser trait: tech levels added except in "
    "the tutorial",
    "starting_setup.starbases": "starbase designs the player starts with",
    "starting_setup.starbases[].slot": "the starbase design slot",
    "starting_setup.starbases[].design": "the design template",
    "starting_setup.starbases[].built": "false: the design exists but none is built",
    "starting_setup.homeworld_starbase": "the starbase design slot on the homeworld",
    "starting_setup.homeworld_mass_driver_warp": "the homeworld mass driver's starting warp",
    "starting_setup.homeworld_installations": "false: the homeworld starts with no mines, "
    "factories or defenses",
    "starting_setup.homeworld_scanner": "false: the homeworld starts without a scanner",
    "starting_setup.fleets": "starting fleets, each added when its conditions hold",
    "starting_setup.fleets[].design": "the design template",
    "starting_setup.fleets[].count": "how many fleets of it (default 1)",
    "starting_setup.fleets[].extra_planet": "instead of a fleet: an extra colonized planet",
    "starting_setup.fleets[].min_tech": "only with at least these tech levels",
    "starting_setup.fleets[].below_tech": "only with tech levels below these",
    "starting_setup.fleets[].human_only": "only for human players",
    "starting_setup.fleets[].forbidden_traits": "not for races with any of these traits",
    "starting_setup.fleets[].min_universe_size": "only from this universe size up",
    "starting_setup.fleets[].outside_tutorial": "not in the tutorial",
    "starting_setup.fleets[].tutorial_only": "only in the tutorial",
    "part_upgrade.from": "the parts to replace",
    "part_upgrade.candidates": "replacements, best first; the first the player can use wins",
    "part_upgrade.candidates[].part": "the replacement part",
}


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def load_json(path):
    return json.loads(read(path))


# --- Reading the schemas ------------------------------------------------------------------------


def simple_consts(path, ns):
    """Single-line `const NAME := value` of a .gd file, evaluated in order (unknown ones skipped)."""
    out = {}
    for line in read(path).split("\n"):
        m = re.match(r"^const ([A-Z_][A-Z0-9_]*)\s*(?::\s*[^=]+)?:?=\s*(.+)$", line)
        if not m:
            continue
        try:
            out[m.group(1)] = eval(m.group(2), {}, {**ns, **out})
        except Exception:
            pass
    return out


class Namespace:
    def __init__(self, values):
        self.__dict__.update(values)


def load_schemas():
    """Evaluates the const block of content_schemas.gd as Python, keeping its `#` comments."""
    text = read(SCHEMAS).split("\nclass Report:")[0]
    lines = text.split("\n")
    out = []
    comment = []
    value_docs = {}
    for line in lines:
        s = line.strip()
        if s.startswith("class_name") or s.startswith("extends"):
            continue
        if s.startswith("##"):
            comment = []
            continue
        if s.startswith("#"):
            comment.append(s.lstrip("#").strip())
            continue
        if comment:
            km = re.match(r'^(\s*)"(\w+)":', line)
            vm = re.match(r'^\s*"(\w+)",\s*$', line)
            if km:
                doc = " ".join(comment)
                out.append('%s"__doc__%s": %s,' % (km.group(1), km.group(2), json.dumps(doc)))
            elif vm:
                value_docs[vm.group(1)] = " ".join(comment)
            comment = []
        line = re.sub(r"^const ([A-Z_][A-Z0-9_]*)\s*(?::\s*[^=]+)?:?=", r"\1 =", line)
        line = re.sub(r"\btrue\b", "True", line)
        line = re.sub(r"\bfalse\b", "False", line)
        out.append(line)
    race = Namespace(simple_consts(os.path.join(ROOT, "core", "model", "race.gd"), {}))
    brains = Namespace(simple_consts(os.path.join(ROOT, "core", "ai", "ai_brains.gd"), {}))
    ns = {"Race": race, "AiBrains": brains}
    exec("\n".join(out), ns)
    return ns, value_docs


# --- Rendering a schema -------------------------------------------------------------------------


def code(text):
    return "`%s`" % text


def count_text(spec):
    lo = spec.get("min")
    hi = spec.get("max")
    if lo is not None and hi is not None:
        return "exactly %d" % lo if lo == hi else "%d to %d" % (lo, hi)
    if lo:
        return "at least %d" % lo
    if hi is not None:
        return "at most %d" % hi
    return ""


def describe(spec):
    t = spec["t"]
    if t == "int":
        lo = spec.get("min")
        hi = spec.get("max")
        if lo is not None and hi is not None:
            return "integer %d to %d" % (lo, hi)
        if lo is not None:
            return "integer >= %d" % lo
        if hi is not None:
            return "integer <= %d" % hi
        return "integer"
    if t == "string":
        return "text"
    if t == "bool":
        return "true / false"
    if t == "enum":
        return "one of " + ", ".join(code(v) for v in spec["values"])
    if t == "id":
        return "id"
    if t == "key":
        return "lowercase dotted key"
    if t == "ref":
        return "id of a %s" % code(spec["to"])
    if t == "list":
        of = spec["of"]
        n = count_text(spec)
        inner = "objects (see below)" if of["t"] == "object" else describe(of)
        return "list%s of %s" % (" (%s)" % n if n else "", inner)
    if t == "object":
        return "object (see below)"
    if t == "map":
        return "map: %s -> %s" % (describe(spec["key"]), describe(spec["value"]))
    return t


def sentence(text):
    text = text.strip()
    if not text:
        return ""
    text = text[0].upper() + text[1:]
    return text if text.endswith(".") else text + "."


def field_rows(type_name, fields, required, prefix):
    rows = []
    for name, spec in fields.items():
        if name.startswith("__doc__"):
            continue
        path = prefix + name
        doc = fields.get("__doc__" + name, "") or FIELD_DOCS.get("%s.%s" % (type_name, path), "")
        rows.append((path, describe(spec), "yes" if name in required else "", sentence(doc)))
        sub = spec
        suffix = ""
        while sub["t"] == "list":
            sub = sub["of"]
            suffix += "[]"
        if sub["t"] == "object":
            rows.extend(
                field_rows(type_name, sub["fields"], sub.get("required", []), path + suffix + ".")
            )
    return rows


def cell(text):
    return text.replace("|", "\\|")


def example_for(type_name, defs):
    of_type = [d for d in defs if d.get("type") == type_name]
    if not of_type:
        return ""
    best = of_type[0]
    dump = json.dumps(best, indent=2)
    if dump.count("\n") > 30:
        best = min(of_type, key=lambda d: len(json.dumps(d)))
        dump = json.dumps(best, indent=2)
    if dump.count("\n") > 30:
        return ""
    return dump


def render_types(ns, defs, value_docs):
    types = ns["TYPES"]
    common = ns["_COMMON"]
    out = []
    out.append("Every definition also has the common fields:\n")
    out.append("| Field | Kind | Required |")
    out.append("|---|---|---|")
    for name, spec in common.items():
        req = "yes" if name in ("type", "id") else ""
        out.append("| `%s` | %s | %s |" % (name, cell(describe(spec)), req))
    out.append("")
    type_names = sorted(k for k in types if not k.startswith("__doc__"))
    out.append("Type index: " + ", ".join("[`%s`](#%s)" % (t, t) for t in type_names) + ".\n")
    for name in sorted(k for k in types if not k.startswith("__doc__")):
        spec = types[name]
        out.append("### %s\n" % name)
        doc = types.get("__doc__" + name) or TYPE_DOCS.get(name, "")
        if doc:
            out.append(sentence(doc) + "\n")
        fields = dict(spec["fields"])
        fields.update(spec.get("more_fields", {}))
        rows = field_rows(name, fields, spec["required"], "")
        if rows:
            out.append("| Field | Kind | Required | Notes |")
            out.append("|---|---|---|---|")
            for path, kind, req, note in rows:
                out.append("| `%s` | %s | %s | %s |" % (path, cell(kind), req, cell(note)))
            out.append("")
        n = sum(1 for d in defs if d.get("type") == name)
        line = "The base game defines %d." % n if n else "The base game defines none."
        ex = example_for(name, defs)
        if ex:
            out.append(line + " Example from `content/core`:\n")
            out.append("```json\n%s\n```" % ex)
        else:
            out.append(line)
        out.append("")
    out.append("### Message parameter kinds\n")
    out.append("The values of a `message` definition's `params` list:\n")
    out.append("| Kind | Notes |")
    out.append("|---|---|")
    for v in ns["MESSAGE_PARAMS"]:
        out.append("| `%s` | %s |" % (v, cell(value_docs.get(v, ""))))
    return "\n".join(out)


# --- Stats, tags, constants, traits ---------------------------------------------------------------


def core_sources():
    files = sorted(glob.glob(os.path.join(ROOT, "core", "**", "*.gd"), recursive=True))
    out = [(os.path.relpath(f, ROOT).replace("\\", "/"), read(f)) for f in files]
    # the schemas name fields, not stats or tags
    return [(path, text) for path, text in out if not path.endswith("content_schemas.gd")]


def readers(word, sources):
    """core/ files that mention the string literal "word" (where a rule reads it)."""
    needle = '"%s"' % word
    return [path for path, text in sources if needle in text]


def short_paths(paths, limit=4):
    names = [p.split("/")[-1] for p in paths]
    text = ", ".join(code(n) for n in names[:limit])
    if len(names) > limit:
        text += " and %d more" % (len(names) - limit)
    return text


def render_stats(defs, sources):
    part_stats = {}
    part_tags = {}
    hull_stats = {}
    hull_tags = {}
    for d in defs:
        if d.get("type") == "part":
            for k in d.get("stats", {}):
                part_stats.setdefault(k, set()).add(d["category"])
            for k in d.get("tags", []):
                part_tags.setdefault(k, set()).add(d["category"])
        elif d.get("type") == "hull":
            for k in d.get("stats", {}):
                hull_stats.setdefault(k, set()).add(d["id"])
            for k in d.get("tags", []):
                hull_tags.setdefault(k, set()).add(d["id"])
    out = ["#### Part stats\n", "| Stat | Meaning | Core parts with it | Read in |", "|---|---|---|---|"]
    for k in sorted(part_stats):
        out.append("| `%s` | %s | %s | %s |" % (
            k, STAT_DOCS.get(k, ""), ", ".join(sorted(part_stats[k])), short_paths(readers(k, sources))))
    out += ["", "#### Hull stats\n", "| Stat | Meaning | Core hulls with it | Read in |", "|---|---|---|---|"]
    for k in sorted(hull_stats):
        out.append("| `%s` | %s | %s | %s |" % (
            k, STAT_DOCS.get(k, ""), ", ".join(code(h) for h in sorted(hull_stats[k])),
            short_paths(readers(k, sources))))
    out += ["", "#### Part tags\n",
            "Tags starting with `ai_` are hints for the computer players only.\n",
            "| Tag | Meaning | Core categories | Read in |", "|---|---|---|---|"]
    for k in sorted(part_tags):
        doc = TAG_DOCS.get(k, "Computer player hint." if k.startswith("ai_") else "")
        out.append("| `%s` | %s | %s | %s |" % (
            k, doc, ", ".join(sorted(part_tags[k])), short_paths(readers(k, sources))))
    out += ["", "#### Hull tags\n", "| Tag | Meaning | Core hulls | Read in |", "|---|---|---|---|"]
    for k in sorted(hull_tags):
        out.append("| `%s` | %s | %s | %s |" % (
            k, TAG_DOCS.get(k, ""), ", ".join(code(h) for h in sorted(hull_tags[k])),
            short_paths(readers(k, sources))))
    out.append("")
    out.append(
        "\"Read in\" lists the `core/` files that contain the name as a quoted string. It is a text"
    )
    out.append(
        "search, so it can miss names the code builds (`\"mines_\" + type` reads the three `mines_`"
    )
    out.append(
        "stats; `cost.tag.<tag>_adjust_pct` prices parts by tag) and can list files that use the"
    )
    out.append(
        "same word for something else (`normal`). A stat or tag that no rule reads has no effect."
    )
    return "\n".join(out)


def render_constants(defs, names):
    out = ["| Id | Value | Meaning |", "|---|---|---|"]
    for d in defs:
        if d.get("type") == "constant":
            out.append("| `%s` | %d | %s |" % (d["id"], d["value"], cell(names.get(d["id"] + ".name", ""))))
    return "\n".join(out)


def render_traits(defs, names):
    out = ["| Id | Name | Kind | Cost | Parameters |", "|---|---|---|---|---|"]
    for d in defs:
        if d.get("type") != "trait":
            continue
        params = ", ".join("`%s` %d" % (k, v) for k, v in d.get("params", {}).items()) or "none"
        out.append("| `%s` | %s | %s | %d | %s |" % (
            d["id"], cell(names.get(d["id"] + ".name", "")), d["kind"], d["cost"], params))
    return "\n".join(out)


def render_params(defs, sources):
    params = {}
    for d in defs:
        if d.get("type") == "trait":
            for k, v in d.get("params", {}).items():
                params.setdefault(k, []).append("%s %d" % (d["id"].split(".")[-1], v))
    out = ["| Parameter | Set by (core) | Read in |", "|---|---|---|"]
    for k in sorted(params):
        out.append("| `%s` | %s | %s |" % (k, ", ".join(params[k]), short_paths(readers(k, sources))))
    return "\n".join(out)


# --- Writing --------------------------------------------------------------------------------------


def replace_block(path, name, body):
    text = read(path)
    begin = "<!-- BEGIN GENERATED: %s -->" % name
    end = "<!-- END GENERATED: %s -->" % name
    if begin not in text or end not in text:
        sys.exit("%s: markers for %s not found" % (path, name))
    head, rest = text.split(begin, 1)
    _, tail = rest.split(end, 1)
    text = head + begin + "\n" + body.rstrip("\n") + "\n" + end + tail
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    ns, value_docs = load_schemas()
    defs = []
    for path in sorted(glob.glob(os.path.join(CORE_CONTENT, "**", "*.json"), recursive=True)):
        data = load_json(path)
        defs.extend(data if isinstance(data, list) else [data])
    names = load_json(CORE_LANG)
    sources = core_sources()
    content_md = os.path.join(ROOT, "modding", "content.md")
    traits_md = os.path.join(ROOT, "modding", "traits.md")
    replace_block(content_md, "types", render_types(ns, defs, value_docs))
    replace_block(content_md, "stats", render_stats(defs, sources))
    replace_block(content_md, "constants", render_constants(defs, names))
    replace_block(traits_md, "traits", render_traits(defs, names))
    replace_block(traits_md, "params", render_params(defs, sources))
    print("updated modding/content.md and modding/traits.md")


if __name__ == "__main__":
    main()
