"""Reads the battle recordings in the original's player turn files (.m1, .m2 ...), spec S16: the
battle's place and players, its tokens (stacks of ships or a starbase) as they started, and every
move and shot in order. Dev harness only; the recordings are the oracle for the battle engine.

One battle:

    {
     "id": n, "sides": n, "players": [player, ...], "planet": id or -1, "x": x, "y": y,
     "tokens": [{...}, ...],          # the 29-byte battle tokens (see TOKEN_FIELDS); a ship
                                      # token names its fleet, a starbase token its planet
     "events": [{"token": i, "square": s, "round": r, "countdown": c, "hits": [...]}, ...],
    }

An event is a token moving (to `square`; 255 when it left the battle) or firing (from `square`); a
shot's hits are [{"target": i, "kind": k, "killed": n, "shield_damage": n, "damage": w}, ...], with
`damage` the target's damage word after the hit (packed like a fleet's: percent damaged in the low 7
bits, armor points above).
"""

import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import starsfile  # noqa: E402

T_BATTLE = 31
# A record over 1 KiB goes on in continuation blocks.
T_BATTLE_MORE = 39
HEADER = 14
TOKEN = 29
EVENT = 6
HIT = 8
STARBASE = 1
# (name, offset, struct format) of the token fields kept.
TOKEN_FIELDS = [
    ("id", 0, "<h"), ("owner", 2, "B"), ("kind", 3, "B"), ("design", 4, "B"), ("square", 5, "B"),
    ("computer_initiative", 6, "B"), ("initiative_low", 7, "B"), ("initiative_high", 8, "B"),
    ("torpedo_jamming", 11, "B"), ("torpedo_accuracy", 12, "B"), ("beam_damage_pct", 13, "B"),
    ("beam_defense_pct", 14, "B"), ("mass", 15, "<H"), ("shields", 17, "<H"), ("count", 19, "<H"),
    ("damage", 21, "<H"), ("targets", 23, "B"), ("tactic", 24, "B"), ("ranges", 25, "B"),
    ("movement", 26, "B"),
    ("state", 27, "<H"),
]


def shield_damage(word):
    """A hit's shield damage: a 13-bit value shifted left by twice the top three bits."""
    return (word & 0x1FFF) << (((word >> 13) & 7) * 2)


def parse_record(data):
    battle_id, sides, tokens, players, size, planet, x, y = struct.unpack_from("<HBBHHhHH", data, 0)
    if size != len(data):
        raise ValueError("battle %d: record of %d bytes, header says %d" % (battle_id, len(data), size))
    out = {
        "id": battle_id, "sides": sides, "players": [p for p in range(16) if players >> p & 1],
        "planet": planet, "x": x, "y": y, "tokens": [], "events": [],
    }
    for t in range(tokens):
        base = HEADER + t * TOKEN
        token = {}
        for name, offset, fmt in TOKEN_FIELDS:
            token[name] = struct.unpack_from(fmt, data, base + offset)[0]
        # the token's id is a fleet (owner × 512 + number) or, for a starbase, its planet
        if token["kind"] == STARBASE:
            token["planet"] = token.pop("id")
        else:
            word = token.pop("id")
            token["fleet"], token["fleet_owner"] = word & 0x1FF, (word >> 9) & 15
        out["tokens"].append(token)
    pos = HEADER + tokens * TOKEN
    while pos < size:
        token, square, count, flags = struct.unpack_from("<BBHH", data, pos)
        event = {
            "token": token, "square": square, "round": flags & 15, "countdown": (flags >> 4) & 15,
            "hits": [],
        }
        pos += EVENT
        for _ in range(count):
            target, kind, killed, shields, damage = struct.unpack_from("<BBHHH", data, pos)
            event["hits"].append(
                {
                    "target": target, "kind": kind, "killed": killed,
                    "shield_damage": shield_damage(shields), "damage": damage,
                }
            )
            pos += HIT
        out["events"].append(event)
    if pos != size:
        raise ValueError("battle %d: events overrun the record" % battle_id)
    return out


def read_battles(path):
    """The battles in one player turn file, in file order. A long record continues in the
    continuation blocks that follow its first one."""
    out = []
    pending = b""
    for b in starsfile.StarsFile.read(path).blocks:
        if b.type not in (T_BATTLE, T_BATTLE_MORE):
            continue
        if (b.type == T_BATTLE) != (not pending):
            raise ValueError("%s: battle blocks out of order" % path)
        pending += bytes(b.data)
        while len(pending) >= HEADER:
            size = struct.unpack_from("<H", pending, 6)[0]
            if len(pending) < size:
                break
            out.append(parse_record(pending[:size]))
            pending = pending[size:]
    if pending:
        raise ValueError("%s: an unfinished battle record" % path)
    return out


def game_battles(hst_path, players):
    """Every battle of the turn, from the turn files beside the host file, by battle id; each
    player's file holds the battles that player took part in. Records of the same battle must
    agree."""
    base = os.path.splitext(hst_path)[0]
    seen = {}
    for p in range(players):
        path = "%s.m%d" % (base, p + 1)
        if not os.path.exists(path):
            continue
        for battle in read_battles(path):
            if battle["id"] in seen and seen[battle["id"]] != battle:
                raise ValueError("battle %d differs between turn files" % battle["id"])
            seen[battle["id"]] = battle
    return [seen[k] for k in sorted(seen)]
