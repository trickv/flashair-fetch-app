# TODO

Version-controlled backlog of deferred work, factored out of the
narrative deferred-cleanups lists in `CLAUDE.md` and `DEVELOPMENT.md`.
Treat this file as the at-a-glance checklist; the richer per-item
context (why something matters, which session surfaced it) lives in
the prose docs.

Effort markers: **S** ≈ < 1 hour, single-file · **M** ≈ a few hours,
multi-file or some research · **L** ≈ substantial, may span sessions.

---

## iOS — Pending verification

- [ ] **Verify the "Already synced: N files" line in the Import Complete
      alert.** Commit `861582b` added the field; the build is installed
      on `trickyiphone16` but no one has tapped Sync against the card
      with the new code path yet. _Effort: S (just a tap)._

## iOS — UX improvements

- [ ] **Auto-scroll the import list to the active row.** For 100+ file
      runs the live download row scrolls off-screen as completed rows
      pile up; you have to manually scroll to follow progress. Plan:
      wrap the `ScrollView` in `ScrollViewReader` + reverse the list so
      pending is at the bottom and the active row sits at the top.
      _Effort: S._
- [ ] **Last-imported thumbnail preview.** Show a small thumbnail of the
      most-recently-saved photo in the progress UI so the photographer
      can glance at the phone mid-shoot and see what just came across.
      Plan: keep the last `PHAsset`'s localIdentifier in the VM, load a
      thumbnail via `PHImageManager.requestImage(for:targetSize:…)` at
      a small size (e.g. 64pt), display it in a corner of `progressSection`.
      Surfaced from real-world photo-shoot use on 2026-06-03. _Effort: M._
- [ ] **Dedicated "FlashAir" album in Photos.** iOS analog of Android's
      `Pictures/FlashAirImport/`. Currently imports save into the main
      Photos Library at their FAT capture date — you can find them via
      Albums → Recently Added or the "Saved from FlashAir Sync" attribution,
      but there's no grouping. Plan: in `PhotoSaver.saveToPhotos`, fetch
      or create a `PHAssetCollection` titled "FlashAir" and add the new
      asset's placeholder to it inside the same `performChanges` block.
      _Effort: S._
- [ ] **Import footer indicator** for mock-vs-real mode + git commit hash.
      Android UI surfaces both; iOS footer just shows SSID/Host. Will need
      a small build phase to plumb the git short-hash into a Swift constant
      (Android does this via `resValue` for `R.string.git_commit_id`).
      _Effort: S._

## iOS — Feature: Live shooting mode

- [ ] **"Live shooting mode" toggle.** After an initial sync, instead of
      tearing down the Wi-Fi, keep it joined and poll `walkDirectory` every
      ~2 seconds. When new files appear, sync them immediately. Toggle in
      Settings or a button on the main screen ("Stay Connected"). Useful
      during active photo shoots — you press the shutter, the photo lands
      on the phone seconds later. Power-intensive (radio + repeated HTTP),
      so should auto-exit after N minutes of no activity or on user tap.
      Surfaced from real-world use on 2026-06-03. Concerns: depends on the
      backgrounding fix below if the user wants to keep the phone screen-
      locked during the shoot. _Effort: M–L._

## iOS — Index hygiene

- [ ] **Prune stale entries from `SyncIndex` at sync end.** Files deleted
      on the camera stay in the index forever. The 2026-05-31 pull showed
      195 entries = 170 currently-on-card + 25 stale from photos that
      had been deleted on the camera between sessions. For a multi-year
      card-rotation user this becomes index bloat. Cheap fix at sync end:
      remove index entries whose path wasn't seen in the current listing.
      _Effort: S._
- [ ] **Move `SyncIndex` from `Documents/` to `Application Support/`.**
      It's currently user-visible in Files.app, which is leaky for an
      internal cache. Needs a one-time migration on app launch that
      copies any existing JSON from the old location to the new before
      removing the old. _Effort: S._

## iOS — M3 (resilience)

- [ ] **Backgrounding kills long syncs.** If the app loses foreground
      mid-sync (user switches apps, screen lock, memory pressure), the
      `URLSession` downloads stall and the `NEHotspotConfiguration` Wi-Fi
      link can drop. Real-hardware syncs of a full card take 10+ minutes,
      so this is a real risk. Confirmed in-the-field on 2026-06-03: user
      wants to be able to lock the screen during long shoots, currently
      has to keep the screen on for the entire sync.

      **Before implementing — feasibility deep-dive (added 2026-06-03).**
      The plan below is "likely fix," not validated. Do an in-depth review
      first to confirm there's no simpler workaround we're missing:
      - Read Apple's actual `UIRequiresPersistentWiFi` semantics under
        screen lock (docs are vague — does it actually keep Wi-Fi alive
        when locked, or only when active in foreground?).
      - Test what really happens to a background `URLSession` + an active
        `NEHotspotConfiguration` when the screen locks on the FlashAir
        network specifically.
      - Scan for any newer iOS 17/18/26 APIs that might apply (e.g. has
        BackgroundTasks framework grown anything relevant?).
      - Search for third-party reports of comparable app patterns —
        camera importers, scientific instrument apps, IoT setup flows.
      - Goal: either find a cheaper workaround, or confirm the multi-
        pronged fix below is genuinely the right path.

      Likely fix (post-deep-dive), a combination of:
      1. Switch downloads to `URLSessionConfiguration.background(withIdentifier:)`
         so the system can resume them across suspensions.
      2. Set `UIRequiresPersistentWiFi` in `Info.plist` (via `project.yml`
         `info.properties`) to keep the radio active in foreground and
         signal Wi-Fi-dependence to iOS power management.
      3. At minimum, a coachmark warning the user to keep the app open.

      iOS analog of Android's planned `ImportService` foreground-service.
      _Effort: L (including the feasibility deep-dive)._
- [ ] **iOS Connection Assistant prompt mid-sync** ("flashair has no
      internet, switch?"). Surfaced during the 2026-05-31 170-file run;
      user has to tap Stay or the sync breaks. Evaluate whether
      `UIRequiresPersistentWiFi` (above) suppresses it; if not, an in-app
      coachmark is the floor. _Effort: S–M (depends on Apple behavior)._
- [ ] **Retry-with-backoff on transient timeouts.** The 2026-05-29 session
      showed four attempts in a row timing out because the FlashAir card
      had powered down between shots; each required a manual re-tap of
      Sync. The first listing-level timeout should trigger an exponential
      backoff retry rather than failing the whole sync. _Effort: M._
- [ ] **Retry on Wi-Fi-not-found with coachmark.** When the SSID isn't
      broadcasting (camera off / sleeping), don't error out immediately —
      sit in a retry loop with a friendly message like "Looking for
      FlashAir… please power on your camera." Today the failure surfaces as
      a generic red error banner. Surfaced from real-world use on
      2026-06-03. _Effort: S–M, overlaps with retry-with-backoff above._
- [ ] **Reduce the every-sync hotspot-join consent prompt.** iOS re-prompts
      on every `NEHotspotConfiguration.apply()` because we explicitly
      `removeConfiguration` during teardown. Three options to evaluate:
      (a) drop the teardown and accept that the phone stays on the
      no-internet network until iOS auto-switches; (b) switch
      `joinOnce = true` and let iOS auto-remove on disconnect; (c) keep
      current behavior. Needs hands-on testing — Apple's prompt behavior
      varies by iOS version. _Effort: S (test) + S (implement chosen path)._
- [ ] **Wire up the existing Cancel button.** The `Cancel` button shows
      mid-sync but `SyncEngine.cancel()` is never called from the running
      download loop. `isCancelled` checks already exist in `sync()` — just
      need the UI button to call into the actor. _Effort: S._

## iOS — Observability

- [x] **Wire up Sentry for crash + error + usage telemetry.** ✅ Done
      2026-06-03 (`022f95e`). Sentry Cocoa SDK 9.16.1 via SPM, opt-in
      via Settings → Privacy (default off). `Utils/Telemetry.swift`
      wrapper isolates the rest of the app from the SDK. `Logger.shared`
      bridges to breadcrumbs; `ImportViewModel`'s catch path captures
      `FlashAirError.*`; success path emits a `sync_completed` event with
      aggregate-only metrics (no filenames, no photo content). Privacy
      hardening: no Session Replay, no screenshot/view-hierarchy
      attachments, `sendDefaultPii = false`, no profiling. DSN lives in
      `Info.plist` via `project.yml` info.properties (public per Sentry
      docs — safe to commit).

## iOS — Code quality / testing

- [ ] **`FlashAirClient.downloadFile` has a declared-but-unused `progress:`
      callback.** Hook it up to `URLSession`'s data-task progress so the
      per-file progress UI advances during the download (currently jumps
      0% → 100%). _Effort: S._
- [ ] **Swift FAT decode lacks the range validation the Kotlin side has.**
      `decodeFATDateTime` in `Models.swift` happily accepts month=15 etc.;
      Kotlin's `decodeFATDateTime` returns null for out-of-range fields.
      Mirror the validation. _Effort: S._
- [ ] **`CSVParserTests` are vacuous `XCTAssertTrue(true)` stubs.**
      Root cause: `parseCSV` is private in `FlashAirClient`. Bump to
      `internal` + add `@testable import` in the test file, then write
      real CSV parsing assertions (6-field and 5-field formats). _Effort: S._

## Android

- [ ] **Validate M2 end-to-end on the emulator against the mock server.**
      The full Android M2 stack (`WiFiConnector`, `MediaStoreWriter`,
      `SyncEngine`, progress UI) is merged on `main` and builds + unit
      tests pass on CI, but **only the M1 listing path has actually been
      run** on the emulator. _Effort: M._
- [ ] **Fix the `op=104` mock-server regression** so CI goes green.
      `tools/mock-flashair/test_server.py` config-endpoint assertion has
      been failing since M2's edits to `server.py`. Android build/test
      are unaffected — this is a mock-only regression. _Effort: S._
- [ ] After mock validation: real-hardware validation (parallel to iOS
      2026-05-29 milestone), then mirror iOS M3 work.

---

## Recommended next slices

No urgency on any of this; today's main branch is a clean milestone.
When you're ready to pick something up, my "best ratio of payoff to
effort" recommendations:

1. **Trio of S-effort items in one build cycle:** "Already synced" verify
   + auto-scroll the import list + index pruning. Fixes the three rough
   edges that surfaced during the 170-file run. ~30 min of code + one
   `xcodebuild` + `devicectl install`.
2. **FlashAir album** as a standalone follow-up — discoverability win
   that doesn't fit naturally into the trio above.
3. **M3 backgrounding** (the L-effort item) is the right next big swing,
   because it unlocks day-to-day usability — you wouldn't have to
   babysit the app for 10 minutes during a full-card sync.
