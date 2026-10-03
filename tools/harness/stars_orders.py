"""Converts an original .x order file into our order file format (specs S11, S23).

Usage: python tools/harness/stars_orders.py <name>.x1 out.orders.json

Order blocks converted so far: production queue change (29), research change (34) and planet
change (35). Any other order block stops the conversion with its type, so a fixture never silently
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
QUEUE_CHANGE = 29
RESEARCH_CHANGE = 34
PLANET_CHANGE = 35
FILE_KIND_ORDERS = 1


class StarsOrdersError(Exception):
    pass


def convert(raw, legacy=None):
    """Our order file (a dict) from the bytes of a .x file."""
    f = starsfile.StarsFile(raw)
    if len(f.turns) != 1:
        raise StarsOrdersError("an order file holds exactly one turn")
    header, blocks = f.turns[0]
    if header.file_kind != FILE_KIND_ORDERS:
        raise StarsOrdersError("not an order file (file kind %d)" % header.file_kind)
    importer = stars_import.Importer.__new__(stars_import.Importer)
    importer.legacy = legacy or stars_import.Legacy()
    orders = []
    for b in blocks:
        if b.type == starsfile.TYPE_FOOTER:
            continue
        orders.append(convert_block(importer, b))
    return {
        "format": FORMAT,
        "format_version": FORMAT_VERSION,
        "game_version": stars_import.GAME_VERSION,
        "player": header.player,
        "turn": header.turn,
        "orders": orders,
    }


def convert_block(importer, b):
    d = b.data
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
    raise StarsOrdersError("order block type %d is not converted yet" % b.type)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("x")
    ap.add_argument("out")
    args = ap.parse_args(argv)
    with open(args.x, "rb") as f:
        result = convert(f.read())
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(result, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
