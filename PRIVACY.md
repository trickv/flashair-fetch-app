# Privacy Policy

_Last updated: September 23, 2026_

FlashAir Sync ("the app") is an open source iOS app that copies photos
and videos from a Toshiba FlashAir Wi-Fi SD card into your device's
Photos library. This document describes what the app does and does not
do with your data.

It is written to be accurate rather than flattering: the app **does**
send crash and diagnostic reports to a third-party service by default,
and this document says exactly what those contain.

## Summary

- **No accounts.** There is no sign up, no login, and the app never
  asks for your name or email. It does not know who you are. There is
  one identifier: while diagnostics are enabled, the Sentry SDK
  generates a random installation ID — a UUID it stores in the app's
  own cache storage on your device — and attaches it to every report
  it sends, so that several reports from the same installation can be
  recognised as related. It is not derived from you or your device, it
  is not the advertising identifier, it is not used to track you, it
  is never shared beyond the diagnostics processor named below, and it
  is deleted along with the app when you remove it.
- **No advertising.** The app contains no ads and no advertising SDKs.
- **No tracking.** Nothing the app collects is used to track you across
  apps or websites, and no advertising identifier is read.
- **No data sale or sharing** beyond the single diagnostics processor
  named below.
- **Your photos stay yours.** Photo and video content is transferred
  from the SD card to your device and saved to your Photos library.
  Photo content is never uploaded anywhere by this app.
- **Diagnostics are on by default and can be turned off** at
  **Settings → Privacy** inside the app. See "Diagnostics and crash
  reporting" below for exactly what is sent.
- **Source available.** The full source code is published at
  https://github.com/trickv/flashair-fetch-app and you can verify these
  claims.

## What the app accesses

### Your Photos library (add only)

The app requests **add-only** access to your Photos library
(`NSPhotoLibraryAddUsageDescription`). It uses that access solely to
write the files it downloaded from the SD card, preserving the original
filename and the file's embedded EXIF metadata.

The app does **not** read, enumerate, browse, modify, or delete the
photos already in your library, and has no code path that does so.

### Wi-Fi

To reach the card, the app asks iOS to join the SD card's own Wi-Fi
access point (`NEHotspotConfiguration`, gated by the
`com.apple.developer.networking.HotspotConfiguration` entitlement). iOS
shows you a system prompt before this happens and you can decline.

The app joins exactly the one network you configured, for the duration
of the transfer, and asks iOS to forget it again when the sync finishes
or fails. It does not scan for, enumerate, or record the other networks
around you, and it does not read the SSID of the network you were on
before.

### Local network

The SD card runs a small HTTP server (typically at `192.168.0.1`) on its
own access point. The app talks to that server over plain HTTP to list
directories and download files. The card's firmware is HTTP-only and
cannot be updated to support TLS, which is why the app declares
`NSAllowsLocalNetworking` in its App Transport Security configuration.
That exception applies to local addresses only; no internet host is
contacted over cleartext.

### On-device storage

- **Sync index.** So that a repeated sync does not re-download files you
  already have, the app stores a small JSON index in its own app
  container (`Documents/FlashAirSync/sync_index_<network>.json`). It
  contains file paths and byte sizes as reported by the card — no photo
  content. It never leaves your device and is removed when you delete
  the app. You can clear it from **Settings**.
- **Settings.** Your network name, passphrase, card address and
  preferences are stored in the app's own preferences store on your
  device. The passphrase never leaves the device. The network name and
  card address do appear in diagnostic reports when those are enabled —
  see "Filenames, card address and network name" below.
- **In-app log.** The app keeps the most recent ~1000 log lines in
  memory for troubleshooting. These lines can include the filenames and
  card paths of files being transferred. They are shown only inside the
  app and are transmitted only if you explicitly export/share them, or
  as described below.

## Diagnostics and crash reporting

The app sends crash reports and diagnostic events to **Sentry**
(https://sentry.io), a third-party error-monitoring service, which
processes them on our behalf. Sentry's own privacy policy is at
https://sentry.io/privacy/.

**This is enabled by default.** You can turn it off at any time at
**Settings → Privacy** inside the app; when it is off, the SDK is shut
down and nothing is sent.

### What is sent when diagnostics are enabled

- **Crash reports and app-hang reports** — stack traces, the app
  version and build, the iOS version and device model.
- **Error events** — when a sync fails, including per-file download
  failures.
- **Performance traces** for a 20% sample of operations — timings only.
- **Breadcrumbs** — the app's own recent log lines, attached as context
  to an error.
- **One aggregate `sync_completed` event per finished sync** —
  counts of files found / imported / already-synced / skipped / failed,
  total bytes, duration and throughput. Numbers only.
- **A random installation ID** — the UUID described in the Summary,
  attached automatically by the SDK to every event it sends. It is not
  something the app sets or can suppress independently of turning
  diagnostics off entirely.

### Filenames, card address and network name

**Filenames and card paths can be included in error reports.** When an
individual file fails to download, the app records which file it was
(for example `IMG_1234.JPG` and its path on the card) so that a bug
report is actionable. Filenames also appear in the breadcrumb log lines
attached to errors.

**The card's address and the Wi-Fi network name are also included in
error reports.** The address you have the app pointed at (for example
`192.168.0.1`) is attached to sync failures, and the name of the
network the app joined appears in the breadcrumb log lines that travel
with an error — a connection failure is not diagnosable without them.

**Your Wi-Fi passphrase is never sent.** It is stored on your device
and handed only to iOS, to join the card's access point. It is not
logged, not written to the breadcrumb trail, and not attached to any
report.

**Photo and video content is never sent.** Only the name and the
expected byte size travel with an error report.

### What is deliberately not sent

- No photo or video content, ever.
- No screenshots and no view-hierarchy capture — both are explicitly
  disabled, because a screenshot of this app could contain your photos.
- No session replay — explicitly disabled.
- No name, email, contacts, calendar, files outside the app, or
  advertising identifier. Sentry's "default PII" collection is
  explicitly disabled. Note that this setting does **not** cover the
  random installation ID above — that one is attached by the SDK
  regardless, and turning diagnostics off is what stops it.
- No precise location. Note that, as with any internet request, Sentry's
  servers can see the IP address your device connects from and may
  derive an approximate (city-level) location from it. It is not used to
  identify you and the app does not request location permission.

### Retention

Events are retained by Sentry for a limited period under this project's
retention settings and are then deleted automatically. If you want an
event removed sooner, open an issue (see Contact) and it will be
deleted on request.

## What the app does not do

- The app does not collect, store, or transmit your name, email, phone
  number, contacts, precise location, or files outside its own
  container.
- The app does not read your existing photo library.
- The app does not upload your photos or videos anywhere.
- The app contains no advertising SDKs and no cross-app tracking.
- The app does not require an account and has no server of its own.

## Children

The app is a general-purpose photo utility, is not directed at children,
and does not knowingly collect personal information from anyone,
including children.

## Changes to this policy

Any changes will be published to this same document in the project
repository. The "Last updated" date at the top reflects the most recent
change.

## Contact

For questions about this privacy policy or the app, open an issue at
https://github.com/trickv/flashair-fetch-app/issues.

---

FlashAir is a trademark of Kioxia Corporation (formerly Toshiba Memory
Corporation). This app is an independent open-source project and is not
affiliated with, endorsed by, or sponsored by Kioxia or Toshiba.
