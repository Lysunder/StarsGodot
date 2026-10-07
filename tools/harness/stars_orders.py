"""Converts an original .x order file into our order file format (specs S11, S23).

Usage: python tools/harness/stars_orders.py <name>.x1 out.orders.json

Order blocks converted so far: cargo transfers (1, 2, 25), waypoint delete, add and change (3, 4, 5),
repeat orders (10), ship
moves, split and merge (23, 24, 37), design change (27; design names neutral unless --keep-names),
production queue change (29), research change (34), planet
change (35), fleet battle plan (42), rename fleet (44; the name is left out unless --keep-names,
as the importer leaves fleet names out) and player defaults (46: the default queue for new
colonies and their leftover-to-research setting). Any other order block stops the conversion with its type, so a fixture never silently
loses orders. Registration data (block type 9) is dropped unread by the file reader.
"""

import argparse
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import starsfile  # noqa: E402
import stars_import  # noqa: E402

FORMAT = "starsgodot-orders"
FORMAT_VERSION = 1
CARGO_TRANSFERS = {1: "b", 2: "h", 25: "i"}
HOLDER_KINDS = {1: "planet", 2: "fleet", 4: "deep_space", 8: "object"}
WAYPOINT_DELETE = 3
WAYPOINT_ADD = 4
WAYPOINT_CHANGE = 5
REPEAT_ORDERS = 10
MOVE_SHIPS = 23
SPLIT_FLEET = 24
DESIGN_CHANGE = 27
STARBASE_SLOT_BASE = 16
QUEUE_CHANGE = 29
RESEARCH_CHANGE = 34
PLANET_CHANGE = 35
MERGE_FLEETS = 37
PLAYER_RELATIONS = 38
RELATIONS = ["neutral", "friend", "enemy"]
FLEET_BATTLE_PLAN = 42
RENAME_FLEET = 44
PLAYER_DEFAULTS = 46
FILE_KIND_ORDERS = 1


class StarsOrdersError(Exception):
    pass


def convert(raw, legacy=None, keep_names=False):
    """Our order file (a dict) from the bytes of a .x file."""
    f = starsfile.StarsFile(raw)
    if len(f.turns) != 1:
        raise StarsOrdersError("an order file holds exactly one turn")
    header, blocks = f.turns[0]
    if header.file_kind != FILE_KIND_ORDERS:
        raise StarsOrdersError("not an order file (file kind %d)" % header.file_kind)
    importer = stars_import.Importer.__new__(stars_import.Importer)
    importer.legacy = legacy or stars_import.Legacy()
    importer.keep_names = keep_names
    orders = []
    for b in blocks:
        if b.type == starsfile.TYPE_FOOTER:
            continue
        orders.append(convert_block(importer, b, keep_names))
    return {
        "format": FORMAT,
        "format_version": FORMAT_VERSION,
        "game_version": stars_import.GAME_VERSION,
        "player": header.player,
        "turn": header.turn,
        "orders": orders,
    }


def fleet_ref(word):
    """{"fleet", "owner"} from a fleet id (number, owner x 512)."""
    return {"fleet": word & 0x1FF, "owner": (word >> 9) & 15}


def holder(kind, word):
    """One side of a cargo transfer (S23 blocks 1, 2, 25)."""
    name = HOLDER_KINDS.get(kind)
    if name == "planet":
        return {"planet": word & 0x7FF}
    if name == "fleet":
        return {"fleet": word & 0x1FF, "owner": (word >> 9) & 15}
    raise StarsOrdersError("cargo transfer with a %s is not converted yet" % name)


def convert_block(importer, b, keep_names=False):
    d = b.data
    if b.type in CARGO_TRANSFERS:
        first, second, kinds, mask = struct.unpack_from("<HHBB", d, 0)
        size = struct.calcsize(CARGO_TRANSFERS[b.type])
        values = iter(struct.unpack_from("<%d%s" % (bin(mask).count("1"), CARGO_TRANSFERS[b.type]), d, 6))
        amounts = [next(values) if mask >> c & 1 else 0 for c in range(5)]
        assert len(d) == 6 + size * bin(mask).count("1")
        out = holder(kinds & 15, first)
        if "fleet" not in out:
            raise StarsOrdersError("cargo transfer from a planet is not converted yet")
        out.update(type="cargo_transfer", other=holder(kinds >> 4, second), amounts=amounts)
        return out
    if b.type in (REPEAT_ORDERS, SPLIT_FLEET, MERGE_FLEETS, FLEET_BATTLE_PLAN, RENAME_FLEET, MOVE_SHIPS):
        out = fleet_ref(struct.unpack_from("<H", d, 0)[0])
        if b.type == REPEAT_ORDERS:
            out.update(type="fleet_repeat", repeat=bool(struct.unpack_from("<H", d, 2)[0] & 1))
        elif b.type == SPLIT_FLEET:
            out.update(type="fleet_split")
        elif b.type == MERGE_FLEETS:
            others = [w & 0x1FF for (w,) in struct.iter_unpack("<H", d[2:])]
            out.update(type="fleet_merge", fleets=others)
        elif b.type == FLEET_BATTLE_PLAN:
            out.update(type="fleet_battle_plan", plan=struct.unpack_from("<H", d, 2)[0])
        elif b.type == RENAME_FLEET:
            name = starsfile.read_string(d, 4)[0] if keep_names else ""
            out.update(type="fleet_rename", name=name)
        else:
            other, mask = struct.unpack_from("<HxH", d, 2)
            counts = iter(struct.unpack_from("<%dh" % bin(mask).count("1"), d, 7))
            ships = [{"design": i, "count": next(counts)} for i in range(16) if mask >> i & 1]
            out.update(type="fleet_move_ships", other=other & 0x1FF, ships=ships)
        return out
    if b.type in (WAYPOINT_DELETE, WAYPOINT_ADD, WAYPOINT_CHANGE):
        fleet_id, index = struct.unpack_from("<HH", d, 0)
        out = {"fleet": fleet_id & 0x1FF, "owner": (fleet_id >> 9) & 15}
        if b.type == WAYPOINT_DELETE:
            out.update(type="waypoint_delete", index=index & 0x7FFF, count=2 if index & 0x8000 else 1)
            return out
        out.update(index=index, waypoint=importer.waypoint(d[4:]))
        out["type"] = "waypoint_add" if b.type == WAYPOINT_ADD else "waypoint_change"
        return out
    if b.type == DESIGN_CHANGE:
        word = struct.unpack_from("<H", d, 0)[0]
        operation, slot = word & 15, (word >> 8) & 31
        starbase = slot >= STARBASE_SLOT_BASE
        out = {"starbase": starbase, "slot": slot - STARBASE_SLOT_BASE if starbase else slot}
        if operation == 0:
            out["type"] = "design_delete"
            return out
        design = importer.design(starsfile.Block(stars_import.T_DESIGN, d[2:]), starbase)
        out.update(type="design_change", design=design)
        return out
    if b.type == PLAYER_DEFAULTS:
        queue = importer.default_queue(-1, d[1], d[2:]) if len(d) > 1 else []
        return {"type": "player_defaults", "leftover_to_research": bool(d[0] & 1), "queue": queue}
    if b.type == QUEUE_CHANGE:
        planet = struct.unpack_from("<H", d, 0)[0] & 0x7FF
        items = [importer.queue_item(planet, w) for w in struct.iter_unpack("<HH", d[2:])]
        return {"type": "production_queue", "planet": planet, "items": items}
    if b.type == RESEARCH_CHANGE:
        return {"type": "research", "percent": d[0], "field": d[1] & 15, "next": d[1] >> 4}
    if b.type == PLANET_CHANGE:
        planet = struct.unpack_from("<H", d, 0)[0]
        v = struct.unpack_from("<I", d, 2)[0]
        return {
            "type": "planet_settings",
            "planet": planet,
            "leftover_to_research": bool(v & 1),
            "mass_driver_target": ((v >> 1) & 0x3FF) - 1,
            "mass_driver_warp": ((v >> 11) & 15) + 4,
            "route": ((v >> 15) & 0x3FF) - 1,
        }
    if b.type == PLAYER_RELATIONS:
        # one byte per player: 0 neutral, 1 friend, 2 enemy (the player's own entry included)
        return {"type": "player_relations", "relations": [RELATIONS[v] for v in d]}
    raise StarsOrdersError("order block type %d is not converted yet" % b.type)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("x")
    ap.add_argument("out")
    ap.add_argument("--keep-names", action="store_true", help="keep fleet names (never for committed fixtures)")
    args = ap.parse_args(argv)
    with open(args.x, "rb") as f:
        result = convert(f.read(), keep_names=args.keep_names)
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(result, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
