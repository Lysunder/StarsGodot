"""Adds the planets' population and defense estimates (S15) to existing golden fixtures, read
from the original's host files they were converted from. One-off helper for fixtures made
before the importer read the estimates.

    python tools/harness/add_estimates.py <harness folder> <fixtures folder>
"""

import glob
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import starsfile  # noqa: E402

T_PLANET = 13
# Fixture folders whose harness run has another name; the turn-0 games are game/gNN.hst.
RUNS = {"tiny2": "fix_tiny2", "tiny3ai": "fix_tiny3ai"}
TURN0 = {
    "medium_clump": "g02", "small_maxmin": "g03", "tiny_accel": "g04", "small_sparse": "g05",
    "tiny_random_ai": "g09", "small_it": "g11", "medium_it_two_humans": "g12", "tiny_it": "g13",
    "tiny_random_race": "g14", "small_two_random_races": "g15", "tiny_random_races_only": "g17",
    "small_random_race_accel": "g18", "tiny_random_race_packed": "g19",
}


def estimates(path):
    """Planet id -> (population estimate, defense estimate) for the owned planets in a host file."""
    out = {}
    for b in starsfile.StarsFile.read(path).blocks:
        if b.type != T_PLANET:
            continue
        d = b.data
        word0, flags = struct.unpack_from("<HH", d, 0)
        if word0 >> 11 == 31 or flags & 0x7F <= 2:
            continue
        pos = 5 + sum(1 for k in range(3) if (d[4] >> 2 * k) & 3) + 6
        if flags & 0x400:
            pos += 3
        e = struct.unpack_from("<H", d, pos)[0]
        out[word0 & 0x7FF] = (e & 0xFFF, e >> 12)
    return out


def host_file(harness, game, turn):
    if game in TURN0:
        return os.path.join(harness, "game", TURN0[game] + ".hst")
    found = glob.glob(os.path.join(harness, "runs", RUNS.get(game, game), "t%03d" % turn, "*.hst"))
    return found[0] if len(found) == 1 else None


def main(harness, fixtures):
    for path in sorted(glob.glob(os.path.join(fixtures, "*", "t[0-9][0-9][0-9].json"))):
        game = os.path.basename(os.path.dirname(path))
        turn = int(os.path.basename(path)[1:4])
        hst = host_file(harness, game, turn)
        if hst is None:
            sys.exit("%s: no host file" % path)
        est = estimates(hst)
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for p in data["state"]["planets"]:
            pop, defense = est.get(p["id"], (0, 0)) if p["owner"] >= 0 else (0, 0)
            p["population_estimate"], p["defense_estimate"] = pop, defense
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, indent=1, sort_keys=True)
            f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
