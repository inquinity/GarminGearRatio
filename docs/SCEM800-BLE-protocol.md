# Shimano SC-EM800 BLE Protocol — Reverse-Engineered Reference

Status: **Validated** (Path A complete, 2026-07-29)
Device tested: SC-EM800 head unit, advertised as "SCEM800 73A"
Tooling: nRF Connect for Mobile (iOS), CSV log export (`SCEM800_73A.csv`)

> **Scope note (2026-08-09).** The wire format below is unchanged and still
> correct. What changed is why you'd use it. The Edge 1050 decodes STEPS **gear
> position** on its own and hands it to any data field via
> `Activity.Info.rearDerailleurIndex`/`Max` and the front equivalents — no BLE,
> no ANT, no permission. So this protocol is not the only route to gear
> position, and is likely no longer the preferred one. Its unique value is the
> **assist/motor** data: assist mode, assist level, cadence, speed, rider
> profile name. Treat the `0x00` gear packet documented here as a cross-check
> against `Activity.Info` rather than as the primary source. See `CLAUDE.md`
> § Data sources.

## Device Identification

| Field | Value |
|---|---|
| Advertised name | `SCEM800 73A` |
| Manufacturer Data | Shimano Inc., company ID `0x044A` (1098 decimal) |
| Manufacturer Name String (0x2A29) | `SHIMANO` |
| Serial Number String (0x2A25) | `7H9XEM0173A` |
| Firmware Revision String (0x2A26) | `4.9.0.0` |

## Services

| Service UUID | Short UUID | Notes |
|---|---|---|
| `000018FF-5348-494D-414E-4F5F424C4500` | `0x18FF` | Advertised. Contains characteristics `2AF3`–`2AFF`. Not used for gear/mode data (per `markdotai/emtb` source, purpose unconfirmed for this range). |
| `000018EF-5348-494D-414E-4F5F424C4500` | `0x18EF` | Advertised. **This is the one that matters.** Matches `modeServiceUuid` in `markdotai/emtb`. Contains `2AC0`–`2AC5`. |
| `000018FE-1212-EFDE-1523-785FEABCD123` | — | Present, not investigated. |
| Battery Service (`0x180F`) | — | Standard GATT battery service, present. |
| Device Information (`0x180A`) | — | Standard GATT device info (manufacturer/serial/firmware strings above). |

All custom Shimano UUIDs use the 128-bit base `5348-494D-414E-4F5F-424C4500`, which decodes as ASCII **"SHIMANO_BLE\0"**.

## Key Characteristic: `00002AC1-5348-494D-414E-4F5F424C4500`

- Service: `0x18EF`
- Property: **Notify**
- Matches `modeCharacteristicUuid` in `markdotai/emtb` exactly.
- **This single characteristic is multiplexed** — it carries at least 7 distinct sub-message types, distinguished by a **leading type-tag byte** on each notification payload. Payload length is fixed per type.

### Observed sub-message types (all from `2AC1`)

| Type tag (byte 0) | Payload length | Contents |
|---|---|---|
| `0x00` | 18 bytes | **Gear position** (see below) |
| `0x01` | 20 bytes | Unknown — not decoded |
| `0x02` | 10 bytes | **Assist mode** + motion/rotation counters (see below) |
| `0x03` | 19 bytes | Wheel/distance counters (continuously incrementing, duplicated fields) — not gear-related |
| `0x04` | 3 bytes | Unknown — not decoded |
| `0x05` | 13 bytes | ASCII rider profile name, e.g. `"Profile1"`, `"Profile2"` |
| `0x06` | 6 bytes | Unknown — not decoded |

Any parser reading this characteristic **must branch on byte 0** and ignore/skip types it doesn't need.

## Gear Position — Type `0x00` (18 bytes)

```
Byte:   0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17
Idle:   00 00 03 FF FF 07 0B 80 80 80 F7 EE 12 FF FF 0C 00 07
Gear7:  00 00 03 FF FF 07 0B 80 80 80 F7 EE 12 FF FF 0C 00 07
```

- **Byte 5 = current gear.** Direct 1:1 hex-to-decimal encoding, no offset/scaling.
- **Byte 6 = max gear (cassette size).** Observed constant `0x0B` (11) throughout — confirms an 11-speed rear cassette. Useful as a sanity check / for supporting other cassette sizes generically.
- Bytes 0–4 and 7–17 observed constant in all captures; purpose unconfirmed (likely padding, checksum, or unused fields for this device class).

### Validated gear byte values (directly observed in capture log)

| Gear | Byte 5 (hex) |
|---|---|
| 1 | `01` |
| 2 | `02` |
| 3 | `03` |
| 4 | `04` |
| 5 | `05` |
| 6 | `06` |
| 7 | `07` |
| 8 | `08` |
| 9 | `09` |
| 10 | `0A` |
| 11 | `0B` |

Confirmed via two capture passes: a paused/deliberate 1→2→3 sequence, and a rapid 3→11 sequence, plus a 10→6 downshift. Full 1–11 range covered with no gaps.

### Byte-level cross-device comparison (SC-EM800 vs emtb's E7000/EN100 example)

emtb's source comment gives a literal example gear packet from E7000/EN100: `00 00 00 FF FF YY 0B 80 80 80 0C F0 10 FF FF 0A 00` (17 bytes, `YY`=gear at index 5). Aligned against our own SC-EM800 sample:

```
idx:     0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17
SC-EM800 00 00 03 FF FF 07 0B 80 80 80 F7 EE 12 FF FF 0C 00 07
E7000    00 00 00 FF FF YY 0B 80 80 80 0C F0 10 FF FF 0A 00  (17 bytes, no idx 17)
```

Indices 0,1,3,4,6,7,8,9,13,14,16 match exactly across both devices. Index 6 (`0B`) matching on both is a second independent confirmation it's the max-gear/cassette-size field. Indices 2, 10, 11, 12, 15 differ (device-specific constants — possibly serial-derived, checksum, or hardware-revision bytes), and SC-EM800 carries one extra trailing byte (idx 17) that E7000 doesn't have. None of the differing bytes affect the gear read at index 5.

## Assist Mode — Type `0x02` (10 bytes)

```
Byte:    0  1  2  3  4  5  6  7  8  9
Idle:    02 00 00 00 00 00 E1 0A 00 00
Eco:     02 01 F0 00 00 00 E3 0A 00 00
Boost:   02 03 E4 00 00 00 E3 0A 00 00
```

- **Byte 1 = assist mode.**

| Value | Mode |
|---|---|
| `0x00` | Off |
| `0x01` | Eco |
| `0x02` | Trail *(not directly captured ourselves — SC-EM800 sample jumped 01→03 between two quick button presses — but confirmed by emtb source comment, see below)* |
| `0x03` | Boost |
| `0x04` | Walk *(from emtb source comment only — not observed on SC-EM800 at all; SC-EM800 may not support a walk-assist mode, or it may live elsewhere)* |

Source for the full list: emtb developer's own code comment in `emtbDelegate.mc`: `// Mode is 00=off 01=eco 02=trail 03=boost 04=walk`. This should be treated as reliable (it's the developer's working notes, not a guess) but the `04=Walk` value is unverified against SC-EM800 specifically — worth confirming if the bike has a walk-assist button/mode.

- **Byte 2:** Highly variable, large-range value (0x00–0xFF observed). Behaves like a continuous sawtooth — believed to be a crank/wheel rotation phase or cadence-related counter, **not** gear-related. Ruled out as gear field after full-session analysis.
- **Bytes 6–7 (little-endian 16-bit):** Slow-incrementing counter (e.g. `0x0AE1` → `0x0AE2` → `0x0AE3`), increments roughly in sync with byte-2 wraparounds. Likely a coarse distance/revolution counter. Not further decoded.
- Bytes 3–5, 8–9: mostly `0x00` at idle; byte 3 and 5 show transient activity during active pedaling — not decoded.

## Type `0x05` — Rider Profile (13 bytes)

Contains ASCII text, e.g.:
```
05 05 00 50 72 6F 66 69 6C 65 31 00 00   → "Profile1"
05 06 00 50 72 6F 66 69 6C 65 32 00 00   → "Profile2"
```
Byte 1 appears to be a profile index/ID. Not further investigated — noted for completeness in case rider-profile switching is relevant later.

## Open Items / Not Yet Decoded

- Type `0x01` (20 bytes), `0x04` (3 bytes), `0x06` (6 bytes) — contents unknown.
- Type `0x03` (19 bytes) — confirmed to be wheel/distance-related counters (continuously incrementing, duplicate fields at bytes 1-2 and 5-6), not further decoded.
- Bytes 0–4, 7–17 of the type-`0x00` gear packet — likely padding/reserved/checksum, unconfirmed.
- Battery percentage — not yet isolated (likely via standard Battery Service `0x180F` / `0x2A19`, per `emtb`'s `batteryServiceUuid`/`batteryCharacteristicUuid`, not yet cross-checked against this device's actual readings).

## Source Cross-Reference

- `markdotai/emtb` — https://github.com/markdotai/emtb — confirmed exact UUID match on `0x18EF` service / `2AC1` characteristic.
- Raw capture source: `SCEM800_73A.csv` (nRF Connect for Mobile Log export, iOS), captured 2026-07-29.
- **Correction (2026-07-29):** an earlier pass at this doc said emtb "does not appear to read the type `0x00` (gear) packet." That was wrong — emtb's `onCharacteristicChanged` branches on **payload size**, not an explicit type-tag check, and it does read a gear packet. See below.

### emtb's actual parsing logic (`emtbDelegate.mc`, `onCharacteristicChanged`)

```monkeyc
function onCharacteristicChanged(characteristic, value)
{
	if (characteristic.getUuid().equals(modeCharacteristicUuid))
	{
		if (value!=null)
		{
			// value is a byte array
			if (value.size()==10)	// we want the one which is 10 bytes long (out of the 3 that Shimano seem to spam ...)
			{
				// mode
				mainView.values[3] = value[1].toNumber();	// and it is the 2nd byte of the array
				// cadence
				mainView.values[7] = value[5].toNumber();
				// assistance level
				mainView.values[8] = value[4].toNumber();
				// speed
				mainView.values[9] = ((value[3] << 8) | value[2]).toFloat()/10;
			}
			else if (value.size()==17)
			{
				// gear
				mainView.values[6] = value[5].toNumber();
			}
		}
	}
}
```

**This independently confirms our own byte offsets**, found via completely separate hardware (E7000/EN100 vs our SC-EM800) and a completely separate reverse-engineering pass:

| Field | emtb (E7000/EN100) | Us (SC-EM800) | Agreement |
|---|---|---|---|
| Gear packet total size | 17 bytes | 18 bytes | Off by one — SC-EM800 carries one extra byte, see below |
| Gear byte index | `value[5]` | byte 5 | **Exact match** |
| Mode packet size | 10 bytes | 10 bytes | Exact match |
| Mode byte index | `value[1]` | byte 1 | **Exact match** |

The 1-byte size difference on the gear packet (17 vs 18) is consistent with our own finding that **byte 6 = max gear (`0x0B`/11)** — a field that may simply not exist, or exists at a different position, on the E7000/EN100 hardware emtb targeted. Bytes 0–5 line up exactly between both devices; the extra byte is additive at/after index 6, not a shift of the whole layout.

### New fields revealed by emtb's code (not yet independently verified against SC-EM800 captures)

The 10-byte "mode" packet apparently carries more than just assist mode — emtb reads four separate fields out of it:

| emtb field | Byte(s) | Formula | Status against our data |
|---|---|---|---|
| **Mode** | `value[1]` | direct | Confirmed — matches our assist-mode byte exactly (`00`=Off, `01`=Eco, `03`=Boost observed) |
| **Speed** | `value[2]`, `value[3]` | `((value[3]<<8) \| value[2]) / 10.0` | Not yet cross-checked, but this **retroactively explains** our own protocol doc's earlier note that byte 2 was "a continuous sawtooth... believed to be a crank/wheel rotation phase" — that byte-2 sawtooth is almost certainly **speed**, not rotation phase. Should be re-labeled once confirmed. |
| **Assistance level** | `value[4]` | direct | Distinct from "mode." In our full-session capture this byte was `00` throughout — plausibly because we did little/no loaded pedaling (assistance level may represent real-time motor output/torque contribution, which would be near-zero coasting on a stand). Needs a capture with actual pedaling resistance to validate. |
| **Cadence** | `value[5]` | direct | Our protocol doc already flagged byte 5 (of the *10-byte* packet — do not confuse with byte 5 of the *18-byte gear* packet, different packet type) as showing "transient activity during active pedaling," consistent with cadence. Not yet numerically validated against a known RPM. |

**Action item for a future capture session:** repeat Path A specifically to validate speed (`value[2]/[3]`), assistance level (`value[4]`), and cadence (`value[5]`) against known ground truth (e.g., ride at a steady, known cadence and compare).
