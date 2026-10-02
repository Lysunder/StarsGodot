"""Writes content/core/content/names.json: our own planet and race name lists (spec S07).

The planet names are built from invented syllables with a fixed seed, so the list is reproducible
and contains no text from the original game. Run from the repository root:

    python tools/gen_name_lists.py
"""

import json
import random

PLANET_COUNT = 1000  # S07: name ids 0..998, plus one more used only in the tutorial

STARTS = [
    "Ab", "Al", "Am", "Ar", "As", "Ba", "Be", "Bo", "Br", "Ca", "Ce", "Cr", "Da", "De", "Dr", "El",
    "Em", "Er", "Fa", "Fe", "Ga", "Ge", "Gr", "Ha", "He", "Ib", "Il", "Ir", "Ja", "Ka", "Ke", "Kr",
    "La", "Le", "Lu", "Ma", "Me", "Mo", "Na", "Ne", "No", "Ob", "Ol", "Or", "Pa", "Pe", "Qu", "Ra",
    "Re", "Ro", "Sa", "Se", "Si", "Ta", "Te", "Th", "Tr", "Ul", "Ur", "Va", "Ve", "Wa", "Xe", "Ya",
    "Ze", "Zo",
]
MIDDLES = [
    "", "", "", "ba", "de", "li", "ma", "no", "ra", "si", "te", "va", "lo", "ri", "ne", "ka",
]
ENDS = [
    "a", "ar", "as", "en", "er", "ia", "ic", "id", "il", "is", "ix", "on", "or", "os", "um", "us",
    "yr", "eth", "ane", "ost", "ura", "eon", "ica", "ova",
]

RACE_NAMES = [
    "Aldrani", "Bevrok", "Calistri", "Dorvane", "Elluvian", "Fenwari", "Galdric", "Hesperan",
    "Ismori", "Jovrel", "Kethari", "Lumarin", "Morvex", "Norrith", "Ostravi", "Pellune",
    "Quorani", "Rhodari", "Sylvane", "Tevrani", "Ulvaric", "Vexilli", "Wyrrani", "Zephiri",
]


def planet_names():
    rng = random.Random(20261001)
    seen = set()
    out = []
    while len(out) < PLANET_COUNT:
        name = rng.choice(STARTS) + rng.choice(MIDDLES) + rng.choice(ENDS)
        if name not in seen:
            seen.add(name)
            out.append(name)
    return out


def main():
    data = [
        {"type": "name_list", "id": "name_list.planets", "names": planet_names()},
        {"type": "name_list", "id": "name_list.races", "names": RACE_NAMES},
    ]
    with open("content/core/content/names.json", "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
