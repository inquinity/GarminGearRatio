# GarminGearRatio — Connect IQ gear-ratio data field (Edge 1050)

Shows drivetrain gear positions and the resulting **gear ratio** (the "power
multiplier") as a Garmin data field. Developed against a Shimano STEPS
(SC-EM800) bike, but the data source is drivetrain-agnostic: it reads whatever
the head unit reports, so it is not Di2- or STEPS-specific.

Supersedes **Gear Ratio v1** (`../GarminGearRatioVersion1`), which solved the
same problem from a raw ANT+ Di2 channel and required the `Ant` permission.
This project took over the `GarminGearRatio` name on 2026-08-10; the app UUIDs
and display names differ, so both can be installed side by side.

- **Status log / decisions:** `docs/project.md`
- **Historical BLE wire format:** `docs/SCEM800-BLE-protocol.md` (no longer used
  by this app — see below)

## Data sources

**One source: `Toybox.Activity.Info`.** `@since` API 2.1.0, supported on
`edge1050`, requiring **no permission at all**:

```
info.frontDerailleurIndex   info.frontDerailleurMax   info.frontDerailleurSize
info.rearDerailleurIndex    info.rearDerailleurMax    info.rearDerailleurSize
```

The head unit decodes these from its own STEPS pairing. They are what Garmin's
built-in "Rear cog position" and "Front chain position" fields render.

**Measured behaviour on this bike (2026-08-09, on-device):**

| Field | Observed | Usable? |
|---|---|---|
| `rearDerailleurIndex` / `Max` | `10/11`, tracks every shift | Yes |
| `rearDerailleurSize` | constant `12` in every gear | **No** |
| `frontDerailleurIndex` / `Max` | `255/255` (no-data sentinel) | No — 1x bike |
| `frontDerailleurSize` | `0` | **No** |

So **positions are live; teeth are not**. Tooth counts come from app settings
via `GearConfig.mc`. This is also why Garmin's own Gear Ratio field is blank on
this bike: front teeth are 0, so the ratio is undefined.

**Index convention:** rear position 1 is the **easiest** gear — the largest cog
— descending to the smallest at position 11; front position 1 is the small ring.
Confirmed twice over: by the rider on this bike (2026-08-09) and, independently,
by v1's `DESIGN.md`, which derives it from ki2's tests against real Di2
hardware. See `docs/GearRatioV1-DESIGN.md` § "Entry order and sorting".

### Removed / ruled out

**Shimano BLE stream** (`0x18EF`/`2AC1`) — removed 2026-08-09. It connected but
cycled connect→drop, delivering only tags `0x01`/`0x06` plus a battery read;
the gear (`0x00`) and mode (`0x02`) packets never arrived. It may also have been
competing with the Edge's own STEPS pairing, which is the thing that feeds
`Activity.Info`. `docs/SCEM800-BLE-protocol.md` and the deleted
`ShimanoBleDelegate.mc` (see git history) remain accurate if it is ever revived.

**Don't revive it — it is unnecessary in every configuration, not just ours.**
BLE was never a source of otherwise-unavailable gear data; it was a second path
to data the head unit already had. Enumerating the cases:

| Drivetrain | Gear data reaches the Edge via | BLE needed? |
|---|---|---|
| Di2 12-speed (built-in wireless) | Normal Di2 protocol | No |
| Di2 11-speed + D-Fly, no ebike | Normal Di2 protocol — the Edge's own built-in Di2 data fields | No |
| Di2 11-speed, no D-Fly, no ebike | Nothing transmits at all | No — no data exists to read, by any protocol |
| Di2 11-speed + D-Fly + ebike | The ebike already transmits; D-Fly is redundant | No |
| Di2 11-speed, no D-Fly, + ebike | The ebike (this bike) | No — solved via `Activity.Info` |

Wherever gear data exists, something transmits it, the Edge is paired to it, and
`Activity.Info` exposes the decoded result. The argument doesn't depend on
Shimano specifics, so it holds for SRAM AXS and Campagnolo EPS too. BLE's only
unique offering was eBike telemetry — which Connect IQ does not expose at all
(see below), so even wanting that data wouldn't justify the path.

**`AntPlus.Shifting`** — the 9.2.0 SDK doc for `getShiftingStatus()` states
verbatim that it "Will not provide status for Shimano shifting systems."

**eBike telemetry** (assist mode, ebike battery, travel range, shifting advice)
— **not exposed to Connect IQ at all.** Zero hits across the entire SDK doc
tree; `Activity.Info` has no assist/battery/range member and AntPlus has no
eBike class. Those are firmware-internal native fields. BLE is the only possible
source, which is what the removal above costs.

## App type & structure

Single `type="datafield"` app, `edge1050`, **no permissions**. "Pages" are
**display modes** chosen via the `DisplayMode` setting (0=Ride, 1=Gear Config,
2=Test), not button navigation.

- `source/Di2StepsApp.mc` — AppBase; builds the view.
- `source/Di2StepsView.mc` — DataField; `onUpdate` dispatches on `DisplayMode`.
- `source/StepsData.mc` — drivetrain state sampled from `Activity.Info`.
- `source/GearConfig.mc` — tooth counts from settings + ratio computation.

## Known issues & validation notes

**Sample at draw time.** `onUpdate` calls `Activity.getActivityInfo()` itself
rather than relying only on the value cached by `compute()`. `compute()` runs at
1 Hz and `onUpdate` can run before it within a cycle, which rendered the
previous second's gear — a measured ~1s lag behind Garmin's built-in field,
confirmed fixed on the road 2026-08-10. Don't "simplify" this back to a cache
read without re-measuring.

**Residual 0–1s jitter — cause not yet settled.** Shifts sometimes appear
instantly and sometimes take up to ~1s. The likely explanation is the refresh
interval: Connect IQ redraws a data field roughly once per second, so a shift
landing just after a redraw waits for the next one, giving a delay uniform over
0–1s. There is no API to redraw faster.

**But that explanation predicts all five rows lag together**, and the rider's
2026-08-10 report was that gear position updated contemporaneously while the
ratio did not. Structurally that cannot happen: `drawTest` samples `rearPos`
once and derives position, teeth, and ratio from it in a single draw. So either
the comparison was our field against Garmin's own continuously-updating gear
graphic (which the refresh-interval story does explain), or something is
happening that this code doesn't account for. Shift logging exists to settle it.

### Shift timing logs

`Di2StepsView.logShift` emits one `System.println` line per *rendered* gear
change — a few per minute, not per frame:

```
di2steps t=812345 rear=8 teeth=17 ratio=2.76 render=180ms
```

`render` is the gap between sampling first seeing that position
(`StepsData.rearChangedAtMs`) and the draw that put it on screen. It measures
the only part of the delay this app controls; the head unit's own reporting
delay is invisible to us. Position, teeth and ratio are logged together on
purpose — they come from one sample in one draw and so cannot disagree, and a
log line showing them disagreeing would disprove that.

**Reading the logs.** In the simulator they appear directly in the `monkeydo`
console. On device, Connect IQ writes `println` output for side-loaded apps
under `/GARMIN/Apps/LOGS/` — **this exact path is unverified**; check the
directory listing after a ride and pull whatever appears:

```bash
CLI=/Applications/SwiftMTP.app/Contents/MacOS/swiftmtp-cli
"$CLI" ls   <deviceId> <storageId> /GARMIN/Apps/LOGS
"$CLI" pull <deviceId> <storageId> /GARMIN/Apps/LOGS/<file> ./ciq-log.txt
```

`deviceId`/`storageId` come from `swiftmtp-cli devices` / `storages` — the same
values `deploy.sh` discovers.

**Unimplemented modes:** `drawRide` and `drawGearConfig` are stubs. The data
path is validated and correct as of 2026-08-10, so all remaining work is UI:
the Test screen is a diagnostic layout, not a rider-facing one.

## Versioning

`<iq:application version>` in `manifest.xml` is the release marker. The Edge
only replaces an installed app when that version **increases** under the same
UUID (`ac6eef9d9ca5471caafb0730d68bee87`).

**Bump the patch digit on every build you push to the device.** If you don't,
`deploy.sh` will report success, the file will land in `/GARMIN/Apps`, and the
Edge will silently keep running the old code — which looks exactly like a code
change that didn't work. `deploy.sh` echoes the version it is building for this
reason, and verifies the pushed file's byte size afterwards.

The Test screen used to carry a build tag (`B5`, `B6`) as on-device
confirmation of which build was running. It was dropped once deploys were
reliable. If you ever again suspect the Edge is running stale code, adding a
tag line back to `drawTest` is the quickest way to prove it.

## Build & run

SDK: `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`
Dev key: `~/Library/Mobile Documents/com~apple~CloudDocs/Certs/garmin_developer_key.der`
(in iCloud Drive so it survives a machine rebuild — the old `~/Certs` copy was
lost that way. If a build fails on a missing key that `ls` shows as present,
iCloud has evicted its contents; open the folder in Finder to re-download.)
Deployment tool: **SwiftMTP** (`github.com/Neighbor-Z/SwiftMTP`) — CLI for MTP file transfer to Garmin devices

Verify the SDK is actually where the build expects before debugging a build failure:

```bash
ls "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/"
```

### Simulator workflow
```bash
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
KEY="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Certs/garmin_developer_key.der"
"$SDK/bin/monkeyc" -d edge1050 -f monkey.jungle -o bin/di2steps.prg -y "$KEY"
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

Split the app in two when deciding where to test something: the **arithmetic**
(teeth → ratio) is fully testable off the bike, the **position source**
(`Activity.Info`) is not testable at all off the bike.

### Unit tests (simulator) — covers all the ratio logic

`ratio()` takes gear positions as plain parameters, so the entire tooth-count
and ratio path can be tested without hardware. `source/GearConfigTest.mc` covers
CSV parsing, `sortDescending` normalisation, tooth-plausibility bounds, lookup
by position, ratio arithmetic, 2-decimal rounding, and null propagation.

```bash
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
KEY="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Certs/garmin_developer_key.der"
"$SDK/bin/monkeyc" -t -d edge1050 -f monkey.jungle -o bin/di2steps-test.prg -y "$KEY"
open "$SDK/bin/ConnectIQ.app"
"$SDK/bin/monkeydo" bin/di2steps-test.prg edge1050 -t
```

The simulator must already be running before `monkeydo`. 20 tests as of
2026-08-09, all passing.

### What the simulator CANNOT test

**`Activity.Info`'s derailleur fields have no simulated drivetrain**, so gear
positions read as never-sampled and the Ratio row stays `--` no matter what
teeth are configured. That means position tracking, the draw-time sampling fix
for the ~1s lag, and end-to-end ratio against real gears are **device-only**, on
the real Edge 1050 + bike.

Untried idea if that ever needs closing: play a recorded ride FIT (from
`/GARMIN/Activities`) back through the simulator and see whether Connect IQ
surfaces derailleur data from playback. Unverified — it may simply not populate.

Note `compute()` only runs while an activity is recording, so every value reads
`--` until you actually start one. That is expected, not a fault.

On-device procedure — set `DisplayMode = 2` (Test / Diagnostics), which renders:

```
Front Position = 1
Front Teeth = 47
Rear Position = 8
Rear Teeth = 17
Ratio = 2.76
```

(Real values from the 2026-08-10 road test, cross-checked against Garmin's
built-in "Rear cog position" field reading `8/11` on the same screen.)

Reading the position values, which is where the diagnostic value is:

| Shown | Meaning |
|---|---|
| `n/a` | The API doesn't expose derailleur fields on this device |
| `--` | No value: either not sampled yet, or the head unit reported nothing |
| a number | Live value |

During the 2026-08-09 probe those last two were rendered separately (`--` vs
`null`) because telling them apart was the whole question. That is settled, so
the screen now reads consistently. If a future symptom needs the distinction
back, it is a two-line change in `posOr`.

Teeth show `--` when unconfigured, and `Ratio` shows `--` unless both ends
resolve — never a fabricated `0.00`.

Set **Front Teeth** and **Rear Teeth** in settings before riding, or the ratio
row cannot compute. Shift through the full rear range and check the ratio moves
sensibly; also compare against Garmin's built-in "Rear cog position" field,
which is the reference for whether our position tracking is correct and
timely.

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
