"""Writes the modding API reference (modding/api/) from the doc comments in core/.

One Markdown page per `class_name` under core/, plus an index (modding/api/README.md). Each page
holds the class's doc comment and its public constants, enums, signals, variables, functions and
inner classes, each with its `##` doc comment. Names that start with `_` are internal and left
out (except `_init`, shown as the constructor).

Run from the repository root after changing doc comments in core/:

    python tools/gen_api_docs.py

The output is committed. Never edit modding/api/ by hand: the next run overwrites it.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "core")
OUT = os.path.join(ROOT, "modding", "api")

# Longest constant or variable default shown inline; longer ones are left out.
MAX_VALUE = 70

# Classes a modder meets first, listed at the top of the index.
KEY_CLASSES = [
    "ModManifest",
    "ModLoader",
    "ModSource",
    "ContentRegistry",
    "ContentSchemas",
    "Ruleset",
    "StandardRuleset",
    "TurnPipeline",
    "Phase",
    "StandardTurn",
    "TurnContext",
    "RngStreams",
    "StarsRandom",
    "RaceMath",
    "GameState",
]

DECL = re.compile(
    r"^(?P<static>static\s+)?(?P<kind>func|var|const|signal|enum|class)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)


class Member:
    def __init__(self, kind, name, text, doc, static=False):
        self.kind = kind
        self.name = name
        self.text = text
        self.doc = doc
        self.static = static


class ClassDoc:
    def __init__(self, name, extends="", doc=None):
        self.name = name
        self.extends = extends
        self.doc = doc or []
        self.members = []
        self.inner = []


def indent_of(line):
    n = 0
    for ch in line:
        if ch == "\t":
            n += 1
        else:
            break
    return n


def scan_code(text):
    """Returns (code without comment, bracket depth change) for one line, skipping strings."""
    depth = 0
    out = []
    i = 0
    quote = None
    while i < len(text):
        ch = text[i]
        if quote:
            out.append(ch)
            if ch == "\\" and i + 1 < len(text):
                out.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        elif ch == "#":
            break
        else:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            out.append(ch)
        i += 1
    return "".join(out).rstrip(), depth


def doc_text(line):
    stripped = line.strip()
    if stripped == "##":
        return ""
    if stripped.startswith("## "):
        return stripped[3:]
    return stripped[2:]


def normalize_signature(parts):
    sig = " ".join(p.strip() for p in parts)
    sig = re.sub(r"\s+", " ", sig)
    sig = sig.replace("( ", "(").replace(" )", ")").replace(", )", ")").replace(",)", ")")
    sig = sig.replace(", }", " }").replace(",}", " }")
    if sig.endswith(":"):
        sig = sig[:-1].rstrip()
    return sig


def parse_file(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    cls = None
    extends = ""
    i = 0
    # class_name and extends come first (in either order), then the class doc block.
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith("class_name "):
            cls = s.split()[1]
            if " extends " in s:
                extends = s.split(" extends ", 1)[1].strip()
        elif s.startswith("extends "):
            extends = s.split(None, 1)[1].strip()
        elif s.startswith("@"):
            pass
        else:
            break
        i += 1
    if cls is None:
        return None
    result = ClassDoc(cls, extends)
    while i < len(lines) and lines[i].strip().startswith("##"):
        result.doc.append(doc_text(lines[i]))
        i += 1
    parse_body(lines, i, 0, result)
    return result


def parse_body(lines, i, level, target):
    """Parses declarations at indentation `level` into target until the block ends."""
    pending = []
    n = len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()
        if stripped == "":
            pending = []
            i += 1
            continue
        ind = indent_of(line)
        if ind < level:
            return i
        if ind > level:
            i += 1
            continue
        if stripped.startswith("##"):
            pending.append(doc_text(line))
            i += 1
            continue
        if stripped.startswith("#"):
            i += 1
            continue
        if level > 0 and stripped.startswith("extends "):
            target.extends = stripped.split(None, 1)[1].strip()
            i += 1
            # an inner class's doc block follows its extends line
            while i < n and lines[i].strip().startswith("##") and indent_of(lines[i]) == level:
                target.doc.append(doc_text(lines[i]))
                i += 1
            continue
        m = DECL.match(stripped)
        if not m:
            pending = []
            i += 1
            continue
        kind = m.group("kind")
        name = m.group("name")
        static = bool(m.group("static"))
        doc = pending
        pending = []
        if kind == "class":
            head = stripped.rstrip(":")
            inner = ClassDoc(name, doc=doc)
            if " extends " in head:
                inner.extends = head.split(" extends ", 1)[1].strip()
            i = parse_body(lines, i + 1, level + 1, inner)
            if not name.startswith("_"):
                target.inner.append(inner)
            continue
        # gather the whole declaration while brackets are open
        parts = []
        depth = 0
        j = i
        while j < n:
            code, d = scan_code(lines[j].strip())
            parts.append(code)
            depth += d
            j += 1
            if kind == "func":
                if depth <= 0 and code.endswith(":"):
                    break
            elif depth <= 0:
                break
        i = j
        if name.startswith("_") and name != "_init":
            continue
        if kind == "func":
            text = normalize_signature(parts)
            if name == "_init":
                text = re.sub(r"\s*->\s*void$", "", text.replace("func _init", "new", 1))
        elif kind in ("const", "var"):
            first, d0 = scan_code(lines[j - len(parts)].strip())
            if len(parts) == 1 and d0 == 0:
                text = first[:-1].rstrip() if first.endswith(":") else first
            else:
                text = re.split(r"\s*:?=\s*", first, maxsplit=1)[0]
                text = text.rstrip(":").rstrip()
            text = shorten_value(text)
        elif kind == "enum":
            text = normalize_signature(parts)
        else:
            text = normalize_signature(parts)
        target.members.append(Member(kind, name, text, doc, static))
    return i


def shorten_value(text):
    """Drops a const/var default that is too long to read inline."""
    m = re.match(r"^(.*?)(\s*:?=\s*)(.*)$", text)
    if not m:
        return text
    if len(m.group(3)) > MAX_VALUE:
        return m.group(1)
    return text


def first_sentence(doc):
    text = " ".join(line for line in doc if line).strip()
    if not text:
        return ""
    m = re.match(r"^(.+?[.!?])(\s|$)", text)
    return m.group(1) if m else text


def md_escape_cell(text):
    return text.replace("|", "\\|")


def render_doc(doc):
    out = []
    for line in doc:
        out.append(line)
    # trim blank lines at the ends
    while out and not out[0]:
        out.pop(0)
    while out and not out[-1]:
        out.pop()
    return "\n".join(out)


def link_type(name, known):
    if name in known:
        return "[`%s`](%s.md)" % (name, name)
    return "`%s`" % name


def render_members(cls, known, heading):
    out = []
    groups = [
        ("Constants", "const"),
        ("Enums", "enum"),
        ("Signals", "signal"),
        ("Variables", "var"),
    ]
    for title, kind in groups:
        items = [m for m in cls.members if m.kind == kind]
        if not items:
            continue
        out.append("%s %s\n" % (heading, title))
        for m in items:
            prefix = "static " if m.static and not m.text.startswith("static") else ""
            line = "- `%s%s`" % (prefix, m.text)
            doc = " ".join(d for d in m.doc if d)
            if doc:
                line += ": " + doc
            out.append(line)
        out.append("")
    funcs = [m for m in cls.members if m.kind == "func"]
    if funcs:
        out.append("%s Functions\n" % heading)
        for m in funcs:
            label = "new" if m.name == "_init" else m.name
            out.append("%s# `%s()`\n" % (heading, label))
            sig = m.text
            if m.name == "_init":
                sig = "%s.%s" % (getattr(cls, "qualname", cls.name), sig)
            if m.static and not sig.startswith("static"):
                sig = "static " + sig
            out.append("```gdscript\n%s\n```\n" % sig)
            doc = render_doc(m.doc)
            if doc:
                out.append(doc + "\n")
    return out


def render_class(cls, path, known):
    rel = os.path.relpath(path, ROOT).replace("\\", "/")
    out = ["# %s\n" % cls.name]
    meta = "`%s`" % rel
    if cls.extends:
        meta += ", extends %s" % link_type(cls.extends, known)
    out.append(meta + "\n")
    doc = render_doc(cls.doc)
    out.append((doc if doc else "*No class doc comment.*") + "\n")
    out.extend(render_members(cls, known, "##"))
    for inner in cls.inner:
        inner.qualname = "%s.%s" % (cls.name, inner.name)
        out.append("## Inner class `%s.%s`\n" % (cls.name, inner.name))
        if inner.extends:
            out.append("Extends %s.\n" % link_type(inner.extends, known))
        doc = render_doc(inner.doc)
        if doc:
            out.append(doc + "\n")
        out.extend(render_members(inner, known, "###"))
    out.append("---\n")
    out.append("*Generated by `tools/gen_api_docs.py` from the doc comments in `%s`.*" % rel)
    text = "\n".join(out)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.rstrip("\n") + "\n"


def render_index(classes):
    by_dir = {}
    for cls, path in classes:
        d = os.path.relpath(os.path.dirname(path), ROOT).replace("\\", "/")
        by_dir.setdefault(d, []).append((cls, path))
    names = {cls.name: (cls, path) for cls, path in classes}
    out = [
        "# API reference\n",
        "Generated from the `##` doc comments in `core/` by `tools/gen_api_docs.py`. Do not edit these",
        "pages by hand; change the doc comment and run the tool again.\n",
        "**Status: experimental.** The mod API is version 1 (`ModLoader.API_VERSION`). There is no",
        "separate `ModAPI` facade yet, so these pages list every public name in `core/`. Names that",
        "start with `_` are internal and not listed. Anything here may still change before 1.0; the",
        "classes most likely to stay are the ones listed first.\n",
        "## Start here\n",
        "| Class | File | Summary |",
        "|---|---|---|",
    ]
    for name in KEY_CLASSES:
        if name in names:
            cls, path = names[name]
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            out.append(
                "| [`%s`](%s.md) | `%s` | %s |"
                % (name, name, rel, md_escape_cell(first_sentence(cls.doc)))
            )
    out.append("")
    out.append("## All classes, by folder\n")
    for d in sorted(by_dir):
        out.append("### `%s/`\n" % d)
        out.append("| Class | Summary |")
        out.append("|---|---|")
        for cls, path in sorted(by_dir[d], key=lambda cp: cp[0].name):
            out.append(
                "| [`%s`](%s.md) | %s |"
                % (cls.name, cls.name, md_escape_cell(first_sentence(cls.doc)))
            )
        out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


def main():
    classes = []
    for dirpath, dirnames, filenames in os.walk(SRC):
        dirnames.sort()
        for fn in sorted(filenames):
            if not fn.endswith(".gd"):
                continue
            path = os.path.join(dirpath, fn)
            cls = parse_file(path)
            if cls is not None:
                classes.append((cls, path))
    classes.sort(key=lambda cp: cp[0].name)
    seen = set()
    for cls, path in classes:
        if cls.name in seen:
            sys.exit("duplicate class_name %s" % cls.name)
        seen.add(cls.name)
    known = seen
    os.makedirs(OUT, exist_ok=True)
    for fn in os.listdir(OUT):
        if fn.endswith(".md"):
            os.remove(os.path.join(OUT, fn))
    for cls, path in classes:
        with open(os.path.join(OUT, cls.name + ".md"), "w", encoding="utf-8", newline="\n") as f:
            f.write(render_class(cls, path, known))
    with open(os.path.join(OUT, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(render_index(classes))
    print("wrote %d class pages to %s" % (len(classes), os.path.relpath(OUT, ROOT)))


if __name__ == "__main__":
    main()
