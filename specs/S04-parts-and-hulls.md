# S04 Parts and hulls

Status: draft (2026-09-30). Static data extracted from the original's tables and cross-checked against S.B. Posey's
spreadsheet; per-item effects read from the design-stat code. Open items listed at the end.
References: `GetPartInfo@1008:50f8`, `GetHull@1008:507c`, `GetEngine@1008:50a2`, `GetScannerPart@1008:50b0`,
`MeetsTechRequirements@1008:587a`, `Design_UpdateStats@1030:2dbe`, `Design_GetShields@1030:0a0e`,
`Design_GetCapacity@1048:29a0`, `Slot_CloakUnits@1078:20c8`, `Design_JammingFactor@10c0:2d7c`,
`Design_BattleComputers@10e8:2636`, `Design_BattleMovement@10e8:216e`, `Design_SweepRate@1078:1d1c`,
`Design_ScannerRange@1030:336a`, `GenerateFleetFuel@10a8:1cfa`.

## Summary

Every part and hull is a fixed record in the original: tech requirements, name, mass, cost, and a few
category-specific numbers. Some parts also have effects that aren't in their record at all: the design-stat code
adds them by checking the part's category and item number (for example, a shield that also gives armor, or a cargo
pod that also cloaks). This spec lists every item with all of its effects, so our content can describe each part
completely as data, and says how a design's simple totals (mass, armor, shields, fuel, cargo) are formed.

How an effect works in play (cloaking percentages, jamming against torpedoes, battle movement, scanning, mines,
bombs) belongs to the subsystem specs (S12, S13, S15, S16, S17). This spec only says what each part contributes.

## Data used

### Item kinds

Ship parts are identified by a category bit (the slot category) and an item number. The same codes also identify
groups that don't go in ship slots.

| Kind | Category | Items | Our `category` |
|---|---|---|---|
| 0x0001 | Engine | 16 | `engine` |
| 0x0002 | Scanner | 16 | `scanner` |
| 0x0004 | Shield | 10 | `shield` |
| 0x0008 | Armor | 12 | `armor` |
| 0x0010 | Beam weapon | 24 | `beam` |
| 0x0020 | Torpedo or missile | 12 | `torpedo` |
| 0x0040 | Bomb | 15 | `bomb` |
| 0x0080 | Mining robot | 8 | `mining_robot` |
| 0x0100 | Mine layer | 10 | `mine_layer` |
| 0x0200 | Orbital (stargates, mass drivers) | 16 | `orbital` |
| 0x0800 | Electrical | 17 | `electrical` |
| 0x1000 | Mechanical | 11 | `mechanical` |
| 0x8000 | Planetary (planet scanners, defenses, Genesis Device) | 15 | `planetary` |
| 0x2000 | Terraforming | 20 | `terraform` |
| 0x4000 | Ship hulls (ids 0–31) | 32 | hull |
| 0x0400 | Starbase hulls (ids 32–36) | 5 | hull with `starbase: true` |

In a hull's slot list, bit 0x0400 means "planetary". It only appears together with 0x0200 in starbase orbital slots.

### Part record

All part records share a 52-byte head. Categories with more numbers add words after it.

| Offset | Size | Meaning |
|---|---|---|
| 0 | word | item number + 1 |
| 2 | 6 bytes | minimum tech level: energy, weapons, propulsion, construction, electronics, biotech |
| 8 | 32 bytes | name (zero-padded) |
| 40 | word | mass (kT) |
| 42 | word | resource cost |
| 44, 46, 48 | words | ironium, boranium, germanium cost |
| 50 | word | picture number (cosmetic) |
| 52 | words | category-specific values (below) |

| Category | Record size | Values from offset 52 |
|---|---|---|
| Engine | 78 | a code word (meaning open), fuel use at warp 0–10 (11 words), a zero word |
| Scanner | 56 | normal range (ly); a code word (not the penetrating range; open item) |
| Shield, armor | 54 | shield or armor value |
| Beam | 60 | range, power, initiative, flags (1 = sapper, 2 = gatling) |
| Torpedo | 60 | range, power, initiative, base accuracy (%) |
| Bomb | 58 | always 1; population kill (tenths of a percent); installations destroyed |
| Mining robot | 54 | mining rate |
| Mine layer | 54 | mines laid per year ÷ 10 (items 0–3 standard, 4–6 heavy, 7–9 speed bump; content stats `mines_standard`, `mines_heavy`, `mines_speed_bump`) |
| Orbital | 56 | stargates: mass limit, range (−1 = unlimited); mass drivers: warp, 0 |
| Electrical, mechanical | 54 | one value whose meaning depends on the item (see "Per-item effects") |
| Planetary | 54 | scanners: range (negative = penetrating); defenses: coverage value |
| Terraforming | 54 | amount |

### Hull record (143 bytes)

| Offset | Size | Meaning |
|---|---|---|
| 0 | word | hull number within its table |
| 2 | 6 bytes | minimum tech levels |
| 8 | 32 bytes | name |
| 40 … 50 | words | mass, resources, ironium, boranium, germanium, picture number |
| 52 | word | ship hulls: cargo capacity. Starbases: largest ship mass the dock can build (−1 = unlimited, 0 = no dock) |
| 54 | word | fuel capacity (mg) |
| 56 | word | armor |
| 58 | 16 × 4 bytes | slots: category mask (word), an unused byte, capacity (byte); unused slots are zero |
| 122 | byte | number of slots in use |
| 123 | byte | low 6 bits: initiative. Bits 6–7: hull role flags (open item) |
| 124 | byte | a hull class byte (open item) |
| 125 | word | designer layout of the cargo bay (or a starbase's dock), used when offset 52 is not 0: high byte one corner, low byte the opposite corner, each as below |
| 127 … | 1 byte per slot | designer layout of each slot: low nibble x, high nibble y |

**Designer layout (cosmetic, `Designer_LayoutSlots@10c0:450c`).** The ship designer draws a hull as boxes on a
grid of half-slot cells (32 pixels in the original): slot *i* is a 2 × 2-cell box whose top-left cell is the slot's
(x, y) byte, and the cargo bay (dock) is the box between its two corner cells (the second corner is exclusive). Our
content keeps these as `at: [x, y]` on each slot and `cargo_area: [x1, y1, x2, y2]` on the hull. They change only how
the designer looks, never a rule.

### Mystery Trader items

Some parts and one hull need an item from the Mystery Trader (`Part_NeedsMysteryTraderItem@10d0:4af6`): Enigma
Pulsar, Langston Shell, Mega Poly Shell, Multi Contained Munition, Anti-Matter Torpedo, Hush-a-Boom, Alien Miner,
Multi Function Pod, Multi Cargo Pod, Jump Gate, Genesis Device and the Mini-Morph hull. Content marks them
`mystery_trader`; a player can use one only once it is in `trader_parts`, whatever the tech levels (S04
`available`, built 2026-10-05; how items are given is the Mystery Trader's spec).

## Algorithm: design totals

A design is a hull plus, per slot, one part type and a count. Totals are sums over the slots. All arithmetic is
integer.

1. **Mass** = hull mass + Σ count × part mass.
2. **Cost** = hull cost + Σ count × part cost, per mineral and for resources. Race traits can change part costs;
   that belongs to the traits (S06) and production (S09).
3. **Armor** = hull armor + Σ count × `armor`. For a race with the Regenerating Shields trait, each armor-category
   slot's contribution is halved by an integer shift (`(count × armor) >> 1`) before it is added. Armor from
   non-armor parts (Croby Sharmor, Langston Shell, Multi Cargo Pod) is not halved.
4. **Shields** = Σ count × `shield`. With Regenerating Shields: `shields + (shields × 2) / 5`, truncating. The
   total is capped at 65535.
5. **Fuel capacity** = hull fuel + Σ count × `fuel_capacity`.
6. **Cargo capacity** = hull cargo + Σ count × `cargo_capacity`.
7. **Initiative** = hull initiative + Σ count × `initiative` of battle computers. (How weapon initiative combines
   with it is S16.)
8. **Cloak units** = Σ count × `cloak`. The conversion to a cloaking percentage is S15.
9. **Mine sweep rate** = Σ count × power × r² over beam slots, where r is the beam's range, or 4 for gatling beams.
   Sapper beams don't sweep. Starbases add 1 to r.
10. **Mines laid per year**, per mine type: Σ count × that type's `mines_…` stat; doubled for the Mini Mine Layer and
    Super Mine Layer hulls (hull stat `mine_laying_pct` 200); capped at 100,000,000 (S11, S13).
11. **Mining rate** = Σ count × `mining_rate` over mining robots (the Orbital Adjuster has none), capped at 4,000.
12. **Fuel generation per year**: 50 per Anti-Matter Generator, plus 200 per ship with the Fuel Transport or
    Super-Fuel Xport hull (applied in S12/S19).

These design values combine part effects in non-additive ways and are specified by the subsystem specs, using the
per-part values from this spec: scanner and penetrating range (S15; the original uses floating point here), torpedo
accuracy from computers and jamming (S16), battle movement (S16), ram-scoop fuel (S12).

## Per-item effects

Effects the code adds by item number, beyond the record's own value. Each is per item, multiplied by the slot count.
Stat names are the ones our content uses.

| Part | Extra effects |
|---|---|
| Croby Sharmor (shield 3) | armor 65 |
| Shadow Shield (shield 4) | cloak 70 |
| Langston Shell (shield 6) | armor 65, cloak 20, jamming 5, scan_range 50 |
| Fielded Kelarium (armor 6) | shield 50 |
| Depleted Neutronium (armor 7) | cloak 50 |
| Mega Poly Shell (armor 9) | shield 100, cloak 40, jamming 20, scan_range 80 |
| Enigma Pulsar (engine 8) | cloak 20, battle_move_halves 1 |
| Chameleon Scanner (scanner 6) | cloak 40 |
| Multi Contained Munition (beam 18) | cloak 20, torpedo_accuracy 10, scan_range 150, mines_standard 40 |
| Alien Miner (mining robot 6) | cloak 60, jamming 30, battle_move_halves 1 |
| Orbital Adjuster (mining robot 7) | cloak 50 |
| Cloaking devices (electrical 0–3) | cloak = record value |
| Multi Function Pod (electrical 4) | cloak 60 (record value), jamming 10, battle_move 1 |
| Battle computers (electrical 5–7) | initiative 1 / 2 / 3 (item − 4), torpedo_accuracy = record value |
| Jammers (electrical 8–11) | jamming = record value |
| Energy and Flux Capacitor (electrical 12–13) | beam_damage_pct = record value |
| Anti-Matter Generator (electrical 16) | fuel_capacity 200, fuel_generation 50 |
| Cargo Pod, Super Cargo Pod (mechanical 2–3) | cargo_capacity 50 / 100 |
| Multi Cargo Pod (mechanical 4) | cargo_capacity 250, armor 50, cloak 20 |
| Fuel Tank, Super Fuel Tank (mechanical 5–6) | fuel_capacity 250 / 500 |
| Maneuvering Jet, Overthruster (mechanical 7–8) | battle_move 1 / 2 |
| Beam Deflector (mechanical 10) | beam_deflection 10 |

Units, to be fixed by the subsystem specs:

- `jamming`: percent removed from enemy torpedo accuracy per item. The original multiplies by
  `(100 − jamming) / 100` once per item.
- `battle_move`: whole steps added to the battle-movement sum. `battle_move_halves`: items that add half a step
  together; the original adds `(n + 1) / 2` for n such items.
- `cloak`: cloak units (S15 converts them to a percentage using ship mass).

Behavior groups by item number, named from the items. The rules are in S13, S16 and S17 and must be confirmed there:

- bombs 0–4 normal, 5–7 installation-only (LBU), 8 Hush-a-Boom, 9 retro, 10–14 smart;
- torpedoes 8–11 capital missiles;
- mechanical 0 colonization module, 1 orbital construction module, 9 jump gate;
- electrical 14 energy dampener, 15 tachyon detector;
- scanners 5 and 14 steal cargo from fleets; 14 also from planets.

## Disagreements with the Posey spreadsheet

The code wins (CLAUDE.md). These are recorded so the test oracles can be corrected.

| Item | Code | Posey |
|---|---|---|
| Depleted Neutronium | tech construction 10, electronics 3 | construction 10 only |
| Energy Dampener / Tachyon Detector | mass 2 / 1 | 1 / 2 (swapped) |
| Rhino, Possum, Pick Pocket, Chameleon, Dolphin, Gazelle, Cheetah, Elephant, Eagle Eye, Robber Baron, Peerless scanners | mass 5, 3, 15, 6, 4, 5, 4, 6, 3, 20, 4 | 2 for all |
| Jihad Missile | mass 35 | 25 |

All other costs, masses and tech levels of the 191 items Posey lists agree.

## Edge cases

- A starbase's "cargo" field is its dock limit; −1 means the dock builds any ship. Starbases have no fuel.
- Stargate limits use −1 for "any".
- **Design pictures** (cosmetic): each hull owns four consecutive pictures starting at its picture number (content
  `pictures`: ship hull i at 4i, except hulls 29–31 at 124, 120, 116; starbase hull i at 128 + 4i). A design's
  picture outside its hull's four becomes the hull's first picture plus the value's last two bits (the original
  does this when it loads a design, `DecodeDesignBlock@1068:0000`; so a starting starbase stored as 8 reads back
  as 136).
- The shield cap (65535) comes from the original's 16-bit totals; our engine keeps it as a rule constant (S25 limits
  policy). Armor totals use wide integers, so the Space Dock armor overflow (S25 B21) cannot happen.

## Worked examples

- **Scout with one Quick Jump 5 and one Bat Scanner:** mass 8 + 4 + 2 = 14; armor 20; fuel 50; initiative 1.
- **Regenerating Shields, armor:** a design with 4 × Strobnium (120) on a hull with armor 45: 45 + (4 × 120) >> 1 =
  45 + 240 = 285 (without the trait: 525).
- **Regenerating Shields, shields:** 5 × Bear Neutrino Barrier (100) = 500; 500 + (500 × 2) / 5 = 700.

## Mod hooks

- Content: `part` and `hull` definitions (`content/README.md`). Every effect above is a named stat, so mods can add
  parts with any mix of effects without code.
- Formulas (M6+): `design.mass`, `design.cost`, `design.armor`, `design.shields`, `design.fuel_capacity`,
  `design.cargo_capacity`, `design.initiative`, `design.cloak_units`, `design.sweep_rate`.
- Trait parameters (S06): the armor halving and shield bonus of Regenerating Shields.

## Open questions

1. **Penetrating scanner ranges** (Ferret, Dolphin, Elephant, Chameleon, Robber Baron, Peerless, and the planetary
   "X" scanners) are not in the record. They are computed in the floating-point part of `Design_ScannerRange`, which
   decompiled badly; needs a disassembly pass (S15).
2. Meaning of the engine code word (values 0–6) and the scanner code word (0–4).
3. Effects of the Energy Dampener, Tachyon Detector, capacitors and Beam Deflector in battle and scanning (S15/S16).
4. Hull flag bits 6–7 and the class byte (probably roles used by the AI and the designer).
5. **Part availability by race:** resolved in S06 ("Part availability by trait"); the content now has
   `required_traits` and `forbidden_traits`. Still open here: the hull-only parts (Settler's Delight on the
   Mini-Colony Ship, the Orbital Construction Module on the Colony Ship) as a design rule.
6. Mystery Trader parts (`Part_NeedsMysteryTraderItem`): which items need the trader (S18).

## Data tables

Generated from `content/core`, the same data the game loads. Tech: En energy, We weapons, Pr propulsion,
Co construction, El electronics, Bi biotech. Engine fuel lists warps 1–10 (warp 0 is always 0). GP = general
purpose slot (scanner, shield, armor, beam, torpedo, mine layer, electrical, mechanical).

#### Engine (kind 0x0001)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.engine.settler_s_delight` | Settler's Delight | – | 2 | 1/0/1/2 | fuel 0 0 0 0 0 0 140 275 480 576 | – |
| 1 | `part.engine.quick_jump_5` | Quick Jump 5 | – | 4 | 3/0/1/3 | fuel 0 25 100 100 100 180 500 800 900 1080 | – |
| 2 | `part.engine.fuel_mizer` | Fuel Mizer | Pr2 | 6 | 8/0/0/11 | fuel 0 0 0 0 35 120 175 235 360 420 | – |
| 3 | `part.engine.long_hump_6` | Long Hump 6 | Pr3 | 9 | 5/0/1/6 | fuel 0 20 60 100 100 105 450 750 900 1080 | – |
| 4 | `part.engine.daddy_long_legs_7` | Daddy Long Legs 7 | Pr5 | 13 | 11/0/3/12 | fuel 0 20 60 70 100 100 110 600 750 900 | – |
| 5 | `part.engine.alpha_drive_8` | Alpha Drive 8 | Pr7 | 17 | 16/0/3/28 | fuel 0 15 50 60 70 100 100 115 700 840 | – |
| 6 | `part.engine.trans_galactic_drive` | Trans-Galactic Drive | Pr9 | 25 | 20/20/9/50 | fuel 0 15 35 45 55 70 80 90 100 120 | – |
| 7 | `part.engine.interspace_10` | Interspace-10 | Pr11 | 25 | 18/25/10/60 | fuel 0 10 30 40 50 60 70 80 90 100 | – |
| 8 | `part.engine.enigma_pulsar` | Enigma Pulsar | En7 Pr13 Co5 El9 | 20 | 12/15/11/40 | cloak 20, battle_move_halves 1; fuel 0 0 0 0 0 65 75 85 95 105 | – |
| 9 | `part.engine.trans_star_10` | Trans-Star 10 | Pr23 | 5 | 3/0/3/10 | fuel 0 5 15 20 25 30 35 40 45 50 | – |
| 10 | `part.engine.radiating_hydro_ram_scoop` | Radiating Hydro-Ram Scoop | En2 Pr6 | 10 | 3/2/9/8 | fuel 0 0 0 0 0 0 165 375 600 720 | – |
| 11 | `part.engine.sub_galactic_fuel_scoop` | Sub-Galactic Fuel Scoop | En2 Pr8 | 20 | 4/4/7/12 | fuel 0 0 0 0 0 85 105 210 380 456 | – |
| 12 | `part.engine.trans_galactic_fuel_scoop` | Trans-Galactic Fuel Scoop | En3 Pr9 | 19 | 5/4/12/18 | fuel 0 0 0 0 0 0 88 100 145 174 | – |
| 13 | `part.engine.trans_galactic_super_scoop` | Trans-Galactic Super Scoop | En4 Pr12 | 18 | 6/4/16/24 | fuel 0 0 0 0 0 0 0 65 90 108 | – |
| 14 | `part.engine.trans_galactic_mizer_scoop` | Trans-Galactic Mizer Scoop | En4 Pr16 | 11 | 5/2/13/20 | fuel 0 0 0 0 0 0 0 0 70 84 | – |
| 15 | `part.engine.galaxy_scoop` | Galaxy Scoop | En5 Pr20 | 8 | 4/2/9/12 | fuel 0 0 0 0 0 0 0 0 0 60 | – |

#### Scanner (kind 0x0002)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.scanner.bat_scanner` | Bat Scanner | – | 2 | 1/0/1/1 | scan_range 0 | – |
| 1 | `part.scanner.rhino_scanner` | Rhino Scanner | El1 | 5 | 3/0/2/3 | scan_range 50 | – |
| 2 | `part.scanner.mole_scanner` | Mole Scanner | El4 | 2 | 2/0/2/9 | scan_range 100 | – |
| 3 | `part.scanner.dna_scanner` | DNA Scanner | Pr3 Bi6 | 2 | 1/1/1/5 | scan_range 125 | – |
| 4 | `part.scanner.possum_scanner` | Possum Scanner | El5 | 3 | 3/0/3/18 | scan_range 150 | – |
| 5 | `part.scanner.pick_pocket_scanner` | Pick Pocket Scanner | En4 El4 Bi4 | 15 | 8/10/6/35 | scan_range 80 | steals_from_fleets |
| 6 | `part.scanner.chameleon_scanner` | Chameleon Scanner | En3 El6 | 6 | 4/6/4/25 | scan_range 160, cloak 40 | – |
| 7 | `part.scanner.ferret_scanner` | Ferret Scanner | En3 El7 Bi2 | 2 | 2/0/8/36 | scan_range 185 | – |
| 8 | `part.scanner.dolphin_scanner` | Dolphin Scanner | En5 El10 Bi4 | 4 | 5/5/10/40 | scan_range 220 | – |
| 9 | `part.scanner.gazelle_scanner` | Gazelle Scanner | En4 El8 | 5 | 4/0/5/24 | scan_range 225 | – |
| 10 | `part.scanner.rna_scanner` | RNA Scanner | Pr5 Bi10 | 2 | 1/1/2/20 | scan_range 230 | – |
| 11 | `part.scanner.cheetah_scanner` | Cheetah Scanner | En5 El11 | 4 | 3/1/13/50 | scan_range 275 | – |
| 12 | `part.scanner.elephant_scanner` | Elephant Scanner | En6 El16 Bi7 | 6 | 8/5/14/70 | scan_range 300 | – |
| 13 | `part.scanner.eagle_eye_scanner` | Eagle Eye Scanner | En6 El14 | 3 | 3/2/21/64 | scan_range 335 | – |
| 14 | `part.scanner.robber_baron_scanner` | Robber Baron Scanner | En10 El15 Bi10 | 20 | 10/10/10/90 | scan_range 220 | steals_from_fleets, steals_from_planets |
| 15 | `part.scanner.peerless_scanner` | Peerless Scanner | En7 El24 | 4 | 3/2/30/90 | scan_range 500 | – |

#### Shield (kind 0x0004)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.shield.mole_skin_shield` | Mole-skin Shield | – | 1 | 1/0/1/4 | shield 25 | – |
| 1 | `part.shield.cow_hide_shield` | Cow-hide Shield | En3 | 1 | 2/0/2/5 | shield 40 | – |
| 2 | `part.shield.wolverine_diffuse_shield` | Wolverine Diffuse Shield | En6 | 1 | 3/0/3/6 | shield 60 | – |
| 3 | `part.shield.croby_sharmor` | Croby Sharmor | En7 Co4 | 10 | 7/0/4/15 | shield 60, armor 65 | – |
| 4 | `part.shield.shadow_shield` | Shadow Shield | En7 El3 | 2 | 3/0/3/7 | shield 75, cloak 70 | – |
| 5 | `part.shield.bear_neutrino_barrier` | Bear Neutrino Barrier | En10 | 1 | 4/0/4/8 | shield 100 | – |
| 6 | `part.shield.langston_shell` | Langston Shell | En12 Pr9 El9 | 10 | 10/2/6/20 | shield 125, armor 65, cloak 20, jamming 5, scan_range 50 | – |
| 7 | `part.shield.gorilla_delagator` | Gorilla Delagator | En14 | 1 | 5/0/6/11 | shield 175 | – |
| 8 | `part.shield.elephant_hide_fortress` | Elephant Hide Fortress | En18 | 1 | 8/0/10/15 | shield 300 | – |
| 9 | `part.shield.complete_phase_shield` | Complete Phase Shield | En22 | 1 | 12/0/15/20 | shield 500 | – |

#### Armor (kind 0x0008)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.armor.tritanium` | Tritanium | – | 60 | 5/0/0/10 | armor 50 | – |
| 1 | `part.armor.crobmnium` | Crobmnium | Co3 | 56 | 6/0/0/13 | armor 75 | – |
| 2 | `part.armor.carbonic_armor` | Carbonic Armor | Bi4 | 25 | 0/0/5/15 | armor 100 | – |
| 3 | `part.armor.strobnium` | Strobnium | Co6 | 54 | 8/0/0/18 | armor 120 | – |
| 4 | `part.armor.organic_armor` | Organic Armor | Bi7 | 15 | 0/0/6/20 | armor 175 | – |
| 5 | `part.armor.kelarium` | Kelarium | Co9 | 50 | 9/1/0/25 | armor 180 | – |
| 6 | `part.armor.fielded_kelarium` | Fielded Kelarium | En4 Co10 | 50 | 10/0/2/28 | armor 175, shield 50 | – |
| 7 | `part.armor.depleted_neutronium` | Depleted Neutronium | Co10 El3 | 50 | 10/0/2/28 | armor 200, cloak 50 | – |
| 8 | `part.armor.neutronium` | Neutronium | Co12 | 45 | 11/2/1/30 | armor 275 | – |
| 9 | `part.armor.mega_poly_shell` | Mega Poly Shell | En14 Co14 El14 Bi6 | 20 | 18/6/6/65 | armor 400, shield 100, cloak 40, jamming 20, scan_range 80 | – |
| 10 | `part.armor.valanium` | Valanium | Co16 | 40 | 15/0/0/50 | armor 500 | – |
| 11 | `part.armor.superlatanium` | Superlatanium | Co24 | 30 | 25/0/0/100 | armor 1500 | – |

#### Beam (kind 0x0010)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.beam.laser` | Laser | – | 1 | 0/6/0/5 | range 1, power 10, initiative 9 | – |
| 1 | `part.beam.x_ray_laser` | X-Ray Laser | We3 | 1 | 0/6/0/6 | range 1, power 16, initiative 9 | – |
| 2 | `part.beam.mini_gun` | Mini Gun | We5 | 3 | 0/16/0/10 | range 2, power 13, initiative 12 | gatling |
| 3 | `part.beam.yakimora_light_phaser` | Yakimora Light Phaser | We6 | 1 | 0/8/0/7 | range 1, power 26, initiative 9 | – |
| 4 | `part.beam.blackjack` | Blackjack | We7 | 10 | 0/16/0/7 | range 0, power 90, initiative 10 | – |
| 5 | `part.beam.phaser_bazooka` | Phaser Bazooka | We8 | 2 | 0/8/0/11 | range 2, power 26, initiative 7 | – |
| 6 | `part.beam.pulsed_sapper` | Pulsed Sapper | En5 We9 | 1 | 0/0/4/12 | range 3, power 82, initiative 14 | sapper |
| 7 | `part.beam.colloidal_phaser` | Colloidal Phaser | We10 | 2 | 0/14/0/18 | range 3, power 26, initiative 5 | – |
| 8 | `part.beam.gatling_gun` | Gatling Gun | We11 | 3 | 0/20/0/13 | range 2, power 31, initiative 12 | gatling |
| 9 | `part.beam.mini_blaster` | Mini Blaster | We12 | 1 | 0/10/0/9 | range 1, power 66, initiative 9 | – |
| 10 | `part.beam.bludgeon` | Bludgeon | We13 | 10 | 0/22/0/9 | range 0, power 231, initiative 10 | – |
| 11 | `part.beam.mark_iv_blaster` | Mark IV Blaster | We14 | 2 | 0/12/0/15 | range 2, power 66, initiative 7 | – |
| 12 | `part.beam.phased_sapper` | Phased Sapper | En8 We15 | 1 | 0/0/6/16 | range 3, power 211, initiative 14 | sapper |
| 13 | `part.beam.heavy_blaster` | Heavy Blaster | We16 | 2 | 0/20/0/25 | range 3, power 66, initiative 5 | – |
| 14 | `part.beam.gatling_neutrino_cannon` | Gatling Neutrino Cannon | We17 | 3 | 0/28/0/17 | range 2, power 80, initiative 13 | gatling |
| 15 | `part.beam.myopic_disruptor` | Myopic Disruptor | We18 | 1 | 0/14/0/12 | range 1, power 169, initiative 9 | – |
| 16 | `part.beam.blunderbuss` | Blunderbuss | We19 | 10 | 0/30/0/13 | range 0, power 592, initiative 11 | – |
| 17 | `part.beam.disruptor` | Disruptor | We20 | 2 | 0/16/0/20 | range 2, power 169, initiative 8 | – |
| 18 | `part.beam.multi_contained_munition` | Multi Contained Munition | En21 We21 El16 Bi12 | 8 | 6/40/6/40 | range 3, power 140, initiative 6, cloak 20, torpedo_accuracy 10, scan_range 150, mines_standard 40 | – |
| 19 | `part.beam.syncro_sapper` | Syncro Sapper | En11 We21 | 1 | 0/0/8/21 | range 3, power 541, initiative 14 | sapper |
| 20 | `part.beam.mega_disruptor` | Mega Disruptor | We22 | 2 | 0/30/0/33 | range 3, power 169, initiative 6 | – |
| 21 | `part.beam.big_mutha_cannon` | Big Mutha Cannon | We23 | 3 | 0/36/0/23 | range 2, power 204, initiative 13 | gatling |
| 22 | `part.beam.streaming_pulverizer` | Streaming Pulverizer | We24 | 1 | 0/20/0/16 | range 1, power 433, initiative 9 | – |
| 23 | `part.beam.anti_matter_pulverizer` | Anti-Matter Pulverizer | We26 | 2 | 0/22/0/27 | range 2, power 433, initiative 8 | – |

#### Torpedo (kind 0x0020)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.torpedo.alpha_torpedo` | Alpha Torpedo | – | 25 | 9/3/3/5 | range 4, power 5, initiative 0, accuracy 35 | – |
| 1 | `part.torpedo.beta_torpedo` | Beta Torpedo | We5 Pr1 | 25 | 18/6/4/6 | range 4, power 12, initiative 1, accuracy 45 | – |
| 2 | `part.torpedo.delta_torpedo` | Delta Torpedo | We10 Pr2 | 25 | 22/8/5/8 | range 4, power 26, initiative 1, accuracy 60 | – |
| 3 | `part.torpedo.epsilon_torpedo` | Epsilon Torpedo | We14 Pr3 | 25 | 30/10/6/10 | range 5, power 48, initiative 2, accuracy 65 | – |
| 4 | `part.torpedo.rho_torpedo` | Rho Torpedo | We18 Pr4 | 25 | 34/12/8/12 | range 5, power 90, initiative 2, accuracy 75 | – |
| 5 | `part.torpedo.upsilon_torpedo` | Upsilon Torpedo | We22 Pr5 | 25 | 40/14/9/15 | range 5, power 169, initiative 3, accuracy 75 | – |
| 6 | `part.torpedo.omega_torpedo` | Omega Torpedo | We26 Pr6 | 25 | 52/18/12/18 | range 5, power 316, initiative 4, accuracy 80 | – |
| 7 | `part.torpedo.anti_matter_torpedo` | Anti Matter Torpedo | We11 Pr12 Bi21 | 8 | 3/8/1/50 | range 6, power 60, initiative 0, accuracy 85 | – |
| 8 | `part.torpedo.jihad_missile` | Jihad Missile | We12 Pr6 | 35 | 37/13/9/13 | range 5, power 85, initiative 0, accuracy 20 | capital_missile |
| 9 | `part.torpedo.juggernaut_missile` | Juggernaut Missile | We16 Pr8 | 35 | 48/16/11/16 | range 5, power 150, initiative 1, accuracy 20 | capital_missile |
| 10 | `part.torpedo.doomsday_missile` | Doomsday Missile | We20 Pr10 | 35 | 60/20/13/20 | range 6, power 280, initiative 2, accuracy 25 | capital_missile |
| 11 | `part.torpedo.armageddon_missile` | Armageddon Missile | We24 Pr10 | 35 | 67/23/16/24 | range 6, power 525, initiative 3, accuracy 30 | capital_missile |

#### Bomb (kind 0x0040)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.bomb.lady_finger_bomb` | Lady Finger Bomb | We2 | 40 | 1/20/0/5 | kill_rate 6, installations 2 | normal |
| 1 | `part.bomb.black_cat_bomb` | Black Cat Bomb | We5 | 45 | 1/22/0/7 | kill_rate 9, installations 4 | normal |
| 2 | `part.bomb.m_70_bomb` | M-70 Bomb | We8 | 50 | 1/24/0/9 | kill_rate 12, installations 6 | normal |
| 3 | `part.bomb.m_80_bomb` | M-80 Bomb | We11 | 55 | 1/25/0/12 | kill_rate 17, installations 7 | normal |
| 4 | `part.bomb.cherry_bomb` | Cherry Bomb | We14 | 52 | 1/25/0/11 | kill_rate 25, installations 10 | normal |
| 5 | `part.bomb.lbu_17_bomb` | LBU-17 Bomb | We5 El8 | 30 | 1/15/15/7 | kill_rate 2, installations 16 | lbu |
| 6 | `part.bomb.lbu_32_bomb` | LBU-32 Bomb | We10 El10 | 35 | 1/24/15/10 | kill_rate 3, installations 28 | lbu |
| 7 | `part.bomb.lbu_74_bomb` | LBU-74 Bomb | We15 El12 | 45 | 1/33/12/14 | kill_rate 4, installations 45 | lbu |
| 8 | `part.bomb.hush_a_boom` | Hush-a-Boom | We12 El12 Bi12 | 5 | 1/5/0/5 | kill_rate 30, installations 2 | normal |
| 9 | `part.bomb.retro_bomb` | Retro Bomb | We10 Bi12 | 45 | 15/15/10/50 | kill_rate 0, installations 0 | retro |
| 10 | `part.bomb.smart_bomb` | Smart Bomb | We5 Bi7 | 50 | 1/22/0/27 | kill_rate 13, installations 0 | smart |
| 11 | `part.bomb.neutron_bomb` | Neutron Bomb | We10 Bi10 | 57 | 1/30/0/30 | kill_rate 22, installations 0 | smart |
| 12 | `part.bomb.enriched_neutron_bomb` | Enriched Neutron Bomb | We15 Bi12 | 64 | 1/36/0/25 | kill_rate 35, installations 0 | smart |
| 13 | `part.bomb.peerless_bomb` | Peerless Bomb | We22 Bi15 | 55 | 1/33/0/32 | kill_rate 50, installations 0 | smart |
| 14 | `part.bomb.annihilator_bomb` | Annihilator Bomb | We26 Bi17 | 50 | 1/30/0/28 | kill_rate 70, installations 0 | smart |

#### Mining robot (kind 0x0080)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.mining_robot.robo_midget_miner` | Robo-Midget Miner | – | 80 | 14/0/4/50 | mining_rate 5 | – |
| 1 | `part.mining_robot.robo_mini_miner` | Robo-Mini-Miner | Co2 El1 | 240 | 30/0/7/100 | mining_rate 4 | – |
| 2 | `part.mining_robot.robo_miner` | Robo-Miner | Co4 El2 | 240 | 30/0/7/100 | mining_rate 12 | – |
| 3 | `part.mining_robot.robo_maxi_miner` | Robo-Maxi-Miner | Co7 El4 | 240 | 30/0/7/100 | mining_rate 18 | – |
| 4 | `part.mining_robot.robo_super_miner` | Robo-Super-Miner | Co12 El6 | 240 | 30/0/7/100 | mining_rate 27 | – |
| 5 | `part.mining_robot.robo_ultra_miner` | Robo-Ultra-Miner | Co15 El8 | 80 | 14/0/4/50 | mining_rate 25 | – |
| 6 | `part.mining_robot.alien_miner` | Alien Miner | En5 Co10 El5 Bi5 | 20 | 8/0/2/20 | mining_rate 10, cloak 60, jamming 30, battle_move_halves 1 | – |
| 7 | `part.mining_robot.orbital_adjuster` | Orbital Adjuster | Bi6 | 80 | 25/25/25/50 | mining_rate 0, cloak 50 | orbital_adjuster |

#### Mine layer (kind 0x0100)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.mine_layer.mine_dispenser_40` | Mine Dispenser 40 | – | 25 | 2/10/8/45 | mines_standard 40 | – |
| 1 | `part.mine_layer.mine_dispenser_50` | Mine Dispenser 50 | En2 Bi4 | 30 | 2/12/10/55 | mines_standard 50 | – |
| 2 | `part.mine_layer.mine_dispenser_80` | Mine Dispenser 80 | En3 Bi7 | 30 | 2/14/10/65 | mines_standard 80 | – |
| 3 | `part.mine_layer.mine_dispenser_130` | Mine Dispenser 130 | En6 Bi12 | 30 | 2/18/10/80 | mines_standard 130 | – |
| 4 | `part.mine_layer.heavy_dispenser_50` | Heavy Dispenser 50 | En5 Bi3 | 10 | 2/20/5/50 | mines_heavy 50 | – |
| 5 | `part.mine_layer.heavy_dispenser_110` | Heavy Dispenser 110 | En9 Bi5 | 15 | 2/30/5/70 | mines_heavy 110 | – |
| 6 | `part.mine_layer.heavy_dispenser_200` | Heavy Dispenser 200 | En14 Bi7 | 20 | 2/45/5/90 | mines_heavy 200 | – |
| 7 | `part.mine_layer.speed_trap_20` | Speed Trap 20 | Pr2 Bi2 | 100 | 30/0/12/60 | mines_speed_bump 20 | – |
| 8 | `part.mine_layer.speed_trap_30` | Speed Trap 30 | Pr3 Bi6 | 135 | 32/0/14/72 | mines_speed_bump 30 | – |
| 9 | `part.mine_layer.speed_trap_50` | Speed Trap 50 | Pr5 Bi11 | 140 | 40/0/15/80 | mines_speed_bump 50 | – |

#### Orbital (kind 0x0200)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.orbital.stargate_100_250` | Stargate 100/250 | Pr5 Co5 | 0 | 100/40/40/400 | gate_mass 100, gate_range 250 | stargate |
| 1 | `part.orbital.stargate_any_300` | Stargate any/300 | Pr6 Co10 | 0 | 100/40/40/500 | gate_mass -1, gate_range 300 | stargate |
| 2 | `part.orbital.stargate_150_600` | Stargate 150/600 | Pr11 Co7 | 0 | 100/40/40/1000 | gate_mass 150, gate_range 600 | stargate |
| 3 | `part.orbital.stargate_300_500` | Stargate 300/500 | Pr9 Co13 | 0 | 100/40/40/1200 | gate_mass 300, gate_range 500 | stargate |
| 4 | `part.orbital.stargate_100_any` | Stargate 100/any | Pr16 Co12 | 0 | 100/40/40/1400 | gate_mass 100, gate_range -1 | stargate |
| 5 | `part.orbital.stargate_any_800` | Stargate any/800 | Pr12 Co18 | 0 | 100/40/40/1400 | gate_mass -1, gate_range 800 | stargate |
| 6 | `part.orbital.stargate_any_any` | Stargate any/any | Pr19 Co24 | 0 | 100/40/40/1600 | gate_mass -1, gate_range -1 | stargate |
| 7 | `part.orbital.mass_driver_5` | Mass Driver 5 | En4 | 0 | 48/40/40/140 | driver_warp 5 | mass_driver |
| 8 | `part.orbital.mass_driver_6` | Mass Driver 6 | En7 | 0 | 48/40/40/288 | driver_warp 6 | mass_driver |
| 9 | `part.orbital.mass_driver_7` | Mass Driver 7 | En9 | 0 | 200/200/200/1024 | driver_warp 7 | mass_driver |
| 10 | `part.orbital.super_driver_8` | Super Driver 8 | En11 | 0 | 48/40/40/512 | driver_warp 8 | mass_driver |
| 11 | `part.orbital.super_driver_9` | Super Driver 9 | En13 | 0 | 48/40/40/648 | driver_warp 9 | mass_driver |
| 12 | `part.orbital.ultra_driver_10` | Ultra Driver 10 | En15 | 0 | 200/200/200/1936 | driver_warp 10 | mass_driver |
| 13 | `part.orbital.ultra_driver_11` | Ultra Driver 11 | En17 | 0 | 48/40/40/968 | driver_warp 11 | mass_driver |
| 14 | `part.orbital.ultra_driver_12` | Ultra Driver 12 | En20 | 0 | 48/40/40/1152 | driver_warp 12 | mass_driver |
| 15 | `part.orbital.ultra_driver_13` | Ultra Driver 13 | En24 | 0 | 48/40/40/1352 | driver_warp 13 | mass_driver |

#### Electrical (kind 0x0800)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.electrical.transport_cloaking` | Transport Cloaking | – | 1 | 2/0/2/3 | cloak 300 | – |
| 1 | `part.electrical.stealth_cloak` | Stealth Cloak | En2 El5 | 2 | 2/0/2/5 | cloak 70 | – |
| 2 | `part.electrical.super_stealth_cloak` | Super-Stealth Cloak | En4 El10 | 3 | 8/0/8/15 | cloak 140 | – |
| 3 | `part.electrical.ultra_stealth_cloak` | Ultra-Stealth Cloak | En10 El12 | 5 | 10/0/10/25 | cloak 540 | – |
| 4 | `part.electrical.multi_function_pod` | Multi Function Pod | En11 Pr11 El11 | 2 | 5/0/5/15 | cloak 60, jamming 10, battle_move 1 | – |
| 5 | `part.electrical.battle_computer` | Battle Computer | – | 1 | 0/0/15/6 | initiative 1, torpedo_accuracy 20 | – |
| 6 | `part.electrical.battle_super_computer` | Battle Super Computer | En5 El11 | 1 | 0/0/25/14 | initiative 2, torpedo_accuracy 30 | – |
| 7 | `part.electrical.battle_nexus` | Battle Nexus | En10 El19 | 1 | 0/0/30/15 | initiative 3, torpedo_accuracy 50 | – |
| 8 | `part.electrical.jammer_10` | Jammer 10 | En2 El6 | 1 | 0/0/2/6 | jamming 10 | – |
| 9 | `part.electrical.jammer_20` | Jammer 20 | En4 El10 | 1 | 1/0/5/20 | jamming 20 | – |
| 10 | `part.electrical.jammer_30` | Jammer 30 | En8 El16 | 1 | 1/0/6/20 | jamming 30 | – |
| 11 | `part.electrical.jammer_50` | Jammer 50 | En16 El22 | 1 | 2/0/7/20 | jamming 50 | – |
| 12 | `part.electrical.energy_capacitor` | Energy Capacitor | En7 El4 | 1 | 0/0/8/5 | beam_damage_pct 10 | capacitor |
| 13 | `part.electrical.flux_capacitor` | Flux Capacitor | En14 El8 | 1 | 0/0/8/5 | beam_damage_pct 20 | capacitor |
| 14 | `part.electrical.energy_dampener` | Energy Dampener | En14 Pr8 | 2 | 5/10/0/50 | – | energy_dampener |
| 15 | `part.electrical.tachyon_detector` | Tachyon Detector | En8 El14 | 1 | 1/5/0/70 | – | tachyon_detector |
| 16 | `part.electrical.anti_matter_generator` | Anti-matter Generator | We12 Bi7 | 10 | 8/3/3/10 | fuel_capacity 200, fuel_generation 50 | antimatter_generator |

#### Mechanical (kind 0x1000)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.mechanical.colonization_module` | Colonization Module | – | 32 | 12/10/10/10 | – | colonizer |
| 1 | `part.mechanical.orbital_construction_module` | Orbital Construction Module | – | 50 | 20/15/15/20 | – | colonizer, orbital_construction |
| 2 | `part.mechanical.cargo_pod` | Cargo Pod | Co3 | 5 | 5/0/2/10 | cargo_capacity 50 | – |
| 3 | `part.mechanical.super_cargo_pod` | Super Cargo Pod | En3 Co9 | 7 | 8/0/2/15 | cargo_capacity 100 | – |
| 4 | `part.mechanical.multi_cargo_pod` | Multi Cargo Pod | En5 Co11 El5 | 9 | 12/0/3/25 | cargo_capacity 250, armor 50, cloak 20 | – |
| 5 | `part.mechanical.fuel_tank` | Fuel Tank | – | 3 | 6/0/0/4 | fuel_capacity 250 | – |
| 6 | `part.mechanical.super_fuel_tank` | Super Fuel Tank | En6 Pr4 Co14 | 8 | 8/0/0/8 | fuel_capacity 500 | – |
| 7 | `part.mechanical.maneuvering_jet` | Maneuvering Jet | En2 Pr3 | 5 | 5/0/5/10 | battle_move 1 | – |
| 8 | `part.mechanical.overthruster` | Overthruster | En5 Pr12 | 5 | 10/0/8/20 | battle_move 2 | – |
| 9 | `part.mechanical.jump_gate` | Jump Gate | En16 Pr20 Co20 El16 | 10 | 0/0/50/40 | – | jump_gate |
| 10 | `part.mechanical.beam_deflector` | Beam Deflector | En6 We6 Co6 El6 | 1 | 0/0/10/8 | beam_deflection 10 | – |

#### Planetary (kind 0x0400)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.planetary.viewer_50` | Viewer 50 | – | 0 | 10/10/70/100 | scan_range 50 | – |
| 1 | `part.planetary.viewer_90` | Viewer 90 | El1 | 0 | 10/10/70/100 | scan_range 90 | – |
| 2 | `part.planetary.scoper_150` | Scoper 150 | El3 | 0 | 10/10/70/100 | scan_range 150 | – |
| 3 | `part.planetary.scoper_220` | Scoper 220 | El6 | 0 | 10/10/70/100 | scan_range 220 | – |
| 4 | `part.planetary.scoper_280` | Scoper 280 | El8 | 0 | 10/10/70/100 | scan_range 280 | – |
| 5 | `part.planetary.snooper_320x` | Snooper 320X | En3 El10 Bi3 | 0 | 10/10/70/100 | scan_range 320 | penetrating |
| 6 | `part.planetary.snooper_400x` | Snooper 400X | En4 El13 Bi6 | 0 | 10/10/70/100 | scan_range 400 | penetrating |
| 7 | `part.planetary.snooper_500x` | Snooper 500X | En5 El16 Bi7 | 0 | 10/10/70/100 | scan_range 500 | penetrating |
| 8 | `part.planetary.snooper_620x` | Snooper 620X | En7 El23 Bi9 | 0 | 10/10/70/100 | scan_range 620 | penetrating |
| 9 | `part.planetary.sdi` | SDI | – | 0 | 5/5/5/15 | defense 10 | – |
| 10 | `part.planetary.missile_battery` | Missile Battery | En5 | 0 | 5/5/5/15 | defense 20 | – |
| 11 | `part.planetary.laser_battery` | Laser Battery | En10 | 0 | 5/5/5/15 | defense 24 | – |
| 12 | `part.planetary.planetary_shield` | Planetary Shield | En16 | 0 | 5/5/5/15 | defense 30 | – |
| 13 | `part.planetary.neutron_shield` | Neutron Shield | En23 | 0 | 5/5/5/15 | defense 38 | – |
| 14 | `part.planetary.genesis_device` | Genesis Device | En20 We10 Pr10 Co20 El10 Bi20 | 0 | 0/0/0/5000 | – | genesis_device |

#### Terraform (kind 0x2000)

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Stats | Tags |
|---|---|---|---|---|---|---|---|
| 0 | `part.terraform.total_terraform_3` | Total Terraform ±3 | – | 0 | 0/0/0/70 | terraform 3 | terraform_total |
| 1 | `part.terraform.total_terraform_5` | Total Terraform ±5 | Bi3 | 0 | 0/0/0/70 | terraform 5 | terraform_total |
| 2 | `part.terraform.total_terraform_7` | Total Terraform ±7 | Bi6 | 0 | 0/0/0/70 | terraform 7 | terraform_total |
| 3 | `part.terraform.total_terraform_10` | Total Terraform ±10 | Bi9 | 0 | 0/0/0/70 | terraform 10 | terraform_total |
| 4 | `part.terraform.total_terraform_15` | Total Terraform ±15 | Bi13 | 0 | 0/0/0/70 | terraform 15 | terraform_total |
| 5 | `part.terraform.total_terraform_20` | Total Terraform ±20 | Bi17 | 0 | 0/0/0/70 | terraform 20 | terraform_total |
| 6 | `part.terraform.total_terraform_25` | Total Terraform ±25 | Bi22 | 0 | 0/0/0/70 | terraform 25 | terraform_total |
| 7 | `part.terraform.total_terraform_30` | Total Terraform ±30 | Bi25 | 0 | 0/0/0/70 | terraform 30 | terraform_total |
| 8 | `part.terraform.gravity_terraform_3` | Gravity Terraform ±3 | Pr1 Bi1 | 0 | 0/0/0/100 | terraform 3 | terraform_gravity |
| 9 | `part.terraform.gravity_terraform_7` | Gravity Terraform ±7 | Pr5 Bi2 | 0 | 0/0/0/100 | terraform 7 | terraform_gravity |
| 10 | `part.terraform.gravity_terraform_11` | Gravity Terraform ±11 | Pr10 Bi3 | 0 | 0/0/0/100 | terraform 11 | terraform_gravity |
| 11 | `part.terraform.gravity_terraform_15` | Gravity Terraform ±15 | Pr16 Bi4 | 0 | 0/0/0/100 | terraform 15 | terraform_gravity |
| 12 | `part.terraform.temp_terraform_3` | Temp Terraform ±3 | En1 Bi1 | 0 | 0/0/0/100 | terraform 3 | terraform_temperature |
| 13 | `part.terraform.temp_terraform_7` | Temp Terraform ±7 | En5 Bi2 | 0 | 0/0/0/100 | terraform 7 | terraform_temperature |
| 14 | `part.terraform.temp_terraform_11` | Temp Terraform ±11 | En10 Bi3 | 0 | 0/0/0/100 | terraform 11 | terraform_temperature |
| 15 | `part.terraform.temp_terraform_15` | Temp Terraform ±15 | En16 Bi4 | 0 | 0/0/0/100 | terraform 15 | terraform_temperature |
| 16 | `part.terraform.radiation_terraform_3` | Radiation Terraform ±3 | We1 Bi1 | 0 | 0/0/0/100 | terraform 3 | terraform_radiation |
| 17 | `part.terraform.radiation_terraform_7` | Radiation Terraform ±7 | We5 Bi2 | 0 | 0/0/0/100 | terraform 7 | terraform_radiation |
| 18 | `part.terraform.radiation_terraform_11` | Radiation Terraform ±11 | We10 Bi3 | 0 | 0/0/0/100 | terraform 11 | terraform_radiation |
| 19 | `part.terraform.radiation_terraform_15` | Radiation Terraform ±15 | We16 Bi4 | 0 | 0/0/0/100 | terraform 15 | terraform_radiation |

#### Hulls

| # | Id | Name | Tech | Mass | Fe/Bo/Ge/Res | Armor | Fuel | Cargo/Dock | Init | Slots (accepts × capacity) |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | `hull.small_freighter` | Small Freighter | – | 25 | 12/0/17/20 | 25 | 130 | 70 | 0 | Eng×1, Scan/Elec/Mech×1, Sh/Ar×1 |
| 1 | `hull.medium_freighter` | Medium Freighter | Co3 | 60 | 20/0/19/40 | 50 | 450 | 210 | 0 | Eng×1, Scan/Elec/Mech×1, Sh/Ar×1 |
| 2 | `hull.large_freighter` | Large Freighter | Co8 | 125 | 35/0/21/100 | 150 | 2600 | 1200 | 0 | Eng×2, Scan/Elec/Mech×2, Sh/Ar×2 |
| 3 | `hull.super_freighter` | Super Freighter | Co13 | 175 | 45/0/21/125 | 400 | 8000 | 3000 | 0 | Eng×3, Scan/Elec/Mech×3, Sh/Ar×5, Elec×2 |
| 4 | `hull.scout` | Scout | – | 8 | 4/2/4/10 | 20 | 50 | 0 | 1 | Eng×1, Scan×1, GP×1 |
| 5 | `hull.frigate` | Frigate | Co6 | 8 | 4/2/4/12 | 45 | 125 | 0 | 4 | Eng×1, Scan×2, GP×3, Sh/Ar×2 |
| 6 | `hull.destroyer` | Destroyer | Co3 | 30 | 15/3/5/35 | 200 | 280 | 0 | 3 | Eng×1, Beam/Torp×1, Beam/Torp×1, GP×1, Ar×2, Mech×1, Elec×1 |
| 7 | `hull.cruiser` | Cruiser | Co9 | 90 | 40/5/8/85 | 700 | 600 | 0 | 5 | Eng×2, Sh/Elec/Mech×1, Sh/Elec/Mech×1, Beam/Torp×2, Beam/Torp×2, GP×2, Sh/Ar×2 |
| 8 | `hull.battle_cruiser` | Battle Cruiser | Co10 | 120 | 55/8/12/120 | 1000 | 1400 | 0 | 5 | Eng×2, Sh/Elec/Mech×2, Sh/Elec/Mech×2, Beam/Torp×3, Beam/Torp×3, GP×3, Sh/Ar×4 |
| 9 | `hull.battleship` | Battleship | Co13 | 222 | 120/25/20/225 | 2000 | 2800 | 0 | 10 | Eng×4, Scan/Elec/Mech×1, Sh×8, Beam/Torp×6, Beam/Torp×6, Beam/Torp×2, Beam/Torp×2, Beam/Torp×4, Ar×6, Elec×3, Elec×3 |
| 10 | `hull.dreadnought` | Dreadnought | Co16 | 250 | 140/30/25/275 | 4500 | 4500 | 0 | 10 | Eng×5, Sh/Ar×4, Sh/Ar×4, Beam/Torp×6, Beam/Torp×6, Elec×4, Elec×4, Beam/Torp×8, Beam/Torp×8, Ar×8, Sh/Beam/Torp×5, Sh/Beam/Torp×5, GP×2 |
| 11 | `hull.privateer` | Privateer | Co4 | 65 | 50/3/2/50 | 150 | 650 | 250 | 3 | Eng×1, Sh/Ar×2, Scan/Elec/Mech×1, GP×1, GP×1 |
| 12 | `hull.rogue` | Rogue | Co8 | 75 | 80/5/5/60 | 450 | 2250 | 500 | 4 | Eng×2, Sh/Ar×3, Lay/Elec/Mech×2, Scan×1, GP×2, GP×2, Lay/Elec/Mech×2, Elec×1, Elec×1 |
| 13 | `hull.galleon` | Galleon | Co11 | 125 | 70/5/5/105 | 900 | 2500 | 1000 | 4 | Eng×4, Sh/Ar×2, Sh/Ar×2, GP×3, GP×3, Lay/Elec/Mech×2, Elec/Mech×2, Scan×2 |
| 14 | `hull.mini_colony_ship` | Mini-Colony Ship | – | 8 | 2/0/2/3 | 10 | 150 | 10 | 0 | Eng×1, Mech×1 |
| 15 | `hull.colony_ship` | Colony Ship | – | 20 | 10/0/15/20 | 20 | 200 | 25 | 0 | Eng×1, Mech×1 |
| 16 | `hull.mini_bomber` | Mini Bomber | Co1 | 28 | 20/5/10/35 | 50 | 120 | 0 | 0 | Eng×1, Bomb×2 |
| 17 | `hull.b_17_bomber` | B-17 Bomber | Co6 | 69 | 55/10/10/150 | 175 | 400 | 0 | 0 | Eng×2, Bomb×4, Bomb×4, Scan/Elec/Mech×1 |
| 18 | `hull.stealth_bomber` | Stealth Bomber | Co8 | 70 | 55/10/15/175 | 225 | 750 | 0 | 0 | Eng×2, Bomb×4, Bomb×4, Scan/Elec/Mech×1, Elec×3 |
| 19 | `hull.b_52_bomber` | B-52 Bomber | Co15 | 110 | 90/15/10/280 | 450 | 750 | 0 | 0 | Eng×3, Bomb×4, Bomb×4, Bomb×4, Bomb×4, Scan/Elec/Mech×2, Sh×2 |
| 20 | `hull.midget_miner` | Midget Miner | – | 10 | 10/0/3/20 | 100 | 210 | 0 | 0 | Eng×1, Mine×2 |
| 21 | `hull.mini_miner` | Mini-Miner | Co2 | 80 | 25/0/6/50 | 130 | 210 | 0 | 0 | Eng×1, Scan/Elec/Mech×1, Mine×1, Mine×1 |
| 22 | `hull.miner` | Miner | Co6 | 110 | 32/0/6/110 | 475 | 500 | 0 | 0 | Eng×2, Scan/Ar/Elec/Mech×2, Mine×2, Mine×1, Mine×2, Mine×1 |
| 23 | `hull.maxi_miner` | Maxi-Miner | Co11 | 110 | 32/0/6/140 | 1400 | 850 | 0 | 0 | Eng×3, Scan/Ar/Elec/Mech×2, Mine×4, Mine×1, Mine×4, Mine×1 |
| 24 | `hull.ultra_miner` | Ultra-Miner | Co14 | 100 | 30/0/6/130 | 1500 | 1300 | 0 | 0 | Eng×2, Scan/Ar/Elec/Mech×3, Mine×4, Mine×2, Mine×4, Mine×2 |
| 25 | `hull.fuel_transport` | Fuel Transport | Co4 | 12 | 10/0/5/50 | 5 | 750 | 0 | 0 | Eng×1, Sh×1 |
| 26 | `hull.super_fuel_xport` | Super-Fuel Xport | Co7 | 111 | 20/0/8/70 | 12 | 2250 | 0 | 0 | Eng×2, Sh×2, Scan×1 |
| 27 | `hull.mini_mine_layer` | Mini Mine Layer | – | 10 | 8/2/5/20 | 60 | 400 | 0 | 0 | Eng×1, Lay×2, Lay×2, Scan/Elec/Mech×1 |
| 28 | `hull.super_mine_layer` | Super Mine Layer | Co15 | 30 | 20/3/9/30 | 1200 | 2200 | 0 | 0 | Eng×3, Lay×8, Lay×8, Sh/Ar×3, Scan/Elec/Mech×3, Lay/Elec/Mech×3 |
| 29 | `hull.nubian` | Nubian | Co26 | 100 | 75/12/12/150 | 5000 | 5000 | 0 | 2 | Eng×3, GP×3, GP×3, GP×3, GP×3, GP×3, GP×3, GP×3, GP×3, GP×3, GP×3, GP×3, GP×3 |
| 30 | `hull.mini_morph` | Mini Morph | Co8 | 70 | 30/8/8/100 | 250 | 400 | 150 | 2 | Eng×2, GP×3, GP×1, GP×1, GP×1, GP×2, GP×2 |
| 31 | `hull.meta_morph` | Meta Morph | Co10 | 85 | 50/12/12/120 | 500 | 700 | 300 | 2 | Eng×3, GP×8, GP×2, GP×2, GP×1, GP×2, GP×2 |
| 32 | `hull.orbital_fort` | Orbital Fort | – | 0 | 24/0/34/80 | 100 | – | – | 10 | Orb/Elec×1, Beam/Torp×12, Sh/Ar×12, Beam/Torp×12, Sh/Ar×12 |
| 33 | `hull.space_dock` | Space Dock | Co4 | 0 | 40/10/50/200 | 250 | – | 200 | 12 | Orb/Elec×1, Beam/Torp×16, Sh/Ar×24, Beam/Torp×16, Sh×24, Elec×2, Elec×2, Beam/Torp×16 |
| 34 | `hull.space_station` | Space Station | – | 0 | 240/160/500/1200 | 500 | – | unlimited | 14 | Orb/Elec×1, Beam/Torp×16, Sh×16, Beam/Torp×16, Sh/Ar×16, Sh×16, Elec×3, Beam/Torp×16, Elec×3, Beam/Torp×16, Orb/Elec×1, Sh/Ar×16 |
| 35 | `hull.ultra_station` | Ultra Station | Co12 | 0 | 240/160/600/1200 | 1000 | – | unlimited | 16 | Orb/Elec×1, Beam/Torp×16, Elec×3, Beam/Torp×16, Sh×20, Sh×20, Elec×3, Beam/Torp×16, Elec×3, Beam/Torp×16, Orb/Elec×1, Sh/Ar×20, Beam/Torp×16, Sh/Ar×20, Elec×3, Beam/Torp×16 |
| 36 | `hull.death_star` | Death Star | Co17 | 0 | 240/160/700/1500 | 1500 | – | unlimited | 18 | Orb/Elec×1, Beam/Torp×32, Elec×4, Elec×4, Sh×30, Sh×30, Elec×4, Beam/Torp×32, Elec×4, Beam/Torp×32, Orb/Elec×1, Sh/Ar×20, Elec×4, Sh/Ar×20, Elec×4, Beam/Torp×32 |
