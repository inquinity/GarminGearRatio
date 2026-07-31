# di2steps — Connect IQ data field for Shimano STEPS (SC-EM800)

Reads the SC-EM800's shifting/assist data over **BLE** (Shimano `0x18EF` service,
`2AC1` notify characteristic, multiplexed by a leading type-tag byte) and renders
it as a Garmin data field. Sibling to **GearRatio** (`../GarminGearRatio`), which
reads the same class of data over ANT+ Di2; this app is for bikes where the Di2
stream is not exposed but the STEPS BLE stream is.

- **Wire format (source of truth):** `docs/SCEM800-BLE-protocol.md`
- **Architecture / plan:** `~/.claude/plans/we-are-creating-a-polymorphic-quail.md`
- **BLE reference impl (kept out of this repo):** `markdotai/emtb` cloned at
  `/Users/robert/dev/oss/emtb` — `source/emtbDelegate.mc` is the proven BLE
  state machine our `ShimanoBleDelegate.mc` is ported from.

## App type & structure

Single `type="datafield"` app, `edge1050`, permission `BluetoothLowEnergy`. One
BLE connection owned by the field; "pages" are **display modes** chosen via the
`DisplayMode` setting (0=Ride, 1=Gear Config, 2=Test), not button navigation.

- `source/Di2StepsApp.mc` — AppBase; wires up the view + BLE.
- `source/Di2StepsView.mc` — DataField; `onUpdate` dispatches on `DisplayMode`.
- `source/ShimanoBleDelegate.mc` — BLE central: scan/pair/identify-by-MAC/notify.
- `source/StepsData.mc` — decoded state + raw-packet capture for the Test screen.

## Build & run

SDK: `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`
Dev key: `/Users/robert/Certs/garmin_developer_key.der`
Deployment tool: **SwiftMTP** (`github.com/Neighbor-Z/SwiftMTP`) — CLI for MTP file transfer to Garmin devices

### Simulator workflow
```bash
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
"$SDK/bin/monkeyc" -d edge1050 -f monkey.jungle -o bin/di2steps.prg -y /Users/robert/Certs/garmin_developer_key.der
open "$SDK/bin/ConnectIQ.app"           # launch simulator
"$SDK/bin/monkeydo" bin/di2steps.prg edge1050
```

### Device deployment
After building the `.prg` file, transfer to Edge 1050 via SwiftMTP:
```bash
swiftmtp push bin/di2steps.prg /GARMIN/Apps
```
Then restart the Edge 1050 to load the data field.

**Note:** BLE cannot be exercised in the simulator (it stays on "BLE init..."/
"Scanning..."). Live gear/mode data must be validated on the real Edge 1050 + bike.

Type checking is strict (as in GearRatio): BLE iterators return `Object`, so cast
results to `Ble.Device` / `Ble.ScanResult` when calling their methods.

# git
Use git commits instead of PRs
Keep commits atomic: small and focused on a single change
Use short commit messages (1-3 lines); if there is a need for a more extensive message, ask before continuing.
