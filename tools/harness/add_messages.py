"""Adds each player's turn messages (S21) and view (S15) to existing golden fixtures, from the original's turn files
in the harness runs, leaving everything else in the fixtures as it is.

    python tools/harness/add_messages.py <fixture folder> <run folder>

For every tNNN.json in the fixture folder the run folder's tNNN/ must hold the host file (*.hst) and
the players' turn files (*.m1, *.m2 ...).
"""

import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stars_import  # noqa: E402


def main(fixtures, runs):
    legacy = stars_import.Legacy()
    for path in sorted(glob.glob(os.path.join(fixtures, "t[0-9][0-9][0-9].json"))):
        turn = os.path.basename(path)[:4]
        hosts = glob.glob(os.path.join(runs, turn, "*.hst"))
        if len(hosts) != 1:
            print("skipped %s: no host file in %s" % (path, os.path.join(runs, turn)))
            continue
        if not glob.glob(os.path.join(runs, turn, "*.m[0-9]*")):
            print("skipped %s: no turn files (it keeps no message data)" % path)
            continue
        with open(path, encoding="utf-8") as f:
            save = json.load(f)
        state = save["state"]
        state["messages"] = stars_import.player_messages(hosts[0], len(state["players"]), legacy)
        state["views"] = stars_import.player_views(hosts[0], state)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(save, f, indent=1, sort_keys=True)
            f.write("\n")
        print(path, [len(m) for m in state["messages"]])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
