# Path B: SC-EM800 → GearRatio Connect IQ Integration — Implementation Plan

> **Superseded (2026-07-30):** the "integrate into GearRatio" framing below has
> been replaced by a **new standalone data-field app, `di2steps`**, in this repo
> (`source/`, `manifest.xml`). GearRatio stays the ANT-based app; di2steps is the
> BLE/STEPS app. The staged, prove-it-first thinking here still applies — only the
> host app changed. See the current architecture in
> `~/.claude/plans/we-are-creating-a-polymorphic-quail.md`.

## Context for whoever (human or Claude Code) picks this up

This is **Path B** of the Di2/STEPS Data Access project (see `project.md`). Path A
(protocol reverse-engineering) is **complete and validated** — see
`SCEM800-BLE-protocol.md` for the full byte-level protocol reference. This
document is the implementation plan for consuming that protocol inside
**GearRatio**, an existing, already-working Garmin Connect IQ data field.
GearRatio's display/rendering logic is not in question — it just needs to be
fed the correct data instead of whatever it currently reads.

**Read `SCEM800-BLE-protocol.md` in full before writing any parsing code.**
It is the source of truth for byte offsets, packet types, and confidence
levels (validated vs. inferred vs. unconfirmed).

**Reference implementation:** `markdotai/emtb` (MIT licensed,
https://github.com/markdotai/emtb) is cloned locally at
`/Users/robert/dev/oss/emtb` (kept OUT of this repo on purpose). It is a
full copy of `markdotai/emtb`,
a working Connect IQ data field for a *different* STEPS display (E7000/EN100)
that talks to the same BLE service/characteristic. Its BLE connection,
scanning, and profile-registration boilerplate is directly reusable —
`emtbDelegate.mc` is the file that matters most. Its gear/mode parsing logic
independently converged on the **same byte offsets** we found by hand,
which is why we trust this approach. Do not copy it wholesale into
GearRatio — GearRatio already has its own working structure — but use it as
the reference for "how does a Connect IQ app correctly open and maintain a
BLE connection to this specific device," since that part is solved and
tested by someone else already.

**Also present, for context:** `ebikeDataField` and `ebikeApp`
(`MarkusDatgloi`, forks of emtb) — not bundled locally, but linked from
`project.md`. Their main contribution is a documented Connect IQ platform bug
around BLE profile registration on some watch models (VivoActive 4, Venu) —
worth knowing about even though GearRatio's target device(s) may not be
affected.

---

## Guiding principle

Nothing about this project has been simple so far — the packet layout is
multiplexed and undocumented, several early hypotheses turned out wrong
(byte 2 of the mode packet looked like "crank phase," was actually speed),
and even Path A required switching capture techniques twice (screenshots →
CSV log export) before getting clean data. **Assume the same will be true on
Garmin hardware.** The phone-based BLE stack (iOS, via nRF Connect) and the
Garmin Edge's own BLE stack are different implementations and may behave
differently — different notify timing, different reconnection behavior,
possibly even different chunking of multi-part packets. Do not assume
Path A's findings transfer perfectly; validate each assumption on-device
before building on top of it.

This plan is therefore staged so that **each phase produces a fallback-safe,
independently useful result**, and later phases depend on the earlier ones
being *proven*, not just written.

---

## Phase 1 — Prove basic BLE read capability on-device

**Goal:** confirm the Garmin Edge can open a BLE connection to the SC-EM800,
discover the `0x18EF` service, subscribe to `2AC1` notify, and receive *any*
raw byte array in `onCharacteristicChanged` — with zero parsing logic yet.

**Why first:** this isolates "can we connect and receive data at all" from
"do we understand what the data means." If this phase fails, no amount of
correct byte-offset knowledge matters. If it succeeds, everything after is
comparatively low-risk.

**Tasks:**
- [ ] Port emtb's `bleInitProfiles()` profile definitions for the
      `modeServiceUuid` (`000018ef-...`) / `modeCharacteristicUuid`
      (`00002ac1-...`) pair only — skip the battery and MAC-address profiles
      initially to keep this phase minimal. (Note: emtb registers 3 profiles
      total and Connect IQ caps BLE profile registrations at 3 — check
      whether GearRatio already uses any BLE profiles itself, and if so,
      whether there's budget left for these.)
- [ ] Port the scan/connect state machine (`onScanResults`,
      `onConnectedStateChanged`, `onProfileRegister`) closely enough to
      reliably land on a connected, notifying state.
- [ ] On `onCharacteristicChanged`, do nothing but log: payload length and
      raw hex bytes. No branching, no field extraction.
- [ ] Verify against real hardware: confirm logs show the same packet-length
      family we found via nRF Connect (10, 18, 19, 20, 3, 6, 13 bytes) and
      not something unexpected (e.g., truncated or reassembled differently
      by the Garmin BLE stack).
- [ ] Confirm reconnection behavior: what happens if the Edge goes out of
      range, or the SC-EM800 sleeps? Does GearRatio's existing app lifecycle
      (background/foreground, activity start/stop) interact with this
      cleanly?

**Exit criteria:** raw byte arrays reliably arriving in the callback,
matching known packet-length signatures, across at least one full ride or
extended bench test (not just a few seconds).

---

## Phase 2 — Filter and parse in real time

**Goal:** turn raw byte arrays into gear number, max gear, and assist mode,
updating GearRatio's internal state live.

**Tasks:**
- [ ] Branch on `value.size()`, following emtb's proven pattern (not an
      explicit type-tag check — size is sufficient and matches emtb's own
      approach):
  - `size == 18` → gear packet. Read `value[5]` = current gear,
    `value[6]` = max gear (expected constant `0x0B`/11, but read it live
    rather than hardcoding — don't assume every rider's cassette is 11-speed).
  - `size == 10` → mode packet. Read `value[1]` = assist mode
    (`0`=Off, `1`=Eco, `2`=Trail, `3`=Boost, `4`=Walk — see protocol doc for
    confidence levels per value).
  - All other sizes (19, 20, 3, 6, 13 bytes) → ignore/discard cheaply. Do
    not allocate or process further; these are wheel/distance counters,
    unknown blocks, and rider-profile-name strings, not needed for
    GearRatio's purpose.
- [ ] Wire parsed gear/max-gear into whatever GearRatio currently uses to
      drive its display (replacing the incorrect/stale source it reads
      today).
- [ ] Decide whether assist mode is surfaced in GearRatio's UI at all, or
      just gear — confirm with the existing GearRatio field layout/settings
      before adding new display elements.
- [ ] Handle the "no data yet" state explicitly (just connected, first
      notify hasn't arrived) — GearRatio should show a sensible placeholder,
      not a stale/default gear value that looks like real data.
- [ ] Handle the "0 vs missing" ambiguity — if `value[5]` is ever `0`
      (untested — we only observed 1–11), decide whether that means "no
      gear signal" or is a legitimate value, and don't let it silently
      display as gear "0."

**Exit criteria:** GearRatio's display tracks real shifts and mode changes
live, correctly, across the full 1–11 gear range and all observed assist
modes, on actual Garmin hardware — not just in a simulator.

---

## Phase 3 — Debug/logging mode

**Goal:** build a way to capture raw protocol data *from the Garmin Edge
itself*, independent of a phone. Given how much Path A's understanding
shifted as more data came in (see Guiding Principle above), assume Path B
will surface on-device behavior we haven't seen yet, and we'll need real
field captures to debug it — not just guesses from the simulator.

**Why this matters enough to build deliberately, not bolt on later:** by the
time something looks wrong on a ride, there's no way to "go back and nRF
Connect it" — the Edge is the only thing present. Build the capture
capability before you need it, not after a confusing bug report from a ride.

**Design approach — modeled on emtb's `emtbFitContributor.mc`:**
emtb already demonstrates the exact mechanism needed: writing live sensor
values into custom FIT fields via `Toybox.FitContributor`, so they persist
into the `.FIT` file and are recoverable afterward through Garmin
Connect/any FIT file viewer — effectively the same after-the-fact review
workflow nRF Connect's CSV log gave us, but sourced from the real device in
real riding conditions.

**Tasks:**
- [ ] Add a debug-mode setting (boolean, off by default, toggleable via
      GearRatio's existing Connect IQ app settings/properties) so this
      doesn't run — and doesn't cost memory/battery — for normal users.
- [ ] When enabled, write raw diagnostic fields into the FIT file per
      notification received, at minimum:
      - packet size (to distinguish which type was received)
      - raw byte array (as hex string, or as several UINT8 fields if
        FitContributor can't take a raw string easily at usable length)
      - a monotonic sequence number or timestamp delta, to reconstruct
        notify timing/frequency after the fact
- [ ] Consider a secondary lightweight mode: an in-memory ring buffer of the
      last N raw notifications, viewable on-device (e.g., a debug screen)
      for quick sanity checks without needing to sync and pull a FIT file.
- [ ] Confirm FIT field budget/limits aren't already exhausted by
      GearRatio's existing fields — FitContributor fields are a limited
      resource per data field.
- [ ] Document, in this project, how to actually retrieve and read back
      the debug FIT data after a ride (export path, tool to decode it —
      likely a small Python script similar to the CSV analysis already done
      for the nRF Connect captures, adapted for FIT).

**Exit criteria:** ability to enable debug mode, do a short ride/bench test
exercising several gears and assist modes, disable debug mode, and pull a
FIT file that reconstructs the same kind of byte-level table we built from
the nRF Connect CSV — without needing a phone in the loop.

---

## Phase 4 — Integration & validation

**Goal:** confirm the whole thing works end-to-end and doesn't regress
GearRatio's existing behavior.

**Tasks:**
- [ ] Full-range validation: confirm all 11 gears and all observed assist
      modes display correctly on-device across a real ride, not just a
      bench test.
- [ ] Confirm GearRatio's other existing working fields/features are
      unaffected (no shared state, memory, or BLE-profile conflicts
      introduced by the new SC-EM800 connection).
- [ ] Battery percentage was in scope per `project.md`'s open items —
      revisit `batteryServiceUuid`/`batteryCharacteristicUuid` (standard
      GATT battery service, `0x180F`/`0x2A19`) per emtb's code, and
      cross-check against SC-EM800's actual reported values, if not already
      covered elsewhere in GearRatio.
- [ ] Update `project.md` status log and `SCEM800-BLE-protocol.md` with any
      new findings from on-device testing (expected, given the Guiding
      Principle above).

---

## Open risks to keep in view

- **Assist-mode value `0x04` (Walk)** is sourced from emtb's code comment
  only, never observed on SC-EM800. If a rider hits a walk-assist button,
  confirm this rather than assuming.
- **`value[4]` (assistance level) and `value[5]` of the *mode* packet
  (cadence)** are unvalidated against SC-EM800 — our own capture session had
  this byte at `0` throughout, likely because there was little real pedaling
  load. Not required for gear display, but worth knowing if GearRatio ever
  wants to surface them.
- **Speed field (`value[2]`/`value[3]` of the mode packet)** — our earlier
  protocol doc mischaracterized this as "crank phase"; emtb's code strongly
  suggests it's actually speed (`/10` scaling, likely km/h or mph tenths).
  Re-verify before displaying it as speed specifically.
- **Byte 6 (max gear) assumed constant `0x0B`** — read it live per Phase 2,
  don't hardcode 11, in case this varies by bike/cassette.
- **BLE profile registration cap of 3** (Connect IQ platform limit,
  documented both in emtb and in the `ebikeDataField` bug report) — confirm
  GearRatio has budget for the SC-EM800 profile alongside anything it
  already registers.
