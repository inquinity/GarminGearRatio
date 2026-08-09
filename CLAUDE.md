# di2steps — Connect IQ data field for Shimano STEPS (SC-EM800)

Reads the SC-EM800's shifting/assist data and renders it as a Garmin data field.
Sibling to **GearRatio** (`../GarminGearRatio`), which reads gear position from a
raw ANT+ Di2 channel; this app targets a bike where that Di2 channel is not
exposed but the STEPS BLE stream is.

- **Wire format (source of truth):** `docs/SCEM800-BLE-protocol.md`
- **Architecture / plan:** `~/.claude/plans/we-are-creating-a-polymorphic-quail.md`
- **BLE reference impls (kept out of this repo):**
  - **emtb** (original): `markdotai/emtb` at `/Users/robert/dev/oss/emtb` — the proven BLE 
    state machine our `ShimanoBleDelegate.mc` is ported from.
  - **ebikeDataField** (updated/derivative): `MarkusDatgloi/ebikeDataField` at `/Users/robert/dev/oss/ebikeDataField` — 
    fixes for Garmin CIQ BLE profile registration bug (reports "ErrPrf_N" when profiles fail), 
    best practices for multi-device Shimano STEPS data fields.

## Data sources

There are **two independent paths** into this app. They are not alternatives to
each other — each carries data the other does not.

**1. Shimano BLE stream** (`0x18EF` service, `2AC1` notify characteristic,
multiplexed by a leading type-tag byte; permission `BluetoothLowEnergy`).
Owned by `ShimanoBleDelegate.mc`, decoded in `StepsData.onPacket`. Carries
assist mode, speed, cadence, assist level, rider profile name, plus gear /
max-gear. Battery comes from the standard GATT battery service (`0x180F`/`0x2A19`),
not the multiplexed characteristic.

**2. `Toybox.Activity.Info` derailleur fields** — `@since` API 2.1.0, supported
on `edge1050`, and requiring **no permission at all**:

```
info.frontDerailleurIndex   info.frontDerailleurMax   info.frontDerailleurSize
info.rearDerailleurIndex    info.rearDerailleurMax    info.rearDerailleurSize
```

The head unit decodes these from its own STEPS pairing, independent of anything
this app does. They are what Garmin's built-in "Rear cog position" (`1/11`) and
"Front chain position" (`1/1`) fields render, and `…Size` is teeth count. On the
SC-EM800 the built-in Gear Ratio field renders blank, which is the expected
symptom of both `…Size` fields arriving as `null` — **this is currently a
hypothesis under test**, see the Test screen and `docs/project.md`.

**Ruled out: `AntPlus.Shifting`.** The 9.2.0 SDK doc for `getShiftingStatus()`
states verbatim that it "Will not provide status for Shimano shifting systems."
Do not re-investigate it. Its `DerailleurStatus` shift-failure counters are the
only drivetrain data no other path exposes, and they are unavailable here.

## App type & structure

Single `type="datafield"` app, `edge1050`, permission `BluetoothLowEnergy`. One
BLE connection owned by the field; "pages" are **display modes** chosen via the
`DisplayMode` setting (0=Ride, 1=Gear Config, 2=Test), not button navigation.

- `source/Di2StepsApp.mc` — AppBase; wires up the view + BLE.
- `source/Di2StepsView.mc` — DataField; `onUpdate` dispatches on `DisplayMode`.
- `source/ShimanoBleDelegate.mc` — BLE central: scan/pair/identify-by-MAC/notify.
- `source/StepsData.mc` — decoded state + raw-packet capture for the Test screen.

## Known issues & validation notes

**BLE profile registration:** Garmin CIQ has a documented bug on VivoActive 4 /
Venu where registering the 2nd and 3rd BLE profiles fails silently. Edge 1050
should not be affected. If connection fails on device, the signal is the Test
screen's status line reading **"Initializing..."** and never advancing to
"Scanning..." — `statusLine()` shows that whenever
`ShimanoBleDelegate.isRegistered()` is false, i.e. fewer than 3 profiles
registered. (ebikeDataField surfaces the same condition as an "ErrPrf_N" string;
we do not have an equivalent `errorReport` field, and the status line is
sufficient.)

**Unwired settings:** `Debug`, `FrontRings`, `FrontTeeth`, `RearTeeth` are
declared in `resources/properties.xml` and appear in the settings UI, but no
source file reads them yet. See the comments there.

## Versioning

`<iq:application version>` in `manifest.xml` is the release marker. The Edge
only replaces an installed app when that version **increases** under the same
UUID (`ac6eef9d9ca5471caafb0730d68bee87`).

**Bump the patch digit on every build you push to the device.** If you don't,
`deploy.sh` will report success, the file will land in `/GARMIN/Apps`, and the
Edge will silently keep running the old code — which looks exactly like a code
change that didn't work. `deploy.sh` echoes the version it is building for this
reason; the Test screen's build tag is the on-device confirmation of which build
is actually running.

## Build & run

SDK: `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`
Dev key: `/Users/robert/Certs/garmin_developer_key.der`
Deployment tool: **SwiftMTP** (`github.com/Neighbor-Z/SwiftMTP`) — CLI for MTP file transfer to Garmin devices

Verify the SDK is actually where the build expects before debugging a build failure:

```bash
ls "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/"
```

### Simulator workflow
```bash
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
"$SDK/bin/monkeyc" -d edge1050 -f monkey.jungle -o bin/di2steps.prg -y /Users/robert/Certs/garmin_developer_key.der
open "$SDK/bin/ConnectIQ.app"           # launch simulator
"$SDK/bin/monkeydo" bin/di2steps.prg edge1050
```

### Device deployment
`./deploy.sh` builds, discovers the connected device/storage IDs, and pushes to
`/GARMIN/Apps`. SwiftMTP ships as a sandboxed app with no `swiftmtp` on `PATH`;
the CLI lives at `/Applications/SwiftMTP.app/Contents/MacOS/swiftmtp-cli`.
Connect the Edge 1050 by USB in MTP mode (not Garmin Basemap mode), unlocked.
Bump the manifest version first (see Versioning), then restart the Edge after
the push to load the data field.

## Testing

**Neither data path can be exercised in the simulator.** BLE stays on
"Scanning..." forever, and `Activity.Info`'s derailleur fields have no simulated
drivetrain behind them. The simulator verifies exactly three things: it
compiles, it passes strict type-checking, and the Test screen lays out at the
field's slot size. Everything about data retrieval is device-only, on the real
Edge 1050 + bike.

On-device procedure — set `DisplayMode = 2` (Test / Diagnostics) and read the
two blocks:

- **Values block** (large, auto-fit): build tag + slot size, connection status,
  then one row per decoded field. Rows sourced from `Activity.Info` are
  prefixed `A:` to distinguish them from the BLE-decoded rows. `--` means not
  yet received; `null` means the field was read and the head unit returned
  nothing — that distinction is the whole point of the current probe.
- **Raw block** (small, bottom, capped at 40% height): last raw packet seen per
  BLE type-tag as hex. Empty tags are omitted, so a missing row means that
  packet type has never arrived.

Shift through the full rear range and cycle every assist mode; a bench test is
not sufficient, since several fields only populate while the motor is active.

### Type checking

Builds use monkeyc's **default** type-check level, and that is deliberate for
now. `monkeyc -l 3` (strict) currently reports ~41 errors, nearly all in
`ShimanoBleDelegate.mc`: BLE iterators and `Ble.Uuid` constants come back as
`Object`/`Any`, and the profile-registration dictionaries don't match the
declared `Dictionary{:uuid as Uuid, ...}` shape. Cleaning that up is its own
task — don't treat a strict-mode run as a regression signal until it is done.

Practical rule while writing BLE code: iterators return `Object`, so cast
results to `Ble.Device` / `Ble.ScanResult` before calling their methods.

# git
Use git commits instead of PRs
Keep commits atomic: small and focused on a single change
Use short commit messages (1-3 lines); if there is a need for a more extensive message, ask before continuing.
