# Infrastructure & transient errors

Environment failures that are not code defects. Recorded so the same symptom
isn't re-diagnosed from scratch.

---

## Deploy reports success but the data field never appears on the Edge

**Seen:** 2026-07-31 through 2026-08-09. **Status:** RESOLVED (deploy.sh fixed).

### Symptom

`./deploy.sh` prints `Push complete.` and `✓ Pushed and verified`, the file is
visibly present in `/GARMIN/Apps`, and the Edge is restarted — but "Di2 STEPS"
never appears in the Connect IQ category of the data-screen editor. Restarting
repeatedly changes nothing.

### Root cause

`swiftmtp-cli push <deviceId> <storageId> <localPath> <remotePath>` treats
`<remotePath>` as the destination **directory**, and creates it if missing. It
places the file inside under its own basename.

`deploy.sh` passed the full remote *file* path (`/GARMIN/Apps/di2steps.prg`).
swiftmtp therefore created a **directory** with that name and wrote the real
build to `/GARMIN/Apps/di2steps.prg/di2steps.prg`. The Edge scans
`/GARMIN/Apps` for `.prg` **files**, found a directory, and skipped it.

The `push: 'di2steps.prg' already exists … Overwrite? [y/n]` prompt on every
redeploy was matching that directory, not a previous build.

### Why it went unnoticed for nine days

The verification step was `ls "$REMOTE_DIR" | grep -q di2steps.prg`. That
matches the stray directory perfectly, so every single deploy printed
`✓ Pushed and verified` while nothing was ever installed. **A name match in a
listing does not verify a deploy.** deploy.sh now compares the size field from
`ls` against the local file's byte count, and fails loudly if it finds `<DIR>`.

This also masked a genuinely separate problem — a failing USB-C data cable (see
below). Fixing the cable made transfers work and made the deploy look correct,
which is why the two faults took so long to separate. When a fix makes the
symptom change but not disappear, suspect a second cause.

### Recovery

The name must be freed before a real file can be written there:

```
swiftmtp-cli rm -r <deviceId> <storageId> /GARMIN/Apps/di2steps.prg
```

then redeploy. Confirm the result is a **file** of the expected size:

```
swiftmtp-cli ls <deviceId> <storageId> /GARMIN/Apps
            118268  2026-08-10T02:58:58.  di2steps.prg     <- correct
<DIR>            -  2026-07-31T17:39:50.  di2steps.prg     <- broken
```

---

## MTP push fails: `OpenSession failed: LIBUSB_ERROR_IO`

**First seen:** 2026-08-09, deploying di2steps 1.0.1 to the Edge 1050.
**Status:** RESOLVED — **the USB-C-to-C cable was not carrying data reliably.**
Swapping the cable fixed it outright: the next `./deploy.sh` succeeded on the
first attempt, with the post-push verification passing too.

**Check the cable first.** It cost roughly eight failed attempts and three wrong
theories to get there. The symptoms below all point at software or at the head
unit, and every one of them is also what a marginal cable looks like:
enumeration needs almost no throughput and succeeds, while opening a session and
pushing a 118 KB file needs sustained bulk transfer and fails. If MTP behaves
like this, try a known-good data cable before investigating anything else — and
note that other MTP clients (OpenMTP, the SwiftMTP GUI) failed identically,
which is itself the clearest signal that the problem is below the software.

### Symptom

`./deploy.sh` builds fine, discovers the device and storage, then fails at the
push:

```
FetchAvailableDevices: Found 1 devices on bus
FetchAvailableDevices: Detected device: 091e:5158 (0000d837e511)
OpenSession failed: LIBUSB_ERROR_IO; attempting reset
USB diag: device may be occupied by other processes, PID: 24775
Error initializing device: OpenSession after reset: unexpected data for code 0x1002
```

or, when it fails slightly later in the sequence:

```
fatal error LIBUSB_ERROR_IO; closing connection.
Error listing directory: LIBUSB_ERROR_IO
Error uploading: mtp: cannot run operation GetDeviceInfo, device is not open
Push failed.
```

### What is actually known

- **Enumeration succeeding tells you nothing.** `swiftmtp-cli devices` and
  `storages` both work — the device is on the bus at `091e:5158` and reports
  storage `65537` — while `OpenSession` still fails. Do not read a successful
  device/storage discovery as "the connection is fine."
- **It is intermittent, not total.** Across ~8 attempts in one session, exactly
  one operation succeeded (`swiftmtp-cli ls … /GARMIN/Apps`, which correctly
  listed the previously deployed `di2steps.prg`). Every other attempt failed
  identically. So the path does work; it just usually doesn't.
- **swiftmtp's built-in reset does not recover it.** It reports
  "attempting reset" and then fails on the post-reset `OpenSession`.
- **Short cooldowns are not enough.** An 8-second gap between attempts did not
  help. `deploy.sh` now waits 30s (`PUSH_COOLDOWN`) between push retries. With
  the root cause known, the cooldown is no longer the thing that saves a bad
  run — but it is still worth keeping for genuinely transient session refusals.

### Misleading diagnostics — do not chase these

**`USB diag: device may be occupied by other processes, PID: N` is noise.**
Across attempts it reported PIDs 24111, 18817, 24583, and 24775 — all different,
and none alive when checked with `ps -p`. One of them (18817) happened to be a
long-running Google Chrome, which led to Chrome being quit for nothing; the
failure was unchanged afterward. **Verify any reported PID with `ps -p <pid>`
before acting on it.** Most are stale or are swiftmtp's own prior invocations.

**`system_profiler SPUSBDataType` returning empty output is a sandbox artifact,
not a hardware fact.** Under the agent's sandboxed shell it produces nothing at
all. It is not usable as evidence that the device is absent.

**The sandbox is a real but partial factor.** The one successful operation was
run with the sandbox disabled — but other sandbox-disabled attempts failed too.
Disabling the sandbox appears necessary for raw USB access and is not
sufficient on its own.

### What to try, in order

1. **Swap the USB cable for a known-good data cable.** This was the actual fix.
   Many USB-C cables are charge-only or marginal for data; a cable that charges
   the Edge perfectly can still fail every bulk transfer.
2. Confirm the failure reproduces in a second MTP client (OpenMTP, SwiftMTP
   GUI). If *both* fail the same way, stop debugging the CLI — the problem is
   the cable, the port, or the device, in that order of likelihood.
3. Restart the Edge with it unplugged; reconnect once it has fully booted.
4. Keep the screen awake and unlocked for the whole transfer — the Edge drops
   MTP on screen sleep, which produces a similar error.
5. Confirm it is in MTP mode, not Garmin Basemap / mass-storage mode.
6. Minimise back-to-back sessions. Every `devices` / `storages` / `ls` call
   opens and closes its own session, and the device is least willing to open one
   immediately after the last closed.

### Related

`deploy.sh` retries the push up to 3 times with a 30s cooldown when it sees
`LIBUSB_ERROR_IO`, and treats a failed post-push verification `ls` as
"unverified" rather than as a failed deploy — a second session opened
immediately after a successful push is the most likely of all to be refused.
