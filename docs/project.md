# Di2 / STEPS Data Access — Project Plan

## Goal
Determine whether the Shimano SC-EM800 head unit's shifting/assist data can be
read by a third-party device, and get it into a usable form (Garmin Connect IQ
field, Karoo, or other). Foundational open question: is the data actually
broadcast off the head unit, and if so, in what format/protocol?

## Confirmed so far
- Official SC-EM800 manual states the head unit sends everything shown on its
  main screen to external devices over both **ANT (private)** and
  **Bluetooth LE**. So the data does leave the unit — the open question is
  packet format, not existence.
- Existing Connect IQ Di2 apps (Di2Explore, Di2 Gear & Battery Viewer) target
  road/gravel Di2 groupsets (derailleur + D-Fly battery), not the STEPS
  motor/assist system — likely explains why Di2 Dash Pro found nothing.
- Open-source STEPS-specific data field exists (`markdotai/emtb`, "STEPS EMTB
  Data" on Connect IQ store), confirmed working on E7000 display / EW-EN100
  junction, confirmed **broken** on E8000 (different BLE format). SC-EM800
  compatibility unknown/untested.
- `kwakeham/DiHack` (formerly cmoski/DiHack) has reverse-engineered Shimano's
  Private ANT profile with documented ANT pages — reference for the ANT path.

## Investigation Paths

### 1. nRF Connect and data analysis
Use nRF Connect for Mobile (free, iOS/Android, Nordic Semiconductor) to pair
directly with the SC-EM800 over BLE and inspect its GATT services/characteristics.

- [x] Install nRF Connect for Mobile
- [ ] Put SC-EM800 into BLE pairing/connection mode
- [ ] Scan and connect, enumerate services/characteristics
- [ ] Identify custom (non-SIG-standard) UUIDs — likely candidates for
      Shimano proprietary data
- [ ] Subscribe/notify on candidate characteristics
- [ ] Trigger shifts / assist mode changes on the bike, capture raw hex
      before/after
- [ ] Log characteristic UUIDs + payload bytes for each observed event
- [ ] Compare captured UUIDs/bytes against `markdotai/emtb` source to see if
      SC-EM800 matches the E7000/EN100 format, the E8000 format, or neither

### 2. Order Di2 wire adapters and test fit
Direct hardware approach — order the adapter(s) needed to connect a wired
reader inline and see if it physically fits inside the head unit housing.

- [ ] Confirm which SC-PCE02 cable version ships in-box (SD50-only vs
      SD50+SD300) — verify physically, not from part number alone
- [ ] Determine if EW-AD305 adapter is needed for this specific unit
- [ ] Order adapter(s)
- [ ] Test physical fit inside SC-EM800 housing
- [ ] If it fits, evaluate what data is accessible via this wired path

### 3. Call Shimano for technical/protocol data
Follow up on the earlier call where a Shimano rep confirmed shifting data is
present in the stream but couldn't point to a reader.

- [ ] Identify a more technical point of contact (engineering/OEM support
      rather than consumer support)
- [ ] Ask specifically about: BLE GATT service/characteristic layout, ANT
      private page structure, and whether SC-EM800 shares protocol with
      other STEPS displays (E7000/E8000/EN100) or is unique
- [ ] Ask whether documentation/SDK access exists for third-party readers

### 4. Build a protocol analyzer (Karoo or otherwise)
Fallback/parallel path if BLE inspection via phone isn't sufficient (e.g.
needs to capture at higher rate, or in more detail than nRF Connect provides).

- [ ] Evaluate whether Karoo (or another platform) has lower-level BLE
      access than a stock phone BLE inspector
- [ ] Reference `kwakeham/DiHack` ANT page documentation as a model for
      building an ANT GenericChannel listener, if ANT path is chosen instead
      of/in addition to BLE
- [ ] Build minimal capture/log tool
- [ ] Cross-reference captures against Path 1 findings

## Reference links
- `markdotai/emtb` — https://github.com/markdotai/emtb
- `MarkusDatgloi/ebikeDataField` (bugfix fork) — https://github.com/MarkusDatgloi/ebikeDataField
- `kwakeham/DiHack` — https://github.com/kwakeham/DiHack (wiki: ANT Pages)
- SC-EM800 manual (UM-7H90C-000) — https://si.shimano.com/en/pdfs/um/7H90C/UM-7H90C-000-ENG.pdf
- Connect IQ forum thread, STEPS EMTB Data — https://forums.garmin.com/developer/connect-iq/f/showcase/211359/data-field-steps-emtb-data

## Status log
- 2026-07-29: Plan created. Starting with Path 1 (nRF Connect).
- 2026-07-30: Path A (protocol reverse-engineering) complete and validated
  (`SCEM800-BLE-protocol.md`). Path B reframed from "integrate into GearRatio"
  to a **new standalone data-field app, `di2steps`**, in this repo (see
  `PATHB-CONNECTIQ-PLAN.md` header note and
  `~/.claude/plans/we-are-creating-a-polymorphic-quail.md` for the current
  architecture). Implemented and committed roadmap **Stage 1 (skeleton)** and
  **Stage 2 (BLE retrieval + TEST/diagnostics screen)**: `Di2StepsApp.mc`,
  `Di2StepsView.mc`, `ShimanoBleDelegate.mc` (emtb-ported scan/pair/notify
  state machine), `StepsData.mc`. TEST screen renders connection status plus
  every decoded field (gear/max, assist mode, speed, cadence, assist level,
  battery, profile) and the last raw packet per type-tag; labels spelled out,
  not abbreviated. Docs moved into `docs/`. Compiles/runs in the simulator.
  **Not yet done:** Stage 3 (RIDE mode — `drawRide` is a stub), Stage 4 (config
  wizard + GEAR_CONFIG mode — `drawGearConfig` is a stub), Stage 5 (FIT debug
  capture). **Critical caveat:** BLE cannot be exercised in the simulator —
  Stage 2's exit criteria (live gear/mode tracking across the full 1–11 range)
  are **unverified on real Edge 1050 + SC-EM800 hardware**; that on-device
  validation is the immediate next step before building RIDE mode on top.
