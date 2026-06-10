# Real-World Findings

What we learned running FlashAir Sync against real hardware (Toshiba
FlashAir + Canon EOS REBEL T5i, 2026-05-29 → 2026-06-05) that the
protocol spec didn't predict. Read this before doing real-hardware
Android testing — it'll save you re-discovering every gotcha.

## The Toshiba camera DCIM layout

Real-card `/DCIM` listing on a Toshiba FlashAir card paired with a
Canon DSLR:

```
/DCIM/100__TSB/    ← photos live here  (Toshiba's own subdir convention)
/DCIM/EOSMISC/     ← 1 entry, Canon firmware leftover
/DCIM/MISC/        ← 0 entries
```

- The photos are under `100__TSB`, **not** `100CANON`. Code that
  hardcodes `100CANON` would miss everything. The walker logic in
  `FlashAirClient` is name-agnostic and walks every directory — but
  example comments in `android/.../MediaStoreWriter.kt` and
  `shared-spec/DEDUPE-STRATEGY.md` still reference `100CANON`. They're
  illustrative, not authoritative.
- The two sibling directories (`EOSMISC`, `MISC`) are Canon-firmware
  housekeeping and contain nothing the user wants. The walker should
  tolerate them without falling over.
- A listing showing "3 directories, 0 files" at `/DCIM` is correct,
  not a bug.

## Real-world throughput

170-file full-card sync, 2026-05-31, Toshiba FlashAir W-04 → iPhone 16
on iOS 26.5:

| Metric | Value |
|---|---|
| Files | 170 |
| Total bytes | 768.8 MB |
| Duration | 579.4 s (≈ 9 m 39 s) |
| Per-file average | ~3.41 s |
| Effective throughput | ~10.6 Mbps |
| Failures | 0 |

(An earlier estimate of 13.6 Mbps in older docs was off — that used a
6 MB average file size; the real average is 4.52 MB.)

The "first 30 seconds" of any sync are dominated by the Wi-Fi join +
the recursive `/DCIM` scan; per-file downloading hits the
~3.4 s/file steady state after that.

## URLSession's 30-second timeout matches the card

iOS's default `URLSessionConfiguration.timeoutIntervalForRequest` is
60s, but the Sentry HTTP breadcrumb showed our actual listing call
timing out at **30.5 s** when the card was off — which means
`FlashAirClient` has a 30s timeout configured somewhere (or iOS chose
to fail faster). Either way: **30s is a reasonable timeout floor for
FlashAir HTTP calls.** Android's OkHttp / `HttpURLConnection` should
use the same.

## Camera body sleep is a hard constraint

Real shoots surface this immediately. The camera body has its own
idle-sleep timer (Canon T5i: default 2 minutes). When it sleeps:

- The FlashAir card itself stays alive for some configurable window
  (`APPAUTOTIME`), but the **camera body powers down its Wi-Fi**.
- The card eventually drops Wi-Fi when its own timer fires.
- The sync can't proceed until the user wakes the camera (shutter
  half-press or any button).

**The card has no API to keep the camera body awake.** Neither
platform can solve this from the app side. User workarounds:

- Set camera power-save timeout to 15 min or "never" during shoots.
- Periodic shutter half-press during long syncs.

Document this in the app's beta release notes and any troubleshooting
guides.

## Wi-Fi join consent prompts every session (iOS; similar on Android)

`NEHotspotConfiguration.apply()` triggers iOS's
**"FlashAir Sync wants to join Wi-Fi 'flashair'"** confirmation alert
**every time** the call is made. We have a teardown step that calls
`removeConfiguration` after each sync (so the phone gets internet
back) — iOS treats every post-removal `apply()` as a fresh consent
event, hence the prompt repeats.

Android's `WifiNetworkSpecifier` shows a similar consent prompt per
session. Document the trade-off:

- **Keep the teardown** → prompt every sync, but the phone reliably
  returns to its normal Wi-Fi.
- **Drop the teardown** → no repeat prompt, but the phone is "stuck"
  on the FlashAir network until iOS auto-switches.

## The iOS "Connection Assistant" prompt during sync

Mid-sync, iOS sometimes pops a **"FlashAir has no internet, switch?"**
prompt. Tapping "Stay" keeps the sync going; tapping "Switch" breaks
it. The 170-file sync hit this prompt and survived (user kept hitting
Stay).

`UIRequiresPersistentWiFi` in Info.plist *may* suppress this — Apple's
docs are vague. Untested. Tracked as a TODO item.

## "Saved from FlashAir Sync" source attribution

When `PHAssetCreationRequest` saves a photo on iOS, the Photos.app
Info panel shows **"Saved from FlashAir Sync"** as the source —
automatic, no code required. Verified with `IMG_8027.JPG` on
2026-06-03.

**Android equivalent:** MediaStore's `RELATIVE_PATH` =
`Pictures/FlashAirImport/` provides similar grouping/discoverability
(`MediaStoreWriter.kt:62` already does this).

## Filename preservation matters for downstream (Immich, iCloud)

iOS bug found via Photos Info panel: the early code passed
`addResource(with: .photo, fileURL: tempFile, options: nil)`, where
`tempFile` is named with a UUID. PhotoKit then recorded the UUID as
the resource's `originalFilename`. The Photos info panel showed
`BB952DB9-DFB8-…` instead of `IMG_8027.JPG`.

**Fix:** pass `PHAssetResourceCreationOptions(originalFilename: entry.name)`.
The filename is preserved, syncs through iCloud, and is what
Immich/Google Photos/etc. uploaders read.

**Important nuance** — Immich dedupes by **content hash** (sha1 of
bytes), not filename. `addResource(with: .photo, fileURL:)` preserves
JPEG bytes verbatim, so the hash matches what you'd get from a direct
SD-card offload. **Filename is for human visibility; hash is what
prevents re-upload duplication.**

**Verified at scale on 2026-06-09:** the user pulled the SD card out
of the camera, plugged it into their laptop, and imported every JPG
directly into Immich. Immich detected **all 337 files as duplicates**
of photos already in the library — confirming the entire pipeline
(FlashAir → iOS download → `PHAssetCreationRequest` → Photos library →
iCloud sync → Immich's iOS uploader → server) preserves byte
identity. No re-encoding or transcoding happens at any link. The
"bridge for iCloud/Google Photos/Immich users" goal is proven.

**Android equivalent:** `ContentValues.put(MediaStore.MediaColumns.DISPLAY_NAME, entry.name)`
when inserting into MediaStore. Should already be doing this; verify.

## EXIF preservation is automatic

`PHAssetCreationRequest.addResource` with `.photo` does **not**
re-encode JPEGs. EXIF (camera body, lens, ISO, aperture, shutter,
GPS if present) flows through intact. Verified on 2026-06-03 photo:
Photos.app showed `Canon EOS REBEL T5i`, `EF-S18-55mm f3.5-5.6 IS STM`,
ISO 6400, f/5.6, 1/13s, all read directly from the file's EXIF.

This matters for downstream:

- iCloud Photo Library indexes EXIF for search.
- Google Photos categorizes by camera/lens.
- Immich shows camera/lens/exposure in its UI.

Android MediaStore retains EXIF if you write bytes verbatim — same
principle. **Don't re-encode.**

## `SyncIndex` grows monotonically across card rotations

Post-stress-test pull on 2026-05-31: **195 entries in the index**, of
which **170 were on the card** and **25 were stale** (from photos the
user had deleted from the camera between sessions). The index never
prunes.

For multi-year card-rotation users this becomes index bloat. Fix at
sync end: remove index entries whose path wasn't in the current
listing. Applies to both platforms.

## Debug workflow: USB-tether the phone for live console

iOS-specific but worth documenting since it cost us a real-time
debugging session before we figured it out.

`xcrun devicectl device process launch --console com.flashairsync`
over **USB tether** streams `print()` and `Logger` output live and
**survives the Wi-Fi handoff** when the app joins the FlashAir
network.

The same `--console` invocation over **Wi-Fi-paired** debugging dies
the moment `NEHotspotConfiguration.apply()` switches networks — the
debug tunnel runs over Wi-Fi and gets severed by the network switch.

For Android: **`adb logcat` over USB** has the same property and
should be preferred over Wi-Fi-debugging for real-hardware sessions.

## Toshiba SSID variants

The default FlashAir SSID is `flashair` but real cards often have
suffixes like `flashair_ABC123` (per the protocol spec) or completely
custom SSIDs the user has configured via the FlashAir config tool.
The app's Settings UI lets the user override SSID/passphrase/host —
treat the "default" values in code as a hint, not a hard expectation.

## Tailscale and other VPNs

The user's iPhone has Tailscale active. Worth confirming for any
other VPN-using beta tester: **Tailscale's split-route mode does
not divert private-IP traffic (192.168.0.1) into the tunnel**, so
the FlashAir sync works over the local Wi-Fi interface as expected.

VPNs configured with "all traffic" routing (e.g. some commercial
VPN apps with default-route override) would break this — the user
would need to disable the VPN before syncing or add a route
exception. Document for beta.

## See also

- `TODO.md` — items still to implement based on these findings
- `docs/PARITY.md` — iOS-Android cross-platform mirror checklist
- `docs/BETA-TESTING.md` — beta-distribution playbook
- `shared-spec/DEDUPE-STRATEGY.md` — protocol-level dedupe rationale
- `shared-spec/API.md` — HTTP API reference
