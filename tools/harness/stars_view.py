"""Reads what each player sees from the original's player turn files (.m1, .m2 ...), spec S15:
the other players' planets, fleets and designs in the file with their detail level, the other
players the file describes, and the packets, wormholes and traders in it.

Dev harness only. One view per player:

    {
     "planets": {"<planet id>": detail},          other players' and unowned planets
     "fleets": {"<owner>/<number>": detail},      other players' fleets
     "designs": {"<owner>/<slot>": detail},       other players' ship designs
     "starbase_designs": {"<owner>/<slot>": detail},
     "met": [player, ...],                        other players described in the file
     "packets": ["<owner>/<number>", ...],        packets and salvage in the file, the player's own included
     "wormholes": [number, ...],
     "traders": [number, ...],
    }

A planet seen with penetrating scanners whose starbase stayed hidden by its cloak is written as
detail 3 without a starbase; it is read back as detail 2 when the host file shows a starbase there.
"""

import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import starsfile  # noqa: E402

T_PLAYER, T_PLANET, T_PLANET_PARTIAL = 6, 13, 14
T_FLEET, T_FLEET_PARTIAL, T_DESIGN, T_OBJECT = 16, 17, 26, 43
FULL = 7
SCANNED = 3
STARBASE_HIDDEN = 2
PLANET_STARBASE = 0x200
DESIGN_FULL = 4
OBJECT_KINDS = {1: "packets", 2: "wormholes", 3: "traders"}


def read_view(path, player, starbases):
    """The view in one turn file of `player`; `starbases` is the set of planet ids with a starbase
    in the host file of the same turn."""
    view = {
        "planets": {}, "fleets": {}, "designs": {}, "starbase_designs": {}, "met": [],
        "packets": [], "wormholes": [], "traders": [],
    }
    design_counts = []
    designs = []
    objects_left = None
    for b in starsfile.StarsFile.read(path).blocks:
        d = b.data
        if b.type == T_PLAYER:
            if d[0] != player:
                view["met"].append(d[0])
            design_counts.append((d[0], d[1], d[5] >> 4))
        elif b.type == T_PLANET_PARTIAL:
            word0, flags = struct.unpack_from("<HH", d, 0)
            pid = word0 & 0x7FF
            detail = flags & 0x7F
            if detail == SCANNED and not flags & PLANET_STARBASE and pid in starbases:
                detail = STARBASE_HIDDEN
            view["planets"][str(pid)] = detail
        elif b.type in (T_FLEET, T_FLEET_PARTIAL):
            number, owner = d[0] | (d[1] & 1) << 8, (d[1] >> 1) & 15
            if owner != player:
                view["fleets"]["%d/%d" % (owner, number)] = d[4]
        elif b.type == T_DESIGN:
            designs.append(((d[1] >> 2) & 15, FULL if d[0] & DESIGN_FULL else SCANNED))
        elif b.type == T_OBJECT:
            if objects_left is None:
                objects_left = struct.unpack_from("<H", d, 0)[0]
                continue
            objects_left -= 1
            oid = struct.unpack_from("<H", d, 0)[0]
            number, owner, kind = oid & 0x1FF, (oid >> 9) & 15, oid >> 13
            if kind == 1:
                view["packets"].append("%d/%d" % (owner, number))
            elif kind in OBJECT_KINDS:
                view[OBJECT_KINDS[kind]].append(number)
    # Design blocks come in two runs: every described player's ship designs, then (after the
    # fleets) every described player's starbase designs, each in player order.
    owners = []
    for index, ships, _ in design_counts:
        owners += [(index, "designs")] * ships
    for index, _, bases in design_counts:
        owners += [(index, "starbase_designs")] * bases
    if len(owners) != len(designs):
        raise ValueError("%s: %d design blocks for %d designs" % (path, len(designs), len(owners)))
    for (owner, key), (slot, detail) in zip(owners, designs):
        if owner != player:
            view[key]["%d/%d" % (owner, slot)] = detail
    view["met"].sort()
    for key in ("packets", "wormholes", "traders"):
        view[key].sort()
    return view


def player_views(hst_path, state):
    """Each player's view (S15) from the turn files beside the host file; None for a player
    without one. `state` is the converted host state of the same turn."""
    base = os.path.splitext(hst_path)[0]
    starbases = {p["id"] for p in state["planets"] if p.get("starbase") is not None}
    out = []
    for p in range(len(state["players"])):
        path = "%s.m%d" % (base, p + 1)
        out.append(read_view(path, p, starbases) if os.path.exists(path) else None)
    return out
