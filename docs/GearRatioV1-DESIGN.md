# Gear Ratio v1 — Design Notes (archived reference)

> **Provenance.** Copied verbatim from `GarminGearRatioVersion1/DESIGN.md`
> (repo `inquinity/GarminGearRatioVersion1`, commit `30c7301`) on 2026-08-10,
> when this project took over the GarminGearRatio name. That project solves the
> same problem from a **raw ANT+ Di2 channel**; this one reads
> `Toybox.Activity.Info` instead. See `../GarminGearRatioVersion1`.
>
> **Why it is kept:** the "Entry order and sorting" section below is the only
> written source for the gear-index convention, and it cites a production
> implementation (ki2) tested against real Di2 hardware rather than asserting a
> plausible-sounding rule. This project's convention was confirmed
> independently on-device (2026-08-09, rider's own observation) and **agrees**
> with it: rear position 1 is the largest cog, front position 1 the small ring.
>
> **Correction carried over:** v1's `source/GearConfig.mc` had the doc comments
> on `sortAscending` and `sortDescending` swapped — `sortAscending` was labelled
> "used for rear cogs", `sortDescending` "used for front rings", the reverse of
> how `commit()` actually calls them. The *code* was always right and matches
> this document; only those two comments were wrong. They misled a reading of
> that project during this session, and have since been fixed there.
>
> Sections below describing ANT+ channel discovery and the `SimDi2Profile`
> simulator properties apply to v1 only — this project has neither.

---

# Gear Ratio Data Field — Design Notes

## Di2 Telemetry

Di2 (and eTap) electronic shifting communicates over ANT+ and reports two
distinct categories of data.

### Gear configuration (what is physically present)

The ANT+ Di2 information channel tells us which derailleurs are installed:

| Derailleurs detected | Interpretation |
|---|---|
| Rear only | 1× drivetrain — single chainring, no front derailleur |
| Front + Rear | 2× drivetrain — two chainrings |

The rear derailleur also reports the number of sprockets it manages (11, 12,
or 13 on current systems).

This gives us the **drivetrain topology**: how many rings and cogs the system
has. It does **not** tell us the tooth counts on those rings and cogs.

### Gear position (what gear is currently selected)

The ANT+ Shifting Profile (device type 0x22) transmits the current gear
position as a front index and a rear index in real time as the rider shifts.

---

## Sprocket Tooth Counts

Tooth counts are **always entered by the user**. Di2 telemetry never includes
them. The rider knows their own chainring and cassette sizes.

### Validation rules

- Every tooth count must be an integer in the range **2–99** (inclusive).
  - Minimum 2: prevents near-zero-ratio math; no real sprocket has fewer.
  - Maximum 99: prevents integer overflow; no real sprocket exceeds this.
- The number of values entered must exactly match what the Di2 topology says:
  - Front teeth array length must equal the chainring count (1 or 2).
  - Rear teeth array length must equal the cog count (11, 12, or 13).

### 1× drivetrains

When only a rear derailleur is discovered:
- The rider has exactly **one chainring** and no front derailleur.
- The user enters **a single front tooth count**.
- This value never changes between shifts (there is no front shifting), so it
  is stored once and reused for every gear ratio calculation.
- The front gear position reported by Di2 is always 1 for 1× systems.

### 2× drivetrains

When both a front and rear derailleur are discovered:
- The rider has exactly **two chainrings**.
- The user enters **two front tooth counts**, in any order — see
  "Entry order and sorting" below.
- Di2 reports the active ring index (1 or 2) in real time.

### Entry order and sorting

`frontTeeth[gear - 1]` and `rearTeeth[gear - 1]` are looked up directly by
the gear index Di2 reports — there is no room for a mismatch between entry
order and what the real hardware means by "gear 1," so the wizard sorts
values into the expected convention automatically rather than relying on
the user to enter them in the right order.

**Gear index 1 is the easiest gear on each axis** — small ring in front,
large cog in the rear — increasing toward the hardest gear. This is not
guesswork: the official ANT+ Shifting Device Profile spec (D00001198) is
gated behind ANT+ Alliance membership, but
[ki2](https://github.com/valterc/ki2) — an open-source Karoo companion app
that decodes this exact same ANT+ Shimano Shifting profile against real
Di2 hardware — confirms it explicitly, both in its lookup tables and its
own unit tests:
[`RearTeethPattern.java`](https://github.com/valterc/ki2/blob/main/app/src/main/java/com/valterc/ki2/data/shifting/RearTeethPattern.java) /
[`RearTeethPatternTest.java`](https://github.com/valterc/ki2/blob/main/app/src/test/java/com/valterc/ki2/data/shifting/RearTeethPatternTest.java)
assert `getTeethCount(1) >= getTeethCount(lastGear)` (e.g. an 11-32
cassette: `getTeethCount(1) == 32`, `getTeethCount(11) == 11`), and
[`FrontTeethPattern.java`](https://github.com/valterc/ki2/blob/main/app/src/main/java/com/valterc/ki2/data/shifting/FrontTeethPattern.java) /
[`FrontTeethPatternTest.java`](https://github.com/valterc/ki2/blob/main/app/src/test/java/com/valterc/ki2/data/shifting/FrontTeethPatternTest.java)
assert the opposite (`getTeethCount(1) <= getTeethCount(lastGear)`; a 50-34
setup: `getTeethCount(1) == 34`, `getTeethCount(2) == 50`).

So:
- **Front rings** are sorted **smallest first** (`sortAscending`). Gear
  position 1 = the small ring.
- **Rear cogs** are sorted **largest first** (`sortDescending`). Gear
  position 1 = the large cog.

This is sourced from a production implementation against real hardware,
not just plausible convention — but it's still worth a one-time real-device
check the first time this runs against actual Di2/eTap: shift onto your
smallest chainring and largest cog (easiest gear) and confirm the display
reads gear 1/1.

---

## Simulator Substitutes

Because the Connect IQ simulator cannot send ANT+ data, two sets of
properties stand in for hardware signals:

| Property | Simulates |
|---|---|
| `SimDi2Profile` (0–3) | The gear configuration reported by the ANT+ Di2 channel |
| `SimFrontGear`, `SimRearGear` | The gear position reported by the ANT+ Shifting Profile |

`SimDi2Profile` must be set before the tooth-count wizard can run, because
the wizard needs to know how many rings and cogs to ask about.

---

## On-Device Configuration Wizard

Tooth counts are entered through the on-device settings wizard
(`getSettingsView()`). The wizard is launched by pressing the select/OK
button while the settings status screen is shown.

**Wizard steps:**
1. Select Di2 profile (1×11, 2×12, or 2×13). This replaces `SimDi2Profile`
   and clears any previously saved tooth counts.
2. Enter each front tooth count one at a time (1 picker for 1×, 2 for 2×).
3. Enter each rear tooth count one at a time (11, 12, or 13 pickers).

Within a single ring or cog picker, the values can be entered **in any
order** — they're sorted into the correct gear-position convention when the
wizard commits (see "Entry order and sorting" above). To save scrolling,
each picker after the first (within the same ring/cog phase) starts at the
value just entered rather than resetting to 2T, since cassettes and ring
sets are both entered in one general direction. The very first pick of each
phase (first ring, first cog) always starts at 2T.

All values are written to Properties only when the wizard completes
successfully. Cancelling at any point leaves the existing configuration
unchanged.
