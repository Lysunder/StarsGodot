# S26 Classic asset import

Status: draft (2026-10-18; implemented: `classic_import/`, the art registry `ui/art_registry.gd`, message wording; shown so far: ship and planet pictures). Read from the decompiled code and from the resource table of the player's executable;
no harness checks yet. Formats were checked with a throw-away probe outside the repository (every bitmap resource
decodes with Godot's own BMP loader); nothing extracted was kept.
References: `LoadAppResources@1000:0000` (start-up loads of bitmaps, icons and cursors), `LoadResourceFile@1038:ad28`,
`DrawDIB@1038:aa4e`, `DrawDesignPicture@1048:2d28`, `Tile_DrawTitle@1040:2280`, `Summary_Paint@1020:04e8`,
`ShipDesigner_DrawHull@10c0:185e`, `Designer_DragPart@10c0:1f4c`, `Designer_DrawListItem@10c0:3d1a`,
`Browser_Paint@10d0:1e06`, `RACEWIZARDDLG1@10d8:0336`, `Toolbar_Paint@1060:05a4`, `Scanner_DrawMap@1050:0b46`,
`MessagePane_DrawButtons@1028:6fc6`, `VCR_DrawBoard@10e0:256a`, `TITLEWNDPROC@1018:60f6`,
`InitDisplayMetrics@1010:054c` (run-time palette patches), `GetString@1038:8df4`, `GetMessageTemplate@1028:8864`,
`ExpandMessageCodes@1028:7778`, `Tutor_GetStepText@10f0:6524`, `Tutorial_ExtractTurnFile@1040:7eea`. Decisions D13 and D15; MODDING.md §10; S04
(picture numbers), S21 (message ids and parameters).

## Summary

The base game ships with our own placeholder art and our own text. A player who owns Stars! 2.6i can point the
game at their install folder, and an importer inside the game reads the executable and the help file there and
writes a **cosmetic mod**, `user://mods/classic/`: PNG images keyed by our art ids, and language files keyed by our
string keys. The game then shows the classic ship, planet, part and race pictures (and, optionally, the classic
message wording) through the normal cosmetic-mod path.

Rules that follow from D13:

- Nothing the importer produces is committed, shipped, used in test fixtures or shown in public screenshots. The
  repository holds only the importer code, this spec, and a mapping of numbers (resource ids, sprite indices,
  picture numbers, message numbers) to our ids.
- The base game must work, and look complete, without the pack. Every hook that can show classic art falls back
  to our own drawing when the art id has no texture.
- The pack never affects the ruleset hash (MODDING.md §1.6): it has no `content/` or `patches/`.
- The importer never touches the registration or serial-number code or data, and never reads `code.txt` or any
  registration file in the install folder.
- The importer is game code in the top-level `classic_import/` folder (it runs from a menu command and ships with
  the game; `tools/` is left out of exports). The mapping file next to `content/core/legacy_ids.json` holds numbers
  only, the part picture numbers included. Importing the original's turn-message wording into the local pack is
  allowed (owner's decision, 2026-10-18).

## Data used

### Input files (in the player's install folder)

| File | Used | Notes |
|---|---|---|
| `stars26i.exe` | yes | 16-bit Windows NE executable, about 3.2 MB. Holds every bitmap, icon and cursor, and the packed string tables. |
| `stars!.hlp` | optional | WinHelp 3.1 file, about 1.6 MB: help topics and 133 help pictures. |
| `ctl3dv2.dll`, `hyprfind.dll` | no | Third-party run-time libraries (3D controls, help search). No game assets. |
| `wavemix.dll` (some copies) | no | A sound mixer the 2.6i executable never calls; the game has no sound or music files. |

The importer identifies the executable by its NE header and checks the resource table against the expected
layout (every resource listed below present, with the stated size and bit depth). A SHA-256 of known-good files may
be kept in the mapping file to label the version; an unknown build that passes the layout check is accepted with a
warning, one that fails is refused with a message naming the first mismatch.

### NE resource table

Reached from the MZ header (`e_lfanew` at file offset 0x3C) and the NE header (resource-table offset at NE + 0x24,
relative to the NE header). The table starts with an alignment shift (6 in 2.6i: offsets and lengths are in
64-byte units). Then type entries until a zero type word: type id (bit 15 set = numeric id in the low 15 bits,
otherwise an offset to a length-prefixed name in the table), resource count, 4 reserved bytes, then per resource
12 bytes: offset, length, flags, id (same numeric/name rule), 4 reserved bytes.

Resource types in 2.6i:

| Type | Count | Notes |
|---|---|---|
| BITMAP (2) | 38 | Packed DIBs (40-byte BITMAPINFOHEADER, colour table, pixels; no file header). Uncompressed. |
| ICON (3) / GROUP_ICON (14) | 10 / 10 | 32×32, 16 colours, with AND mask. |
| CURSOR (1) / GROUP_CURSOR (12) | 11 / 11 | 32×32 monochrome with AND mask; 4-byte hotspot before the DIB. |
| DIALOG (5) | 36 | Not imported (our UI is our own, D15). |
| MENU (4) | 1 | Not imported. |
| ACCELERATOR (9) | 2 | Not imported (our KeyBindings define the keys). |
| Numeric types 10000, 10002, 10004 | 1 each | Tutorial data (scripted orders and two embedded turn files, read by `Tutorial_ExtractTurnFile`). Not imported: the tutorial is new content (M11 item 11). |

There are no string, font, version or sound resources.

### Bitmap formats

- 25 bitmaps are 8-bit. 23 of them share one 256-entry palette (the game builds its palette from bitmap 555);
  the title picture (449) and the designer graphic (1079) each have their own.
- 5 bitmaps are 4-bit with the standard 16-colour palette (one, the cargo pattern, has its own 16 entries).
- 8 bitmaps are 1-bit (patterns and masks).
- Pixel rows are stored bottom-up. The original draws sprites with `StretchDIBits`, whose source y is measured
  from the **bottom** of the bitmap; for monochrome and 4-bit bitmaps loaded as device bitmaps (`BitBlt`) the
  source y is measured from the **top**. The tables below give rows counted from the top of the picture as seen.
- Conversion: prepend a 14-byte BITMAPFILEHEADER (`"BM"`, total size, pixel-data offset = 14 + header size + 4 ×
  colours, where colours = the header's used-colour count, or 2^bits when that is 0) and decode with
  `Image.load_bmp_from_buffer`. All 38 bitmaps decode this way; the whole set takes under a second.

### Transparency

Sprites are drawn opaque (SRCCOPY) onto black panels, so ship, planet, part, logo and object pictures keep their
black background; the importer leaves them opaque. Exceptions:

| Bitmap | Rule |
|---|---|
| 178 (toolbar strip) | Palette entry 253 is replaced at run time by the button-face colour: import it as transparent. |
| 1079 (designer graphic) | Palette entry 249, same rule. |
| 199 + 134 | A monochrome mask and a 16-colour image drawn as a pair (AND then OR): combine into one RGBA image, mask white = transparent. |
| Icons, cursors | Standard XOR image + AND mask: AND = 1 means transparent. |
| 1-bit patterns and symbols (88, 249, the 8×8 patterns, the unknown-planet picture) | Drawn with the current text and background colours: import as white-on-transparent so our code can tint them. |

## Algorithm

### 1. Sprite sheets and their indices

Picture numbers below are the original's indices, which our content already stores where they matter (`Design.picture`
and hull `pictures`, S04).

| Resource(s) | Size, depth | Tile | Content and index rule | Our art ids |
|---|---|---|---|---|
| 552, 553, 554, 555, 556 | 512×256 ×4 and 320×256, 8-bit | 64×64 | Ship and starbase pictures, 148 in all (4 per hull). Picture *n* (the design's picture modulo 148): sheet *n* ÷ 32, column (*n* ÷ 4) mod 8, row *n* mod 4. The last sheet has 5 columns. | `art.hull.<hull>.<k>` for each hull and *k* = 0..3, *n* = hull `pictures` + *k* |
| 557 … 561 | half of the above, 8-bit | 32×32 | The same 148 pictures, small, same layout. | `art.hull.<hull>.<k>.small` |
| 500 … 506 | 512×256 ×6 and 256×256, 8-bit | 64×64 | Part pictures. Picture *p* (the part's picture number, S04 record offset 50): sheet *p* ÷ 32, column *p* mod 8, row (*p* ÷ 8) mod 4. The last sheet has 4 columns. Numbers in use run 0..209. | `art.<part id>` (for example `art.part.beam.laser`) |
| 112 | 448×256, 8-bit | 64×64 | Planet pictures, 28, in 7 columns × 4 rows. Picture *k*: column *k* mod 7, row 3 − *k* ÷ 7 (rows counted from the bottom). A planet shows picture (planet number + 8) mod 28. | `art.planet.<k>` |
| UNKNOWNPLANETBMP | 64×64, 1-bit | — | Picture for a planet never scanned. | `art.planet.unknown` |
| 133 | 256×128, 8-bit | 32×32 | Race logos, 32: logo *L* at column *L* mod 8, row *L* ÷ 8. | `art.race_logo.<L>` |
| 80 | 128×64, 8-bit | 16×16 | The same 32 logos, small (drawn in a corner of a ship picture to show its owner). Same layout. | `art.race_logo.<L>.small` |
| 79 | 64×32, 8-bit | 8×8 | The same 32 logos, tiny. Same layout. | `art.race_logo.<L>.tiny` |
| 87 | 448×64, 8-bit | 64×64 | Map objects, 7 in one row: 0, 1, 2 the three minefield kinds (by the minefield's kind number), 3 and 4 packet and salvage (chosen by a flag of the object; which is which is an open question), 5 wormhole, 6 Mystery Trader. | `art.object.minefield.<kind>`, `art.object.packet`, `art.object.salvage`, `art.object.wormhole`, `art.object.mystery_trader` |
| 119 | 576×192, 4-bit | 64×64 | Empty-slot backgrounds in the ship designer, 9 columns × 3 rows, indexed by the slot's kind (`Designer_CountSlotType`). Rows from the top. | `art.slot.<index>` (mapping from our slot categories: open question) |
| 1079 | 60×30, 8-bit | — | A designer graphic (role to confirm). | `art.designer.1079` until named |
| 178 | 432×23, 8-bit | 24×23 | Scanner toolbar buttons, 18 in a row at x = 24 *i*. | `ui.toolbar.<i>` (names once the order is confirmed) |
| SCANNERBMP | 48×101, 4-bit | irregular | Small scanner-map markers (for example 11×11 squares), used by the scanner, summary and designer. The rectangle table is still to be listed. | `art.scanner.<name>` |
| 88 | 16×72, 1-bit | to confirm | Scanner symbols drawn with the text colour (fleet markers). | `art.scanner.symbol.<i>` |
| 249 | 44×7, 1-bit | to confirm | Tiny glyphs for scanner labels. | `art.scanner.glyphs` |
| 199 + 134 | 15×84 and 16×66 | 15×15 | Small mask-and-colour buttons in the Messages pane and the score window. | `ui.small_button.<i>` |
| SCREEN50BMP, 460, 461, 462, CARGOBMP, DOCKBMP | 8×8 | — | Brush patterns: a 50% screen, three hatchings, the designer's cargo and dock fills. | `ui.pattern.<name>` |
| 449 | 800×600, 8-bit | — | Title picture (own palette). | `art.title` |
| GROUP_ICON ×10 | 32×32 | — | Application, host and waiting icons; three explosion and four torpedo frames (battle viewer). | `ui.icon.app`, `ui.icon.host`, `ui.icon.wait`, `art.battle.explosion.<1..3>`, `art.battle.torpedo.<1..4>` |
| GROUP_CURSOR ×11 | 32×32 | — | Four named cursors (scanner, scanner add, open hand, closed hand) and seven numbered ones (roles to confirm). | `ui.cursor.<name>` with hotspot |

Ids follow one rule: art for a content definition is `art.` + its content id (plus `.<k>` for one of several
pictures, and `.small` / `.tiny` for size variants); interface pieces start with `ui.`. A gameplay mod that adds a
hull or a part gets classic-style art the same way, from any cosmetic pack that supplies its id.

### 2. Packed string tables (optional text import)

Three tables live in code segments, all in the same nibble-packed scheme (a character table, a word per group of 64
strings giving the start in the nibble stream, a byte per string giving its length in nibbles, then the stream;
nibble 15 means "add 15 and continue", any other nibble ends a character):

| Table | NE segment | Strings | Size | Importer use |
|---|---|---|---|---|
| Interface strings (`GetString`) | 8 (1038) | 1327 | about 45,000 characters | Not in the first version (our UI has no string keys yet). |
| Turn-message templates (`GetMessageTemplate`) | 6 (1028) | 446 | about 45,000 characters | `message.<x>.text` keys. |
| Tutorial pages (`Tutor_GetStepText`) | 31 (10f0) | 640 slots | about 36,000 characters | Never (the tutorial is new content). |

Offsets of each table inside its segment are recorded in the mapping file (not repeated here). Segment *i*'s file
offset is the segment table entry *i* (NE + word at 0x22, 8 bytes per entry, 1-based) shifted by the alignment
word at NE + 0x32.

**Message templates.** `content/core/legacy_ids.json` already maps each of our message ids to the original's
message number. A template holds plain characters and backslash codes; each code consumes the next parameter(s)
of the message and formats them by kind (`ExpandMessageCodes`). The importer turns each code into our placeholder
`{i}` for the parameter it consumes, using a code table kept in the mapping file (code letter → number of
parameters consumed), and checks the result against the message's `params` list in our content: the count of
placeholders must match, otherwise that message keeps our wording and the importer reports it. Characters are
Windows-1252 and are converted to UTF-8.

### 3. Help file (optional, later)

WinHelp 3.1: a header, an internal directory (a B+ tree of internal file names and offsets), and internal files.
`|TOPIC` is LZ77-compressed in 4 KB blocks and may use `|Phrases` substitution; `|CTXOMAP` maps the 419 context
numbers the game passes to WinHelp to topic offsets; `|TTLBTREE` gives topic titles. The 133 pictures are internal
files `|bm<n>`: 128 DIBs (116 at 4 bits, 11 at 8 bits, 1 at 1 bit, up to 623×544, all run-length packed in
WinHelp's own scheme) and 5 Windows metafiles (skipped). A classic help pack would be `help/topics.json` (context
number → title and plain text with picture references) plus `help/bm<n>.png`, shown by a local help viewer. Not in
the first version.

### 4. Output layout

```
user://mods/classic/
  mod.json            kind "cosmetic", id "classic", version = importer version; "source": exe size and
                      SHA-256, import date. No content/ or patches/.
  art/index.json      art id -> {"file": "sheets/<name>.png", "rect": [x, y, w, h]} (rect optional),
                      plus "hotspot": [x, y] for cursors and "tint": true for 1-bit symbols
  art/sheets/*.png    one PNG per source bitmap, icon or cursor, converted whole (rects index into them)
  lang/en.json        message.<x>.text keys (only when the player chose to import text)
  help/               later (section 3)
```

Sheets are kept whole and indexed by rectangles, so the PNGs are a faithful conversion and the rectangles carry
the layout from section 1. Re-running the importer replaces the folder.

### 5. Import steps

1. The player picks the install folder (a folder dialog; the game never searches the disk).
2. Read `stars26i.exe`, parse the NE header and resource table, run the layout check.
3. Decode each bitmap, icon and cursor; apply the transparency rules; write the sheets.
4. Build `art/index.json` from section 1: fixed tables for planets, logos, objects, slots and chrome; for hulls
   from each hull's `pictures` in the loaded content; for parts from the part picture numbers in the mapping file.
5. If text import was chosen, decode the message table, convert codes, write `lang/en.json`.
6. Write `mod.json` last (a half-written folder has no manifest and is ignored), enable the mod in the player's
   settings, and reload art.

## Randomness

None.

## Edge cases

- A design whose picture is outside its hull's four is already folded back by S04; the picture lookup never
  sees an index of 148 or more.
- Hulls or parts added by gameplay mods have no classic art: the hook falls back to our placeholder.
- An install without `stars!.hlp` imports everything except help.
- The folder may be read-only or on a CD image: the importer only reads it.
- A partial or failed import leaves no `mod.json`, so nothing half-done is ever loaded.
- Two cosmetic mods supplying the same art id: the later in load order wins, as for strings.

## Known bugs

None.

## Worked examples

- Design picture 37 (a hull whose first picture is 36, second variant): sheet 1 (bitmap 553), column 1, row 1:
  the 64×64 tile at (64, 64) from the top-left of that sheet; the small version is the 32×32 tile at (32, 32) of
  bitmap 558.
- Part picture 209: sheet 6 (bitmap 506), column 1, row 2: the tile at (64, 128).
- Planet number 5: picture (5 + 8) mod 28 = 13: column 6, row 3 − 1 = 2: the tile at (384, 128) of bitmap 112.
- Race logo 19: column 3, row 2: tile (96, 64) of bitmap 133; (48, 32) of bitmap 80; (24, 16) of bitmap 79.

## Mod hooks

- Art ids as listed in section 1, read through the art registry (UI side): any cosmetic mod can supply them with
  `art/index.json`, not only the classic pack.
- String keys `message.<x>.text` (S21), overridable by any cosmetic mod's `lang/<locale>.json`.

## Open questions

1. Object pictures 3 and 4: which is the packet and which the salvage (the choosing flag in the object record).
2. Planet picture: confirm the value fed to (n + 8) mod 28 is the planet's number.
3. Rectangles inside SCANNERBMP and bitmaps 88 and 249; the order of the 18 toolbar buttons; roles of the seven
   numbered cursors and of bitmap 1079; the slot-kind index used for bitmap 119.
4. The message code table: list each backslash code and how many parameters it consumes; check our 306 mapped
   messages convert cleanly.
5. Whether other builds (2.6j, 2.7) use the same resource ids; until checked only the layout of the 2.6i build
   is accepted.
