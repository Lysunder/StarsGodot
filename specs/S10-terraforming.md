# S10 Terraforming

Status: draft (2026-10-03), first pass. Read from the decompiled code (the radiation reach checked in the
disassembly, where the decompiler lost an assignment). Implemented in `core/rules/terraforming.gd`. Matches the
original over 26 turns of a harness game (`terra1`): terraform items completing steps on a Total Terraforming
colony, and a Claim Adjuster colony terraforming itself, including a reach change from new tech. Not yet seen in a
harness game: the Claim Adjuster's permanent change and remote terraforming.
References: `GetTerraformCapability@1040:5220`, `Planet_MaxTerraform@1040:51bc`, `Planet_TerraformStep@1040:3d50`,
`ClaimAdjusterTerraform@10b0:2ba4`, `RemoteTerraform@10b0:2dc0`, `RemoteTerraform_Step@10b0:523e`,
`Fleet_TerraformPower@1078:1a34`, `Production_CompleteItem@10b0:0e68` (terraform items), `Planet_Depopulate@1040:553a`.

## Summary

Terraforming moves a planet's environment (gravity, temperature, radiation) one point at a time toward its owner's
ideal, within a reach set by the owner's terraforming tech and measured from the planet's original environment.
It happens through production items (S09), automatically every year for Claim Adjuster races, and through fleets
with Orbital Adjusters, which can also make an enemy planet worse.

## Data used

| Data | Notes |
|---|---|
| Planet environment and original environment | 0–100 per axis (S08) |
| Race habitability | low, center (the ideal), high per axis, or immune (S06) |
| Terraforming parts | `terraform` stat; tags `terraform_total` (all axes), `terraform_gravity`, `terraform_temperature`, `terraform_radiation` |
| Player tech levels and traits | which terraforming parts the player can build (S04) |
| Fleet ships | parts with the `remote_terraform` stat (the Orbital Adjuster) |

## Algorithm

### 1. Reach

For a player (the one whose tech counts): the reach on every axis is the `terraform` value of the best total
terraforming part the player can build (0 if none). For each axis, if the best part for that axis has a larger
value, that value is the axis's reach. "Best" is the available part with the largest value.

### 2. Targets

For a planet, a race (whose habitability counts), a reach r per axis and a mode (**improve** or **worsen**), each
axis gets a low target and a high target, each a value or none:

1. None for both if r = 0 or the race is immune on the axis.
2. Otherwise, with o the original value and e the current value: low = o − r if that is below e (then at least 1),
   else none; high = o + r if that is above e (then at most 99), else none.
3. **Improve:** with c the race's center: if e = c, none for both. If c < e: no high target; the low target, if any,
   is at least c (low = max(low, c)). If c > e: no low target; the high target, if any, is at most c.
4. **Worsen:** with distances from c: d = |e − c|, dl = |low − c| (0 if none), dh = |high − c| (0 if none). If
   d < dl or d < dh: drop the low target if dl < dh, otherwise the high target (so the target farther from the ideal
   remains). Otherwise none for both.

The planet can be terraformed when some axis has a target.

### 3. Maximum terraform

The number of single steps still possible (improve mode, the owner's race and tech): the sum over axes of e − low
(when there is a low target) and high − e (when there is a high target). This is the room for terraform items (S09).

### 4. One step

1. Targets as in step 2. h0 = the planet's habitability value for the race (S08).
2. For each axis with a target t (the low target if there is one, else the high target): set the axis to t, take the
   habitability value h, restore it; the axis's score is (|h − h0| × 100) div |e − t| + 1. Axes without a target
   score 0.
3. The axis with the highest score (the first on ties) moves 1 point: down if it has a low target, up otherwise,
   kept within 1–99. No target anywhere: nothing happens.

### 5. Production items

Each completed terraform unit (S09 items 4, 5, 12) is one step (step 4) in improve mode, with the owner's race and
tech.

### 6. Claim Adjuster (S02 phase 19)

For each planet, in planet order, whose owner has the instant terraforming setting (trait parameter
`terraform.instant`, Claim Adjuster):

1. **Permanent change:** a = random(3). If the race is not immune on axis a, its center differs from the original
   value o on that axis, random(10) = 0, and the population is at least 1000 units (100,000 colonists) or
   random(1000) < population: o moves 1 toward the center. (The draws stop at the first condition that fails, so a
   planet makes 1 to 3 draws.)
2. **Instant terraform:** targets in improve mode (owner's race and tech); every axis with a target is set to it
   (the low target if there is one, else the high target).

### 7. Remote terraforming (S02 phase 20)

For each fleet, in fleet order (S11), that has ships and is at a planet with an owner:

1. Power = the sum over its ship designs of (ships × parts with the `remote_terraform` stat, each counting its
   value). Nothing happens at power 0.
2. Friendly = the fleet's owner is the planet's owner or counts the planet's owner as a friend (S16). A hostile fleet
   terraforms only a planet without a starbase.
3. Up to power times: one step (step 4) with the planet owner's race for habitability but the fleet owner's tech
   (and traits) for the reach, in improve mode when friendly and worsen mode otherwise. Stop early when no step is
   possible.
4. Both players are told the result.

### 8. Losing the planet

When a Claim Adjuster race loses a planet, its environment returns to the original values (S08 step 7).

## Randomness

Only the Claim Adjuster permanent change draws: per Claim Adjuster planet, random(3), then random(10) and random(1000)
as step 6.1 says.

## Edge cases

- Reach is measured from the original environment, so after a Claim Adjuster permanent change the reach moves with
  it.
- Remote terraforming by a friend uses the friend's tech, not the owner's.
- Worsen mode leaves an axis alone when the planet is already as far from the ideal as the reach allows.

## Mod hooks

- Formulas: `terraform.reach`, `terraform.targets`, `terraform.step`.
- Trait parameters: `terraform.instant` (CA 1). Rule constants: `constant.terraform.permanent_chance` (10),
  `constant.terraform.permanent_population` (1000).
- Content: terraforming parts by tag and `terraform` value; `remote_terraform` on fleet parts.

## Open questions

1. Harness check still to do: the Claim Adjuster's permanent change (rare on small colonies) and remote terraforming.
2. Which players count as friends for remote terraforming beyond the relation setting (S16).
