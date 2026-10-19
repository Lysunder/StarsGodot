"""Lists the interface's own text for translators, and wraps format strings in tr().

The interface's text lives in ui/ as English string literals. Godot translates text set on
controls as it is drawn; text the game formats itself ("%s Summary" % name) must go through tr()
so its English form is what gets looked up. This tool finds both kinds:

    python tools/gen_ui_strings.py            writes modding/translation_template.json
    python tools/gen_ui_strings.py --check    fails when the template is out of date
    python tools/gen_ui_strings.py --wrap     wraps human-readable format strings in tr()
    python tools/gen_ui_strings.py --list     prints what it would wrap

The template holds every "ui.<English>" key with its English text, then the content's own display
strings (names, help, messages) from content/core/lang/, so a translation mod can start from a
copy of it (see modding/translating.md).
"""

import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
UI = os.path.join(ROOT, "ui")
TEMPLATE = os.path.join(ROOT, "modding", "translation_template.json")
LANG = os.path.join(ROOT, "content", "core", "lang")

STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
# where a literal is text the player reads
UI_CONTEXT = re.compile(
    r"(?:\b(?:text|title|tooltip_text|dialog_text|placeholder_text|ok_button_text|cancel_button_text)"
    r"\s*=\s*$)|(?:\b(?:tr|add_item|add_check_item|add_radio_check_item|add_separator|set_item_text|"
    r"_keyed_item\(\w+,|_heading|_label|_bold|button|_button|_field|add_tab|set_tab_title)\(\s*$)"
)
WORD = re.compile(r"[A-Za-z]{2,}")
NOT_TEXT = re.compile(r"://|^[a-z_]+(\.[a-z_%0-9]+)+$|^[a-z_]+/|\.(png|json|cfg|gd|tscn)$|^#")


# formatted for the game's own use, not for reading
NOT_UI = {"player %d ", "player %d order %d: "}


def human(text):
    """Whether a literal reads like text for the player."""
    if text in NOT_UI or text.startswith("[") or not WORD.search(text) or NOT_TEXT.search(text):
        return False
    if re.fullmatch(r"[a-z_]+", text):
        return False
    return " " in text or text[:1].isupper() or text.endswith("...")


def code_lines(path):
    in_comment = False
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        yield number, line.rstrip("\n")


def literals(line):
    """(start, end, text) of each string literal outside a trailing comment."""
    out = []
    for m in STRING.finditer(line):
        before = line[: m.start()]
        if before.count('"') % 2 == 1 or "#" in re.sub(STRING, "", before):
            continue
        out.append((m.start(), m.end(), m.group(1)))
    return out


def ui_files():
    """The interface's scripts; the theme's (control type names, font names) aren't text."""
    for folder, _dirs, files in sorted(os.walk(UI)):
        if os.path.basename(folder) == "theme":
            continue
        for file in sorted(files):
            if file.endswith(".gd"):
                yield os.path.join(folder, file)


def wraps(path):
    """Format strings to wrap: human literals followed by % and not already in tr()."""
    found = []
    for number, line in code_lines(path):
        for start, end, text in literals(line):
            after = line[end:].lstrip()
            if not after.startswith("%") or after.startswith("%="):
                continue
            if line[:start].rstrip().endswith(("tr(", "translate(")):
                continue
            if human(text):
                found.append((number, start, end, text))
    return found


def in_static(lines, number):
    """Whether line `number` is in a static function, where there is no tr()."""
    for i in range(number - 1, -1, -1):
        line = lines[i]
        if line.startswith(("func ", "static func ")):
            return line.startswith("static func ")
        if line.startswith(("var ", "const ", "class ")):
            return True
    return True


def wrap_all():
    total = 0
    for path in ui_files():
        found = wraps(path)
        if not found:
            continue
        lines = open(path, encoding="utf-8").read().split("\n")
        for number, start, end, _text in reversed(found):
            line = lines[number - 1]
            call = "TranslationServer.translate(" if in_static(lines, number) else "tr("
            lines[number - 1] = line[:start] + call + line[start:end] + ")" + line[end:]
        open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
        total += len(found)
    print("wrapped", total)


def ui_texts():
    texts = set()
    for path in ui_files():
        for _number, line in code_lines(path):
            for start, end, text in literals(line):
                before = line[:start]
                if before.rstrip().endswith(("tr(", "translate(")) or UI_CONTEXT.search(before):
                    if human(text):
                        texts.add(text)
                elif human(text) and (
                    line[end:].lstrip().startswith("%")
                    or "[" in before
                    or before.rstrip().endswith(":")
                ):
                    # format strings and lists of labels (const tables of [id, label, ...])
                    if " " in text or text[:1].isupper():
                        texts.add(text)
    return sorted(t.encode().decode("unicode_escape") if "\\" in t else t for t in texts)


def template():
    out = {"ui." + t: t for t in ui_texts()}
    for folder, _dirs, files in os.walk(LANG):
        for file in sorted(files):
            if file == "en.json":
                out.update(json.load(open(os.path.join(folder, file), encoding="utf-8")))
    return json.dumps(dict(sorted(out.items())), indent=2, ensure_ascii=False) + "\n"


def main():
    if "--list" in sys.argv:
        for path in ui_files():
            for number, _s, _e, text in wraps(path):
                print("%s:%d  %s" % (os.path.relpath(path, ROOT), number, text))
        return
    if "--wrap" in sys.argv:
        wrap_all()
        return
    text = template()
    old = open(TEMPLATE, encoding="utf-8").read() if os.path.exists(TEMPLATE) else None
    if "--check" in sys.argv:
        if old != text:
            print("out of date (run tools/gen_ui_strings.py):", os.path.relpath(TEMPLATE, ROOT))
            sys.exit(1)
        return
    if old != text:
        open(TEMPLATE, "w", encoding="utf-8", newline="\n").write(text)
        print("wrote", os.path.relpath(TEMPLATE, ROOT))


if __name__ == "__main__":
    main()
