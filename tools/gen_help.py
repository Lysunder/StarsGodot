"""Builds the help strings from their Markdown sources.

content/core/help/<locale>/NN-<topic>.md (first line "# Title", then the body) becomes
content/core/lang/help/<locale>.json with "help.index" (the topic ids in file order, space
separated), "help.<topic>.title" and "help.<topic>.body". The body keeps its markup; the help
window draws it (## headings, - bullets, **bold**, [[topic]] or [[topic|text]] links, {key:action}
for the player's key for an action, {keys} for the list of all of them).

    python tools/gen_help.py          writes the files
    python tools/gen_help.py --check  fails when a file is out of date
"""

import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
SOURCES = os.path.join(ROOT, "content", "core", "help")
OUT = os.path.join(ROOT, "content", "core", "lang", "help")
NAME = re.compile(r"^\d+-([a-z_]+)\.md$")


def build(locale):
    folder = os.path.join(SOURCES, locale)
    strings = {}
    ids = []
    for file in sorted(os.listdir(folder)):
        m = NAME.match(file)
        if not m:
            continue
        topic = m.group(1)
        text = open(os.path.join(folder, file), encoding="utf-8").read().strip("\n")
        first, _, body = text.partition("\n")
        if not first.startswith("# "):
            sys.exit("%s/%s: the first line must be '# Title'" % (locale, file))
        ids.append(topic)
        strings["help.%s.title" % topic] = first[2:].strip()
        strings["help.%s.body" % topic] = body.strip("\n")
    strings["help.index"] = " ".join(ids)
    return json.dumps(dict(sorted(strings.items())), indent=2, ensure_ascii=False) + "\n"


def main():
    check = "--check" in sys.argv
    stale = []
    for locale in sorted(os.listdir(SOURCES)):
        if not os.path.isdir(os.path.join(SOURCES, locale)):
            continue
        text = build(locale)
        path = os.path.join(OUT, locale + ".json")
        old = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if old == text:
            continue
        if check:
            stale.append(path)
        else:
            os.makedirs(OUT, exist_ok=True)
            open(path, "w", encoding="utf-8", newline="\n").write(text)
            print("wrote", os.path.relpath(path, ROOT))
    for path in stale:
        print("out of date (run tools/gen_help.py):", os.path.relpath(path, ROOT))
    sys.exit(1 if stale else 0)


if __name__ == "__main__":
    main()
