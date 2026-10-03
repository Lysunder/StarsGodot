"""Converts the original game's host state (.xy + .hst) into our save format (specs S03, S23).

Dev harness only (M4). Usage:

    python tools/harness/stars_import.py GAME.xy GAME.hst OUT.json [--rng S1,S2] [--keep-names]

By default every name (races, designs, fleets, battle plans, planets) is replaced by a neutral one,
so converted files contain no text from the original and can be used as test fixtures. --keep-names
keeps the names found in the files (local use only; planet names are never available, S23).

The classic random stream's state at the start of the turn is not in any file (S01). Pass it with
--rng; the default is the start-up state of the harness's fixed-seed copy of the original.
"""

import argparse
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import starsfile  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LEGACY_IDS = os.path.join(ROOT, "content", "core", "legacy_ids.json")
HULLS = os.path.join(ROOT, "content", "core", "content", "hulls.json")

FORMAT = "starsgodot-save"
FORMAT_VERSION = 1
GAME_VERSION = "0.1.0"
# Start-up state of the harness copy whose clock seed is fixed to 0x1234 (S01 clock method).
DEFAULT_RNG = (5, 673)

DENSITIES = ["sparse", "normal", "dense", "packed"]
POSITIONS = ["close", "moderate", "farther", "distant"]
OPTION_BITS = {
    "max_minerals": 0x01,
    "slow_tech": 0x02,
    "accelerated_start": 0x20,
    "no_random_events": 0x80,
    "computer_alliances": 0x10,
    "public_scores": 0x40,
    "galaxy_clumping": 0x100,
}
QUEUE_STANDARD = 2
QUEUE_DESIGN = 4
SHIP_DESIGN_SLOTS = 16
LEFTOVER = ["surface_minerals", "concentrations", "mines", "factories", "defenses"]
# Leftover-point values 5 and 6 (possible in random races) act as surface minerals (S06).
LEFTOVER_FALLBACK = "surface_minerals"
RELATIONS = ["neutral", "friend", "enemy"]
AI_PERSONALITIES = ["robotoids", "turindrones", "automitrons", "rototills", "cybertrons", "macinti"]
AI_INACTIVE = 7
TASKS = [
    "none", "transport", "colonize", "remote_mine", "merge", "scrap", "lay_mines", "patrol",
    "route", "transfer",
]
OBJECT_KINDS = ["minefield", "packet", "wormhole", "trader"]
MINEFIELD_TYPES = ["standard", "heavy", "speed_bump"]

T_PLAYER, T_PLANET, T_FLEET, T_WAYPOINT, T_WAYPOINT_SHORT = 6, 13, 16, 19, 20
T_FLEET_NAME, T_DESIGN, T_QUEUE, T_PLAN, T_OBJECT = 21, 26, 28, 30, 43


class StarsImportError(Exception):
    pass


class Legacy:
    """Original numbers to content ids, from content/core/legacy_ids.json."""

    def __init__(self, path=LEGACY_IDS, hulls=HULLS):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        with open(hulls, encoding="utf-8") as f:
            self.pictures = {h["id"]: h["pictures"] for h in json.load(f)}
        self.parts, self.hulls, self.prts, self.lrts = {}, {}, {}, {}
        self.production_items = {}
        for cid, v in data.items():
            if "production_item" in v:
                self.production_items[v["production_item"]] = cid
            elif "hull" in v:
                self.hulls[v["hull"]] = cid
            elif "prt" in v:
                self.prts[v["prt"]] = cid
            elif "lrt_bit" in v:
                self.lrts[v["lrt_bit"]] = cid
            else:
                self.parts[(v["kind"], v["item"])] = cid

    def part(self, kind, item):
        if (kind, item) not in self.parts:
            raise StarsImportError("unknown part kind %d item %d" % (kind, item))
        return self.parts[(kind, item)]


def design_picture(picture, first):
    """The original's loader keeps a design picture within its hull's four (S04)."""
    return picture if first <= picture < first + 4 else (picture & 3) | first


def signed8(b):
    return b - 256 if b > 127 else b


def mask_bits(mask):
    return [i for i in range(16) if mask >> i & 1]


# --- Settings and planets (.xy) ----------------------------------------------------------------


def read_settings(xy):
    block = next(b for b in xy.blocks if b.type == starsfile.TYPE_SETTINGS)
    d = block.data
    game_id, size, density, players, planets, positions = struct.unpack_from("<IHHHHH", d, 0)
    options = struct.unpack_from("<H", d, 16)[0]
    settings = {
        "universe_width": (size + 1) * 400,
        "density": DENSITIES[density],
        "player_positions": POSITIONS[positions],
        "tutorial": False,
        "victory": {"raw": list(d[20:32])},
        "ruleset_hash": "",
        "mods": [{"id": "core", "version": GAME_VERSION}],
    }
    for name, bit in OPTION_BITS.items():
        settings[name] = bool(options & bit)
    positions_out = []
    x = 1000
    for i in range(planets):
        v = struct.unpack_from("<I", xy.planet_data, 4 * i)[0]
        x += v & 1023
        positions_out.append((x, (v >> 10) & 4095, v >> 22))
    return game_id, players, settings, positions_out


# --- Host file ---------------------------------------------------------------------------------


class Importer:
    def __init__(self, xy, hst, legacy, keep_names=False):
        self.xy, self.hst, self.legacy, self.keep_names = xy, hst, legacy, keep_names

    def run(self, rng):
        game_id, player_count, settings, positions = read_settings(self.xy)
        if self.hst.header.game_id != game_id:
            raise StarsImportError(".xy and .hst belong to different games")
        blocks = list(self.hst.blocks)
        pos = 0

        def take(type_id):
            nonlocal pos
            if pos < len(blocks) and blocks[pos].type == type_id:
                pos += 1
                return blocks[pos - 1]
            return None

        players = []
        while (b := take(T_PLAYER)) is not None:
            players.append(self.player(b.data))
        if len(players) != player_count:
            raise StarsImportError("expected %d player blocks" % player_count)
        for p in players:
            # trailing neutral relations are left out of the file (S23)
            p["relations"] += ["neutral"] * (player_count - len(p["relations"]))
        planets = []
        while (b := take(T_PLANET)) is not None:
            q = take(T_QUEUE)
            planets.append(self.planet(b.data, q.data if q else b"", positions))
        if len(planets) != len(positions):
            raise StarsImportError("expected %d planet blocks" % len(positions))
        for p in players:
            for _ in range(p.pop("_ship_design_count")):
                p["ship_designs"].append(self.design(take(T_DESIGN), False))
        fleets = []
        while (b := take(T_FLEET)) is not None:
            fleet, wp_count = self.fleet(b.data)
            for _ in range(wp_count):
                w = take(T_WAYPOINT) or take(T_WAYPOINT_SHORT)
                if w is None:
                    raise StarsImportError("fleet %d/%d: missing waypoint" % (fleet["owner"], fleet["number"]))
                fleet["waypoints"].append(self.waypoint(w.data))
            name = take(T_FLEET_NAME)
            if name is not None and self.keep_names:
                fleet["name"] = starsfile.read_string(name.data, 0)[0]
            fleets.append(fleet)
        for p in players:
            for _ in range(p.pop("_starbase_design_count")):
                p["starbase_designs"].append(self.design(take(T_DESIGN), True))
        objects = {"minefields": [], "packets": [], "wormholes": [], "traders": []}
        count = take(T_OBJECT)
        if count is not None:
            for _ in range(struct.unpack_from("<H", count.data, 0)[0]):
                self.space_object(take(T_OBJECT).data, objects)
        while (b := take(T_PLAN)) is not None:
            self.battle_plan(b.data, players)
        if pos != len(blocks) - 1 or blocks[pos].type != starsfile.TYPE_FOOTER:
            raise StarsImportError("unexpected block %r at position %d" % (blocks[pos], pos))
        for key in ("ship_designs", "starbase_designs"):
            for p in players:
                p[key].sort(key=lambda d: d["slot"])
        state = {
            "turn": self.hst.header.turn,
            "settings": settings,
            "players": players,
            "planets": planets,
            "fleets": fleets,
            "rng": {
                "game_seed": 0,
                "streams": {"classic": {"s1": rng[0], "s2": rng[1]}},
            },
            "messages": [],
            "battles": [],
            "history": [],
            "mod_data": {},
        }
        state.update(objects)
        return {
            "format": FORMAT,
            "format_version": FORMAT_VERSION,
            "game_version": GAME_VERSION,
            "ruleset_hash": settings["ruleset_hash"],
            "mods": settings["mods"],
            "state": state,
        }

    # --- players ---

    def player(self, d):
        if d[6] & 7 != 7:
            raise StarsImportError("player %d: the host file should hold the full record" % d[0])
        index = d[0]
        hab = [signed8(b) for b in d[0x10:0x19]]
        center, low, high = hab[0:3], hab[3:6], hab[6:9]
        for axis in range(3):
            if -1 in (center[axis], low[axis], high[axis]):
                center[axis] = low[axis] = high[axis] = -1
        traits = struct.unpack_from("<I", d, 0x4E)[0]
        rel_count = d[0x70]
        relations = [RELATIONS[r] for r in d[0x71 : 0x71 + rel_count]]
        pos = 0x71 + rel_count
        name, pos = starsfile.read_string(d, pos)
        plural, pos = starsfile.read_string(d, pos)
        ai_flags = d[7]
        personality = ai_flags >> 5
        computer = bool(ai_flags & 2) and personality != AI_INACTIVE
        return {
            "index": index,
            "race": {
                "name": name if self.keep_names else "Race %d" % index,
                "plural_name": plural if self.keep_names else "Races %d" % index,
                "primary_trait": self.legacy.prts[d[0x4C]],
                "lesser_traits": sorted(self.legacy.lrts[b] for b in range(14) if traits >> b & 1),
                "hab_low": low,
                "hab_center": center,
                "hab_high": high,
                "growth_rate": d[0x19],
                "resources_per_colonist": d[0x3E],
                "factory_output": d[0x3F],
                "factory_cost": d[0x40],
                "factories_operated": d[0x41],
                "mine_output": d[0x42],
                "mine_cost": d[0x43],
                "mines_operated": d[0x44],
                "research_costs": list(d[0x46:0x4C]),
                "leftover_points": LEFTOVER[d[0x45]] if d[0x45] < len(LEFTOVER) else LEFTOVER_FALLBACK,
                "techs_start_at_3": bool(traits >> 29 & 1),
                "cheap_factories": bool(traits >> 31 & 1),
                "random": bool(traits >> 30 & 1),
                "logo": d[6] >> 3,
                "mod_data": {},
            },
            "ai": AI_PERSONALITIES[personality] if computer else "",
            "ai_level": (ai_flags >> 2) & 7 if computer else 0,
            "active": personality != AI_INACTIVE or not ai_flags & 2,
            "homeworld": struct.unpack_from("<h", d, 8)[0],
            "tech_levels": list(d[0x1A:0x20]),
            "research_points": list(struct.unpack_from("<6I", d, 0x20)),
            "research_percent": d[0x38],
            "research_field": d[0x39] & 15,
            "next_research_field": d[0x39] >> 4,
            "relations": relations,
            "battle_plans": [],
            "ship_designs": [],
            "starbase_designs": [],
            "trader_parts": [],
            "knowledge": {},
            "mod_data": {},
            "_ship_design_count": d[1],
            "_starbase_design_count": d[5] >> 4,
        }

    def battle_plan(self, d, players):
        owner, number = d[0] & 15, d[0] >> 4
        name = starsfile.read_string(d, 4)[0]
        players[owner]["battle_plans"].append(
            {
                "number": number,
                "name": name if self.keep_names else "Plan %d" % number,
                "tactic": d[1] & 15,
                "primary_target": d[2] & 15,
                "secondary_target": d[2] >> 4,
                "attack": d[3],
            }
        )

    def design(self, block, starbase):
        if block is None or block.type != T_DESIGN:
            raise StarsImportError("missing design block")
        d = block.data
        if not d[0] & 4:
            raise StarsImportError("the host file should hold full designs")
        slot = (d[1] >> 2) & 15
        if bool(d[1] & 0x40) != starbase:
            raise StarsImportError("design slot %d: starbase flag does not match its position" % slot)
        hull = self.legacy.hulls[d[2]]
        slot_count = d[6]
        turn_designed = struct.unpack_from("<H", d, 7)[0]
        built, remaining = struct.unpack_from("<II", d, 9)
        parts = []
        pos = 17
        for _ in range(slot_count):
            kind, item, count = struct.unpack_from("<HBB", d, pos)
            pos += 4
            if count == 0:
                parts.append({"part": "", "count": 0})
            else:
                parts.append({"part": self.legacy.part(kind, item), "count": count})
        name = starsfile.read_string(d, pos)[0]
        return {
            "slot": slot,
            "name": name if self.keep_names else "Design %d" % slot,
            "hull": hull,
            "parts": parts,
            "turn_designed": turn_designed,
            "built": built,
            "remaining": remaining,
            "picture": design_picture(d[3], self.legacy.pictures[hull]),
            "mod_data": {},
        }

    # --- planets ---

    def planet(self, d, queue, positions):
        word0, flags = struct.unpack_from("<HH", d, 0)
        pid, owner = word0 & 0x7FF, word0 >> 11
        owner = -1 if owner == 31 else owner
        detail = flags & 0x7F
        x, y, _name_id = positions[pid]
        p = {
            "id": pid,
            "name": "Planet %d" % pid,
            "x": x,
            "y": y,
            "owner": owner,
            "environment": [50, 50, 50],
            "environment_original": [50, 50, 50],
            "concentration": [0, 0, 0],
            "concentration_fraction": [0, 0, 0],
            "surface": [0, 0, 0],
            "population": 0,
            "extra_colonists": 0,
            "mines": 0,
            "factories": 0,
            "defenses": 0,
            "homeworld": bool(flags & 0x80),
            "has_scanner": False,
            "starbase": None,
            "mass_driver_target": -1,
            "mass_driver_warp": 0,
            "route": -1,
            "queue": [],
            "leftover_to_research": False,
            "artifact": True if flags & 0x1000 else None,
            "mod_data": {},
        }
        pos = 4
        if detail > 2:
            fb = d[pos]
            pos += 1
            for k in range(3):
                code = (fb >> 2 * k) & 3
                if code == 1:
                    p["concentration_fraction"][k] = d[pos]
                    pos += 1
                elif code:
                    raise StarsImportError("planet %d: bad fraction code" % pid)
            p["concentration"] = list(d[pos : pos + 3])
            p["environment"] = list(d[pos + 3 : pos + 6])
            pos += 6
            if flags & 0x400:
                p["environment_original"] = list(d[pos : pos + 3])
                pos += 3
            else:
                p["environment_original"] = list(p["environment"])
            if owner >= 0:
                pos += 2  # estimates for other players' views
        if flags & 0x2000:
            codes = d[pos]
            pos += 1
            values = []
            for k in range(4):
                v, pos = starsfile.read_sized(d, pos, (codes >> 2 * k) & 3)
                values.append(v)
            p["surface"], p["population"] = values[:3], values[3]
        if flags & 0x800:
            inst = d[pos : pos + 8]
            pos += 8
            p["extra_colonists"] = inst[0]
            p["mines"] = inst[1] | (inst[2] & 15) << 8
            p["factories"] = inst[2] >> 4 | inst[3] << 4
            p["defenses"] = inst[4] | (inst[5] & 15) << 8
            p["leftover_to_research"] = bool(inst[6] & 0x80)
            p["has_scanner"] = not inst[6] & 1
        if flags & 0x200:
            w0, w1 = struct.unpack_from("<HH", d, pos)
            pos += 4
            p["starbase"] = {"design": w0 & 15, "damage": w0 >> 4}
            p["mass_driver_target"] = (w1 & 0x3FF) - 1
            p["mass_driver_warp"] = ((w1 >> 10) & 15) + 4
        if flags & 0x4000:
            p["route"] = (struct.unpack_from("<H", d, pos)[0] & 0x3FF) - 1
            pos += 2
        if pos != len(d):
            raise StarsImportError("planet %d: %d bytes left over" % (pid, len(d) - pos))
        p["queue"] = [self.queue_item(pid, q) for q in struct.iter_unpack("<HH", queue)]
        return p

    def queue_item(self, pid, words):
        """One production queue item (S09): standard item or design, count, progress."""
        w0, w1 = words
        number, kind = w0 >> 10, w1 & 15
        item = {"item": "", "design": -1, "starbase": False, "count": w0 & 0x3FF, "progress": w1 >> 4}
        if kind == QUEUE_STANDARD:
            if number not in self.legacy.production_items:
                raise StarsImportError("planet %d: unknown production item %d" % (pid, number))
            item["item"] = self.legacy.production_items[number]
        elif kind == QUEUE_DESIGN:
            item["starbase"] = number >= SHIP_DESIGN_SLOTS
            item["design"] = number - SHIP_DESIGN_SLOTS if item["starbase"] else number
        else:
            raise StarsImportError("planet %d: unknown queue item kind %d" % (pid, kind))
        return item

    # --- fleets ---

    def fleet(self, d):
        number, owner = d[0] | (d[1] & 1) << 8, (d[1] >> 1) & 15
        kind, flags = d[4], d[5]
        if kind != 7:
            raise StarsImportError("fleet %d/%d: the host file should hold full fleets" % (owner, number))
        planet, x, y, design_mask = struct.unpack_from("<hHHH", d, 6)
        pos = 14
        stacks = []
        for slot in mask_bits(design_mask):
            if flags & 8:
                count = d[pos]
                pos += 1
            else:
                count = struct.unpack_from("<H", d, pos)[0]
                pos += 2
            stacks.append({"design": slot, "count": count, "damaged_percent": 0, "damage": 0,
                           "paid": [0, 0, 0, 0]})
        codes = struct.unpack_from("<H", d, pos)[0]
        pos += 2
        cargo = []
        for k in range(5):
            v, pos = starsfile.read_sized(d, pos, (codes >> 2 * k) & 3)
            cargo.append(v)
        damage_mask = struct.unpack_from("<H", d, pos)[0]
        pos += 2
        by_slot = {s["design"]: s for s in stacks}
        for slot in mask_bits(damage_mask):
            w = struct.unpack_from("<H", d, pos)[0]
            pos += 2
            if slot in by_slot:
                by_slot[slot]["damaged_percent"] = w & 0x7F
                by_slot[slot]["damage"] = min(w >> 7, 499)
        battle_plan, wp_count = d[pos], d[pos + 1]
        pos += 2
        if pos != len(d):
            raise StarsImportError("fleet %d/%d: %d bytes left over" % (owner, number, len(d) - pos))
        fleet = {
            "owner": owner,
            "number": number,
            "name": "",
            "x": x,
            "y": y,
            "planet": planet,
            "stacks": [s for s in stacks if s["count"] > 0],
            "cargo": cargo,
            "battle_plan": battle_plan,
            "waypoints": [],
            "repeat": False,
            "mod_data": {},
        }
        return fleet, wp_count

    def waypoint(self, d):
        x, y, target_id = struct.unpack_from("<HHH", d, 0)
        target_kind = d[7] & 15
        wp = {
            "x": x,
            "y": y,
            "target": "none",
            "target_owner": -1,
            "target_id": -1,
            "warp": d[6] >> 4,
            "task": TASKS[d[6] & 15],
            "task_data": {},
        }
        if target_kind == 1:
            wp["target"], wp["target_id"] = "planet", target_id
        elif target_kind == 2:
            wp["target"] = "fleet"
            wp["target_owner"], wp["target_id"] = (target_id >> 9) & 15, target_id & 0x1FF
        elif target_kind == 8:
            kind = OBJECT_KINDS[target_id >> 13]
            wp["target"], wp["target_id"] = kind, target_id & 0x1FF
            wp["target_owner"] = (target_id >> 9) & 15 if kind in ("minefield", "packet") else -1
        if len(d) > 8:
            wp["task_data"] = {"raw": list(struct.unpack_from("<5H", d, 8))}
        return wp

    # --- space objects ---

    def space_object(self, d, out):
        oid, x, y = struct.unpack_from("<HHH", d, 0)
        number, owner, kind = oid & 0x1FF, (oid >> 9) & 15, oid >> 13
        if kind == 0:
            mines = struct.unpack_from("<I", d, 6)[0]
            out["minefields"].append(
                {
                    "owner": owner, "number": number, "x": x, "y": y, "mines": mines,
                    "type": MINEFIELD_TYPES[d[12]], "detonate": d[13] == 1,
                    "seen_by": mask_bits(struct.unpack_from("<H", d, 14)[0]), "mod_data": {},
                }
            )
        elif kind == 1:
            w6 = struct.unpack_from("<H", d, 6)[0]
            dest, warp = w6 & 0x3FF, (w6 >> 10) & 15
            salvage = dest == 0x3FF
            out["packets"].append(
                {
                    "owner": owner, "number": number, "x": x, "y": y,
                    "minerals": list(struct.unpack_from("<3H", d, 8)), "salvage": salvage,
                    "destination": -1 if salvage else dest, "warp": 0 if salvage else warp,
                    "mod_data": {},
                }
            )
        elif kind == 2:
            out["wormholes"].append(
                {
                    "number": number, "x": x, "y": y,
                    "other_end": struct.unpack_from("<H", d, 12)[0] & 0x1FF,
                    "stability": struct.unpack_from("<H", d, 6)[0] & 3,
                    "age": (struct.unpack_from("<H", d, 6)[0] >> 2) & 0x3FF,
                    "seen_by": mask_bits(struct.unpack_from("<H", d, 10)[0]), "mod_data": {},
                }
            )
        else:
            dx, dy = struct.unpack_from("<HH", d, 6)
            out["traders"].append(
                {
                    "number": number, "x": x, "y": y, "destination_x": dx, "destination_y": dy,
                    "warp": d[10] & 15, "item": "",
                    "met": mask_bits(struct.unpack_from("<H", d, 12)[0]), "mod_data": {},
                }
            )


def import_game(xy_path, hst_path, rng=DEFAULT_RNG, keep_names=False):
    xy = starsfile.StarsFile.read(xy_path)
    hst = starsfile.StarsFile.read(hst_path)
    return Importer(xy, hst, Legacy(), keep_names).run(rng)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("xy")
    ap.add_argument("hst")
    ap.add_argument("out")
    ap.add_argument("--rng", help="classic stream state at the start of the turn: S1,S2")
    ap.add_argument("--keep-names", action="store_true")
    args = ap.parse_args(argv)
    rng = tuple(int(v) for v in args.rng.split(",")) if args.rng else DEFAULT_RNG
    save = import_game(args.xy, args.hst, rng, args.keep_names)
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(save, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
