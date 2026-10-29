# App Store Release

How FlashAir Sync gets from this repo to TestFlight and then to the App
Store, under Apple team **99CP4GY776** — the same team as
`../baby-monitor` and `../look-up`.

This assumes you have shipped those two and know the shape of a fastlane
+ GitHub Actions release. Everything below is either *different for this
app* or a thing you would otherwise rediscover the hard way. No Apple 101.

---

## The automation boundary — read this first

**The pipeline stops at TestFlight. Nothing in this repo ever submits to
App Review.** That is deliberate: submission is a one-way door with
metadata attached, and it stays a human decision in App Store Connect.

| Thing | Who does it |
|---|---|
| Generate `FlashAirSync.xcodeproj` from `project.yml` | **Automated** — the release workflow installs XcodeGen and runs `xcodegen generate` |
| Set marketing version | **Automated** — from the git tag (`v0.1.0` → `0.1.0`) |
| Set build number | **Automated** — from `GITHUB_RUN_NUMBER` |
| Import cert, install provisioning profile | **Automated** — `release.yml` steps "Import distribution certificate" and "Install provisioning profile". *Not* fastlane; look there when signing setup breaks |
| Flip the generated project to manual code signing | **Automated** — `fastlane ios beta` (`update_code_signing_settings`) |
| Archive + export `.ipa` | **Automated** |
| Upload to TestFlight | **Automated** |
| Attach `.ipa` + dSYMs to the GitHub Release | **Automated** |
| PR-time unsigned build + unit tests | **Automated** — `.github/workflows/ios-build.yml`, paths-filtered to `ios/**`. Note it reports **skipped**, not **success**, on PRs that touch nothing under `ios/` — which matters if you ever make it a required check |
| Apple Developer Portal: App ID, capability, cert, profile | **Manual, one time** (steps 2–5) |
| App Store Connect: app record, API key | **Manual, one time** (steps 6–7) |
| GitHub repo secrets | **Manual, one time** (step 10) |
| Writing the git tag + GitHub Release notes | **Manual, every release** |
| Suppressing the iOS build for one release | **Manual** — put `[skip-ios]` in the release body; the job-level `if:` guard in `release.yml` honours it and the notes step strips it |
| Assigning a build to TestFlight testers | **Manual** (internal groups can be set to auto-add) |
| App Store metadata, screenshots, App Privacy, App Review Notes | **Manual, one time + on changes** |
| **Submit for Review / Release to the App Store** | **Manual, always** |

**Never hand-bump `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in
`project.yml` for a release.** The tag is the source of truth. The values
in `project.yml` are only a fallback for local builds. (This is a change
from `docs/BETA-TESTING.md`'s original pre-submission checklist, which
predates the pipeline.)

---

## Phase 0 — Two decisions, both already made and applied

Both were cheap to change before step 7 and expensive after. **Both are
now settled and the code changes are in the tree** — this section records
what was decided and why, so the reasoning survives.

### 0.1 The public app name — "FlashAir Sync", with attribution

**Decision (2026-08-13): keep the name `FlashAir Sync`.** The trademark
risk is real and was accepted deliberately. The mitigation is
*attribution*, not avoidance.

FlashAir is a registered trademark of Kioxia Corporation (formerly
Toshiba Memory Corporation, which is why the cards themselves are branded
Toshiba). Guideline 5.2.1 covers misleading or copycat names and metadata
*in the app bundle*, which includes `CFBundleDisplayName` — not just the
store listing. Using someone else's mark to say *what your app works
with* is nominative use, which is the defensible kind, but it is only
defensible when ownership is attributed and non-affiliation is stated.

**So the attribution is not optional, and it has to appear in all three
places.** They must match:

| Where | Status | Text |
|---|---|---|
| In-app, Settings → About footer | **Done** — `Features/Settings/SettingsView.swift` | "FlashAir is a trademark of Kioxia Corporation (formerly Toshiba Memory Corporation). This app is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Kioxia or Toshiba." |
| App Store description footer | **Manual — you paste it at step 12** | Same sentence, verbatim |
| App Review Notes | **Manual — included in the step 13 block** | A line stating the name is nominative use with attribution |

Also at step 12: keep the subtitle free of the mark (describe the
function, not the brand), and put the compatibility claim in the
description *body* — "Works with Toshiba FlashAir W-03 and W-04 Wi-Fi SD
cards" — which is the low-risk placement.

The *internal* names — the repo, the scheme `FlashAirSync`, the bundle ID
`us.v9n.flashair-sync`, the profile `flashair-sync` — are not
user-visible and carry effectively zero risk. Leave them alone; changing
them would invalidate everything below.

**Honest calibration:** I have no evidence that Apple has ever rejected
this app or one like it over the name, and attributed nominative use is
common on the App Store. This is a risk assessment, not a verified
rejection. **If Apple does bounce it on 5.2.1**, the fallback is a
neutral store name ("Wi-Fi SD Import", "CardPull") — that means changing
`CFBundleDisplayName` in `project.yml`, regenerating, cutting a new
build, *and* renaming the record in App Store Connect. Cheap to do, but
it costs a review cycle, which is exactly what you are accepting here.

### 0.2 iPhone-only for v1.0 — applied

**Decision (2026-08-13): `TARGETED_DEVICE_FAMILY: "1"`.** Already set in
`project.yml`; a built bundle now reports `UIDeviceFamily = [1]`.

`CLAUDE.md` records that the app has only ever been run on iPhone.
Shipping iPad would have cost a **mandatory** 13" iPad screenshot set
(2064 × 2752) and a reviewer exercising an iPad layout nobody has looked
at — where a layout bug becomes a 2.1 crash rejection.

Consequences to remember at step 12: you need **only** the 6.9" iPhone
screenshot set. The `UISupportedInterfaceOrientations~ipad` key is still
in `project.yml` but is inert while device family is `"1"`, so adding
iPad back in 1.1 is a one-line change plus an actual iPad smoke test.

---

## Phase 1 — Apple Developer Portal (one time)

### Step 1 — Confirm membership and agreements

`developer.apple.com/account` → membership for team **99CP4GY776** is
active and not about to renew.

App Store Connect → **Business** → the Paid/Free Apps agreement is signed
and current. If Apple has pushed a new agreement version since your last
release, **no new app record can be created** until the Account Holder
accepts it. This is the most common silent blocker at step 7 and it costs
30 seconds to rule out.

### Step 2 — Register the App ID `us.v9n.flashair-sync`

`developer.apple.com/account` → **Certificates, Identifiers & Profiles**
→ **Identifiers** → **＋**

1. Register a new identifier → **App IDs** → Continue
2. Type: **App** → Continue
3. Description: `FlashAir Sync` (internal only; ASCII, no punctuation)
4. Bundle ID: **Explicit** → `us.v9n.flashair-sync`
5. Capabilities → tick **Hotspot** (shown as "Hotspot Configuration" in
   some views — same thing)
6. **Tick nothing else.** Not Network Extensions, not Multicast, not
   Access WiFi Information. The app declares exactly one entitlement;
   extra capabilities on the App ID put entitlements in the profile that
   the binary doesn't have, which produces confusing signing failures.
7. Continue → Register

Do **not** register a separate App ID for `us.v9n.flashair-sync.tests`.
The unit-test bundle isn't built during an archive (the generated
scheme's archive action builds only `FlashAirSync.app`), so it never
needs a profile.

> **The Hotspot Configuration entitlement is self-serve. There is no
> request form, no Apple approval, and no waiting.**
>
> `com.apple.developer.networking.HotspotConfiguration` is an
> *unmanaged* entitlement: any paid Apple Developer Program membership
> can tick the box, same day, no justification. `docs/BETA-TESTING.md`,
> `ios/README.md`, and the header comments in
> `ios/FlashAirSync/project.yml` and `FlashAirSync.entitlements` all
> previously said Apple has to "grant" it and
> "has historically denied it for hobby apps" — that is **wrong**, and it
> conflates this entitlement with two genuinely gated things the app does
> not use: `NEHotspotHelper`
> (`com.apple.developer.networking.HotspotHelper`, a *managed*
> entitlement requiring a written request) and
> `com.apple.developer.networking.multicast` (also request-gated).
>
> **Confidence: high (~95%), not absolute.** Basis: Apple's supported
> capabilities matrix for iOS lists Hotspot as a plain ADP-tier
> self-serve capability; Apple DTS has stated the
> managed-vs-unmanaged distinction on the developer forums. Apple's raw
> entitlement reference page could not be machine-read to confirm the
> body text. **The 5-minute empirical check is this step itself:** if the
> checkbox saves immediately, it's self-serve; if it opens a request
> form, it isn't. It will save immediately.

### Step 3 — Distribution certificate (you almost certainly reuse the existing one)

Distribution certificates are **team-scoped, not app-scoped**. The one
signing baby-monitor and look-up signs this app too. Do **not** create a
new one — the per-team cap is small, and hitting it forces a revoke that
breaks the other two repos' pipelines.

```bash
security find-identity -v -p codesigning
security find-certificate -c "Apple Distribution: Patrick van Staveren" -p \
  | openssl x509 -noout -subject -dates
```

At the time this doc was written the local keychain held
`Apple Distribution: Patrick van Staveren (99CP4GY776)`, SHA-1
`9C2EAE1F3072A4B12E595C6A89487B1043464A15`, valid 2026-05-23 →
2027-05-23. Cross-check it is still listed under **Certificates,
Identifiers & Profiles → Certificates** (filter: Apple Distribution).

> ⚠️ **Possible certificate drift across your repos.** baby-monitor's
> `BUILD_CERTIFICATE_BASE64` secret was last set **2026-03-29**; the cert
> in the local keychain was issued **2026-05-23**. Those are different
> certificates. Either you re-issued in May and baby-monitor's next
> release will fail to sign, or the team has two valid certs. **Which one
> is true is UNVERIFIED** — 60 seconds on the Certificates page settles
> it. If the March cert is gone, refresh `BUILD_CERTIFICATE_BASE64` in
> all three repos while you're here, not while debugging a red release.

Only if `find-identity` shows nothing (new Mac / nuked keychain):
Keychain Access → Certificate Assistant → *Request a Certificate From a
Certificate Authority* → **Saved to disk**, **Let me specify key pair
information**, 2048-bit RSA → portal → Certificates → ＋ → **Apple
Distribution** → upload the CSR → download the `.cer` → double-click.

### Step 4 — Export the certificate as `.p12`

Keychain Access → **login** → **My Certificates** → `Apple Distribution:
Patrick van Staveren (99CP4GY776)`.

**Expand the disclosure triangle and confirm a private key is nested
underneath.** Without it the export yields something useless and CI fails
at `security import` with an unhelpful error.

Right-click the **certificate** (not the key) → **Export** → format
**Personal Information Exchange (.p12)** → save to
`~/Desktop/flashair-dist.p12` → set a password.

Use the **same p12 password as your other two repos** — then
`P12_PASSWORD` is a value you already have. Record it in your password
manager either way.

### Step 5 — Create the App Store provisioning profile

**Certificates, Identifiers & Profiles → Profiles → ＋**

1. Distribution → **App Store Connect** → Continue
2. App ID: **`us.v9n.flashair-sync`** → Continue
3. Certificate: the Apple Distribution cert from step 3 → Continue
4. **Provisioning Profile Name: `flashair-sync`** — exact, lowercase,
   hyphenated. This string is matched literally by fastlane's
   `profile_name:` and by the `provisioningProfiles` export-options map.
   A mismatch produces the famously unhelpful *"No profile for team …
   matching 'flashair-sync' found"*.
5. Generate → Download → save as `~/Desktop/flashair-sync.mobileprovision`

Verify the entitlement actually made it into the profile. This is the one
real gate on the Hotspot capability, and if the capability wasn't ticked
in step 2 the profile silently ships without it:

```bash
security cms -D -i ~/Desktop/flashair-sync.mobileprovision \
  | plutil -extract Entitlements xml1 -o - -
```

You must see `com.apple.developer.networking.HotspotConfiguration` set to
`true`. If not: go back to step 2, tick **Hotspot**, then **Edit → Save**
the existing profile (that regenerates it — you don't need a new one) and
re-download.

---

## Phase 2 — App Store Connect (one time)

### Step 6 — App Store Connect API key (you probably reuse this too)

**appstoreconnect.apple.com → Users and Access → Integrations → App
Store Connect API → Team Keys**

These keys are **team-scoped**. The key behind baby-monitor's
`ASC_API_KEY_ID` / `ASC_API_ISSUER_ID` / `ASC_API_KEY_BASE64` uploads
this app with zero new setup — and since a `.p8` can never be
re-downloaded, reusing the file you already have is the path of least
resistance.

Only if you need a new one:

1. **＋** → Name: `flashair-sync-ci`
2. Access role: **App Manager**. (Developer is *not* enough here: the lane
   always passes `changelog:` — it defaults to "Bug fixes and
   improvements." — and setting "What to Test" is updating build metadata.
   Developer also can't manage testers. Either way you'd hit an opaque 403.)
3. Generate → **Download API Key** → `AuthKey_<KEYID>.p8`.
   **Downloadable exactly once, ever.** Losing it means revoke + reissue
   + update every repo's secrets.
4. **Key ID** (10 chars, in the row) → `ASC_API_KEY_ID`
5. **Issuer ID** (UUID at the top of the Keys page, shared by all keys on
   the team) → `ASC_API_ISSUER_ID`

### Step 7 — Create the app record

**App Store Connect → Apps → ＋ → New App**

| Field | Value |
|---|---|
| Platforms | ☑ **iOS** only |
| Name | **`FlashAir Sync`** per the decision in 0.1 (kept, with trademark attribution). ≤30 chars, and must be globally unique across the whole App Store — if it is taken, fall back to the neutral option in 0.1 rather than inventing a variant here |
| Primary Language | English (U.S.) |
| Bundle ID | **`us.v9n.flashair-sync`** — only appears if step 2 completed; portal→ASC sync takes a few minutes, hard-refresh if missing |
| SKU | `flashair-sync` (internal, immutable, never shown) |
| User Access | Full Access |

→ **Create**. Status becomes **Prepare for Submission**.

**This record must exist before the first `upload_to_testflight`**, or
the upload fails with "Could not find app with bundle identifier".

**Then immediately fix the version number App Store Connect invented for
you.** ASC creates the first version record as **1.0**. Open it and set
the **Version** field to the marketing version you actually intend to tag
— `0.1.0` if your first tag is `v0.1.0`. App Store Connect only offers
builds whose `CFBundleShortVersionString` equals this field, so leaving
it at `1.0` means your `0.1.0` build uploads fine, processes fine, lands
in TestFlight fine — and is then simply **absent** from the version's
Build picker at step 15, with no error explaining why. The version record
is renameable at any time before submission; do it now while you're
looking at it.

### Step 8 — Confirm EU DSA trader status

**App Store Connect → Business** → trader status shows **verified**, not
"pending" or "action required".

You almost certainly did this for the other two apps — but it is an
*account-level* setting that specifically gates **new app** approval, so
confirm rather than assume.

**UNVERIFIED:** whether this is purely account-level or also surfaces a
per-app prompt at first submission. Apple's help reads account-level;
there are scattered reports of per-app prompts. The 30-second check
covers both.

### Step 9 — Publish the privacy policy URL

A Privacy Policy URL is **required for every app**, free or not, and
again for TestFlight external testing.

`PRIVACY.md` at the repo root is written for this app. Note that it is
**not** a copy of baby-monitor's — baby-monitor claims "No analytics",
which is false here: this app ships Sentry, default-ON, and filenames can
appear in error reports.

**Before you paste this URL anywhere, `PRIVACY.md` has to actually be on
`main`.** It is untracked on a fresh working tree, and the URL 404s until
it is pushed — App Store Connect and the TestFlight external-testing form
both take a dead link without complaint and bounce it later:

```bash
git add PRIVACY.md && git commit -m "docs: add privacy policy" && git push origin main
curl -sSf -o /dev/null -w '%{http_code}\n' \
  https://github.com/trickv/flashair-fetch-app/blob/main/PRIVACY.md   # expect 200
```

(Step 10.5 below lands this alongside the rest of the pipeline if you'd
rather do it in one commit — but the URL still isn't live until *that*
push, so check the 200 either way.)

Then use:

```
https://github.com/trickv/flashair-fetch-app/blob/main/PRIVACY.md
```

The `/blob/main/` form renders on mobile and needs no login. Prefer it
over `raw.githubusercontent.com` (serves `text/plain`). GitHub Pages is
nicer if you want it; your Jekyll site is **not** a safe default —
`_config.yml` declares `url: "http://trick.vanstaveren.us"` over plain
HTTP, and an `http://` policy URL is a needless rejection risk.

**UNVERIFIED:** I could find no authoritative Apple statement either
blessing or rejecting a GitHub blob URL. Apple's stated requirement is
only "publicly accessible, no login", which it satisfies, and the pattern
is widely used. Low risk, not zero.

---

## Phase 3 — GitHub secrets (one time)

### Step 10 — Set all eight secrets

This repo currently has **zero** secrets — verified with
`gh secret list -R trickv/flashair-fetch-app` (empty). All eight names
match the reference repos exactly, on purpose.

macOS note: BSD `base64` has `-i` / `-o` / `--decode` and **no `-w`**;
its default output is a single unwrapped line, which is what the workflow
expects. Don't "fix" the decode calls to the GNU form.

```bash
R=trickv/flashair-fetch-app

# 1. Distribution certificate (.p12 from step 4)
base64 -i ~/Desktop/flashair-dist.p12 | gh secret set BUILD_CERTIFICATE_BASE64 -R "$R"

# 2. The password you set when exporting the .p12
#    (gh prompts "Paste your secret:" — paste the value and press Enter.
#     It's a single masked line; Ctrl-D only matters when stdin is a pipe.)
gh secret set P12_PASSWORD -R "$R"

# 3. Throwaway password for the ephemeral CI keychain — any random string
openssl rand -base64 24 | tr -d '\n' | gh secret set KEYCHAIN_PASSWORD -R "$R"

# 4. Provisioning profile (step 5)
base64 -i ~/Desktop/flashair-sync.mobileprovision | gh secret set BUILD_PROVISION_PROFILE_BASE64 -R "$R"

# 5. App Store Connect API private key (.p8 from step 6)
base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | gh secret set ASC_API_KEY_BASE64 -R "$R"

# 6. Key ID — the 10-char ID from the Keys row
#    (gh prompts "Paste your secret:" — paste the value and press Enter)
gh secret set ASC_API_KEY_ID -R "$R"

# 7. Issuer ID — the UUID at the top of the Keys page
#    (gh prompts "Paste your secret:" — paste the value and press Enter)
gh secret set ASC_API_ISSUER_ID -R "$R"

# 8. Team ID
printf '99CP4GY776' | gh secret set APPLE_TEAM_ID -R "$R"
```

Verify:

```bash
gh secret list -R trickv/flashair-fetch-app
```

Expect exactly: `APPLE_TEAM_ID`, `ASC_API_ISSUER_ID`, `ASC_API_KEY_BASE64`,
`ASC_API_KEY_ID`, `BUILD_CERTIFICATE_BASE64`,
`BUILD_PROVISION_PROFILE_BASE64`, `KEYCHAIN_PASSWORD`, `P12_PASSWORD`.

Then destroy the local copies — these are long-lived team credentials:

```bash
rm -P ~/Desktop/flashair-dist.p12 ~/Desktop/flashair-sync.mobileprovision
# KEEP the .p8 somewhere safe — it is NOT re-downloadable.
```

`SENTRY_AUTH_TOKEN` is **not** used by the release workflow. dSYMs are
attached to the GitHub Release instead, so symbolication is always
recoverable; wiring `sentry-cli upload-dif` needs the org and project
*slugs*, which the committed DSN does not give you (it only yields the
numeric IDs `o4510950028279809` / `4511510747676672`).

### Step 10.5 — Land the pipeline on `main` before you tag anything

Everything from here down assumes the release machinery is **committed and
pushed**. On a fresh working tree it is not: `fastlane/`, `Gemfile`,
`.github/workflows/release.yml`, `.github/workflows/ios-build.yml`,
`PRIVACY.md`, this document, the asset catalog and `ios/FlashAirSync/tools/`
are all untracked, and eleven files are modified: `.gitignore`, `project.yml`,
the generated `Info.plist`, `FlashAirSync.entitlements`, `Telemetry.swift`,
`SettingsView.swift`, `CLAUDE.md`, `README.md`, `ios/README.md`,
`docs/BETA-TESTING.md` and `docs/REAL-WORLD-FINDINGS.md`.

**The two Swift files are not incidental.** `SettingsView.swift` carries the
only copy of the Kioxia trademark footer that step 0.1 calls non-optional, and
the corrected telemetry-consent text. Leave them out of the commit and the tag
points at a binary missing both — and no check below catches it, because
grepping the working tree passes either way.

**This is the single most likely way a first release silently does
nothing.** A `release` event resolves the workflow file *from the tagged
commit*. Tag before the merge lands and the GitHub Release publishes
against a commit that contains no `release.yml` — **zero workflow runs,
zero error, nothing in the Actions tab to click on.** You will assume it's
still queueing.

```bash
git add fastlane Gemfile .gitignore PRIVACY.md \
        .github/workflows/release.yml .github/workflows/ios-build.yml \
        docs/APP-STORE-RELEASE.md docs/BETA-TESTING.md \
        docs/REAL-WORLD-FINDINGS.md CLAUDE.md README.md ios/README.md \
        ios/FlashAirSync/project.yml \
        ios/FlashAirSync/FlashAirSync/Info.plist \
        ios/FlashAirSync/FlashAirSync/FlashAirSync.entitlements \
        ios/FlashAirSync/FlashAirSync/PrivacyInfo.xcprivacy \
        ios/FlashAirSync/FlashAirSync/Utils/Telemetry.swift \
        ios/FlashAirSync/FlashAirSync/Core/Models.swift \
        ios/FlashAirSync/FlashAirSync/Features/Settings/SettingsView.swift \
        ios/FlashAirSync/FlashAirSync/Assets.xcassets \
        ios/FlashAirSync/tools
git commit -m "release: fastlane + GitHub Actions TestFlight pipeline"
git push origin main

# Sanity: must print NOTHING. Anything still listed is a file the tag
# will not contain.
git status --porcelain

# And check the commit, not the desk — this is the one that ships.
git show HEAD:ios/FlashAirSync/FlashAirSync/Features/Settings/SettingsView.swift \
  | grep -c 'trademark of Kioxia'   # expect 1
```

Then run Phase 4 against **that** commit — it is the one the tag will
point at. If Phase 4's `xcodegen generate` moves `Info.plist`, commit that
too and tag the resulting commit instead.

---

## Phase 4 — Verify before you tag

Cheap checks that turn a 10-minute red CI run into a 10-second local one.

```bash
# 0. After any Xcode upgrade, the toolchain refuses to run until the new
#    licence is accepted — every xcodebuild/xcrun/swift call fails with
#    "You have not agreed to the Xcode license agreements". Cheap to re-run.
sudo xcodebuild -license accept
xcodebuild -version   # note it: CI runs the macos-26 image default, not this

# 1. The project still generates and builds clean, unsigned.
#    Same configuration and destination as .github/workflows/ios-build.yml's
#    device-SDK step (that one also passes -project and -derivedDataPath build).
#    A local pass is strong evidence of a CI pass, not proof — the toolchains
#    differ; see the rationale comment in release.yml.
cd ios/FlashAirSync
xcodegen generate
xcodebuild build -scheme FlashAirSync -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# 2. The workflows are valid *as workflows*, not merely as YAML. GitHub
#    evaluates ${ {  } }-style expressions anywhere in a run block — comments
#    included — so a file can parse as perfect YAML and still be rejected
#    wholesale, showing up in the Actions tab as a 0-second failure named
#    after the file path instead of its `name:`. This happened on the very
#    first push of release.yml.  brew install actionlint
actionlint ../../.github/workflows/*.yml

# 3. The tree is clean after generating. If Info.plist shows as modified,
#    someone edited project.yml without regenerating — commit the plist,
#    or every shipped build gets stamped GitCommitHash "<sha>-dirty".
git -C ../.. status --porcelain
```

Then confirm the release-pipeline prerequisites are actually in the
commit you're about to tag. **Every box below is a check on work that is
already done** — if one of them fails, that is a defect to fix, not a
task you forgot:

- [ ] `PRODUCT_BUNDLE_IDENTIFIER: us.v9n.flashair-sync` (app) and
      `us.v9n.flashair-sync.tests` (tests) in `project.yml`
- [ ] **Version injection wired.** `info.properties` must carry
      `CFBundleShortVersionString: "$(MARKETING_VERSION)"` and
      `CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"`; the lane
      overrides those two build settings on the `xcodebuild` command
      line. This is a two-part change and half of it ships `1.0 (1)`
      forever — the Fastfile preflights it and aborts with instructions
      if the generated plist has literals instead of the `$(…)`
      references. What matters is that **two consecutive releases
      produce different `CFBundleVersion` values** — see
      Troubleshooting → "invalid build number".
- [ ] `Assets.xcassets/AppIcon.appiconset` with a 1024×1024 **opaque**
      PNG (**no alpha channel** — hard reject). Verify, don't eyeball:
      `sips -g pixelWidth -g pixelHeight -g hasAlpha AppIcon-1024.png`.
      The committed PNG is regenerated by
      `ios/FlashAirSync/tools/make-icon.swift`, which encodes both
      constraints
- [ ] `ITSAppUsesNonExemptEncryption: false` in `info.properties`.
      **Already set** — step 11 explains why it's the right answer and
      what would make you revisit it; it is not work left to do
- [ ] `fastlane/Fastfile`, `fastlane/Appfile`, root `Gemfile`,
      `.github/workflows/release.yml` present **and committed** (step
      10.5 — `ls` is not the test here, `git log` is)
- [ ] `NSPhotoLibraryUsageDescription` is **absent** from
      `info.properties` — confirm it, don't assume. The app only ever
      *adds* (`PhotoSaver` uses `.addOnly`), and a binary advertising
      full read access contradicts the App Review Notes in step 13.
      `NSPhotoLibraryAddUsageDescription` is the one that stays:
      ```bash
      # Anchored to real keys — a bare grep also hits the explanatory
      # comment above them and reads like a failure.
      grep -nE '^\s*NSPhotoLibrary[A-Za-z]*:' ios/FlashAirSync/project.yml
      ```
- [ ] **The in-app telemetry consent text matches `PRIVACY.md`.** Both must
      say that a failed file's name and card path travel with the error
      report — `SyncEngine` attaches them. This is the text a user reads
      before consenting, so it is the one that must not under-disclose:
      ```bash
      grep -c 'filename and path on the card' \
        ios/FlashAirSync/FlashAirSync/Features/Settings/SettingsView.swift  # expect 1
      ```
- [ ] `PrivacyInfo.xcprivacy` reaches the **root of the built bundle**,
      not just the source tree — that is the only place Apple's upload
      scanner looks. The source file is
      `ios/FlashAirSync/FlashAirSync/PrivacyInfo.xcprivacy`; `project.yml`
      excludes it from the whole-directory glob and re-adds it with an
      explicit `buildPhase: resources` so the classification can't drift
      silently. Confirm it after the Phase 4 build:
      ```bash
      find ~/Library/Developer/Xcode/DerivedData \
        -path '*FlashAirSync.app/PrivacyInfo.xcprivacy' -print -quit
      ```
      It is **required**, not optional — see Troubleshooting → ITMS-91053
- [ ] **Phase 0's two decisions are applied** to `project.yml`,
      regenerated, and committed. Both are baked into the binary and
      cannot be changed in App Store Connect afterwards:
      ```bash
      # Expect: FlashAir Sync  (0.1 — keep the name, attribute the mark)
      /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' \
        ios/FlashAirSync/FlashAirSync/Info.plist
      # Expect: "1"  (0.2 — iPhone only, so no 13" iPad screenshot set)
      grep -n 'TARGETED_DEVICE_FAMILY' ios/FlashAirSync/project.yml
      ```
- [ ] **Trademark attribution is in the binary**, not just planned. The
      name keeps the FlashAir mark (0.1), so the Settings → About footer
      carrying the Kioxia attribution + non-affiliation statement is part
      of the mitigation, not decoration. It ships in
      `Features/Settings/SettingsView.swift`; the matching store-side
      text is yours to paste at step 12 and it must say the same thing:
      ```bash
      grep -c 'trademark of Kioxia' \
        ios/FlashAirSync/FlashAirSync/Features/Settings/SettingsView.swift  # expect 1
      ```

---

## Every release from now on

The short version: **tag, write notes, publish, watch, then do the two
Apple-side clicks.**

```bash
# 1. Make sure main is green and clean — AND that the release plumbing is
#    actually on it (step 10.5). The workflow is read from the tagged
#    commit; if release.yml isn't in it, publishing runs nothing at all.
git checkout main && git pull
git log --oneline -1 -- .github/workflows/release.yml   # must print something

# 2. Tag. The tag IS the marketing version — "v0.1.0" ships as "0.1.0".
git tag v0.1.0
git push origin v0.1.0

# 3. Write the notes. This file has to exist before the next line reads it;
#    docs/BETA-TESTING.md has the template.
"${EDITOR:-vi}" /tmp/notes.md

# 4. Create AND PUBLISH the GitHub Release. The workflow triggers on
#    `release: types: [published]` — a bare `git push --tags` does nothing.
#    --verify-tag makes a typo'd tag fail here instead of creating a new one.
gh release create v0.1.0 --verify-tag --title "v0.1.0" --notes-file /tmp/notes.md
```

The release body becomes the TestFlight "What to Test" text (it is passed
to fastlane through an environment variable, so quotes and backticks in
it are safe). `docs/BETA-TESTING.md` has the notes template — its
"no filenames" line has been corrected there; use the corrected version.

**Escape hatch: `[skip-ios]`.** Put that tag anywhere in the release body
and the whole `ios-testflight` job is skipped — you get the tag, the
GitHub Release and its notes, but no TestFlight build. Same tag as
`../baby-monitor` and `../look-up`, deliberately, so muscle memory
carries over. Use it for a docs-only or Android-only release, or when
re-cutting a tag you don't want to burn a build number on. Two things
implement it and they have to stay paired: the job-level `if:` guard in
`release.yml` is what actually skips, and the "Compose TestFlight release
notes" step strips the tag out of the text so it never reaches testers.
`workflow_dispatch` ignores it — a manual run is an explicit "build this
now".

Then:

```bash
gh run watch -R trickv/flashair-fetch-app
```

Expect roughly **6–9 minutes for the build itself** — the dominant cost is
SwiftPM fetching sentry-cocoa's prebuilt XCFrameworks (~600 MB
compressed), which is not cacheable at a sane price and is not a bug.

**Then the job may sit there for a while longer.** The lane passes a
`changelog:` alongside `skip_waiting_for_build_processing: true`, and
`upload_to_testflight` has to wait for the build to *appear* in App Store
Connect before it can set "What to Test" — typically another 5–15
minutes. Budget **10–25 minutes wall clock**; the job cap is
`timeout-minutes: 60`. If a run ever times out *after* the upload log
line, the binary is already at Apple: treat it as the "failed after
`upload_to_testflight` succeeded" case in Troubleshooting and do **not**
re-run.

**UNVERIFIED:** exactly how long pilot blocks with
`skip_waiting_for_build_processing: true` *and* a non-empty `changelog:`.
Nobody has run this pipeline yet. Watch run #1's timestamps and replace
this paragraph with the real number.

**What the workflow did for you:** regenerated the project, resolved the
version and build number, imported the cert and profile, archived,
exported `FlashAirSync.ipa`, uploaded it to TestFlight, and attached the
`.ipa` + dSYM zip to the GitHub Release.

**What you still do by hand, per release:**

1. **Wait for the processing verdict.** With
   `skip_waiting_for_build_processing: true`, fastlane goes green as soon
   as Apple *accepts the binary for processing* — not when it validates.
   The real verdict arrives by email 5–30 minutes later, and a failed
   build simply never appears in TestFlight. Watch for the ITMS errors in
   Troubleshooting.
2. **TestFlight → Internal Testing** → confirm the build landed and is
   assigned to your group. Internal groups (up to 100 App Store Connect
   users) need **no Beta App Review** and install minutes after
   processing. Builds expire **90 days** after upload.
   *First release only:* a brand-new app record has **no group at all**,
   so there is nothing for the build to land in and the screen looks
   broken. TestFlight → Internal Testing → **＋** next to Testers &
   Groups → create a group (e.g. `Internal`) → add yourself and anyone
   else who has an App Store Connect account on the team → tick
   **Automatically distribute builds**. Do it once and every later
   release lands there by itself.
3. **Only if you're distributing externally:** TestFlight → External
   Testing → group → add the build. External testing needs **Beta App
   Review**, a beta description, a feedback email and the privacy policy
   URL — and it hits exactly the same "I can't test this without the
   hardware" wall as App Review, so put the demo video link in the beta
   review notes too, not just the App Store ones.
   *Planning estimate only: 2–7 days. Apple publishes no SLA for Beta App
   Review and this number is from third-party reporting — **UNVERIFIED**.*
4. **Only when you want it in the store:** the manual submission below.

Export compliance does **not** need a per-build click, provided
`ITSAppUsesNonExemptEncryption: false` is in the built plist (step 11).

---

## First App Store submission (all manual)

### Step 11 — Export compliance

**Already done.** `ITSAppUsesNonExemptEncryption: false` is set in
`project.yml` → `info.properties` and is in the committed `Info.plist`;
this section exists to explain *why* that is the right answer and what
would make you revisit it, not to ask you for anything.

It is the correct and defensible answer because the
declaration means "does not use **non-exempt** encryption", not "uses no
encryption". This app's only cryptography is OS-provided TLS
(`URLSession` → Sentry) and cleartext HTTP to the card; standard
transport TLS is exempt, and Sentry's SDK implements no crypto of its
own.

It is a regulatory declaration logged against your account and your
binary, not a UI dismissal — revisit it if you ever add custom
encryption. It must be in the **built bundle's** plist, so it goes in
`info.properties` and never into the generated plist by hand.

With the key present, TestFlight stops asking and "Missing Compliance"
never appears.

### Step 12 — Metadata

App Store Connect → your app → **iOS App `<your version>`** / **App
Information**. That left-hand entry is named after the version record's
**Version** field, so it reads `iOS App 0.1.0` if you renamed it in step
7 — and `iOS App 1.0` if you didn't, which is the state in which your
build won't be selectable at step 15.

| Field | Value / note |
|---|---|
| **Screenshots — iPhone 6.9"** | **Required.** 1320 × 2868 **or** 1290 × 2796 portrait (Apple accepts either for this size class), 1–10 images, PNG/JPEG, **no alpha** |
| **Screenshots — iPad 13"** | **Not needed.** Device family is `"1"` per 0.2, so App Store Connect won't ask for an iPad set. (If you ever flip back to `"1,2"`: 2064 × 2752 **or** 2048 × 2732 portrait, and it becomes mandatory) |
| App Previews (video) | Optional — skip |
| Promotional Text | ≤170 chars, editable without a new build; good place for known limitations |
| **Subtitle** | ≤30 chars, **keep the trademark out of it** — describe the function: "Import photos from Wi-Fi SD cards". See 0.1 |
| Description | Must end with the trademark footer below. Say plainly that a FlashAir card is required — it sets expectations and pre-empts 1-star "doesn't work" reviews |
| Keywords | 100 chars, comma-separated, no spaces. `wifi sd,sd card,photo import,camera,dslr,eyefi,wireless`. Metadata keywords are far lower-risk than the name, so `flashair` here is defensible if you want the search traffic |
| **Support URL** | Required — `https://github.com/trickv/flashair-fetch-app/issues` |
| Marketing URL | Optional — repo root |
| Copyright | `2026 Patrick van Staveren` (no `©`, Apple adds it) |
| Category | Primary **Photo & Video**, Secondary **Utilities** |
| Age Rating | Complete the questionnaire. Apple's 2025 overhaul replaced 12+/17+ with **13+/16+/18+** and added mandatory blocks on in-app controls, capabilities and medical/wellness. All-No → **4+** |
| Content Rights | Third-party content? → **No** |
| Pricing *and* Availability | Its **own** page in the sidebar, not App Information: set price tier **Free** *and* country/region availability. A new app cannot be submitted until availability is set |
| **App Privacy** | Step 14 — blocks submission until complete |
| **App Review Information** | Step 13 — the make-or-break field |

**Description — copy-paste the trademark footer verbatim.** This is the
store half of the attribution decided in 0.1; the in-app half is already
shipped in Settings → About. They must say the same thing.

```
Works with Toshiba FlashAir W-03 and W-04 Wi-Fi SD cards. A FlashAir card
is required — the app has nothing to connect to without one.

FlashAir is a trademark of Kioxia Corporation (formerly Toshiba Memory
Corporation). This app is an independent open-source project and is not
affiliated with, endorsed by, or sponsored by Kioxia or Toshiba.
```

**Screenshot shortcut:** the Debug build talks to the mock server at
`localhost:8080` from the Simulator (`SyncSettings.isLocalMockHost` skips
the Wi-Fi join). Run `tools/mock-flashair/server.py`, boot an iPhone 17
Pro Max (6.9") — that one device covers the whole requirement now that
device family is `"1"` — and ⌘S. Far easier than
photographing a real sync — and note the mock path is the *validated*
one, so the screens will be honest.

**UNVERIFIED, worth a look before you shoot:** apps built against the iOS
26 SDK get Liquid Glass styling on native components by default. Your
local Xcode builds already reflect it, but confirm the SwiftUI
layout still looks right — a screenshot that doesn't match the shipped
build reads as sloppy.

### Step 13 — App Review Notes + demo video ← the highest-risk step

**What the reviewer will actually experience:** a device in a test lab.
There is no Wi-Fi network named `flashair`. They tap Sync,
`NEHotspotConfiguration` fails to join or the HTTP call to `192.168.0.1`
times out after ~30s, and they see an error. **They cannot reach a single
screen that demonstrates the app's purpose.**

Unexplained, that is a 2.1 "Information Needed" rejection at best and a
4.2 "minimum functionality" rejection at worst.

**Demo video — the part people lose a week on:** Apple wants to see the
**physical hardware and the app together, on a real Apple device**, not a
screen recording alone. The two `ScreenRecording_05-29-2026*.mp4` files at
the repo root are screen recordings and are **not sufficient on their
own** — shoot a new one with a second camera filming the camera body with
the card in it, the Wi-Fi join, and the photos landing in Photos. 60–120
seconds. Attach a screen recording *additionally* if it helps.

Prefer a **direct file link** (`https://…/demo.mp4`) over an attachment:
Apple's stated preference, it persists across submissions, and it
sidesteps the attachment size question. (**UNVERIFIED:** the current
attachment byte cap. Your existing recordings are 34 MB and 51 MB;
`.mp4`/`.avi` are accepted extensions.)

Copy-paste block for **App Review Information → Notes**:

```
WHAT THIS APP DOES
This app imports photos and videos from a Toshiba FlashAir Wi-Fi SD card
(a wireless SD card used in DSLR cameras) into the iOS Photos library.

WHY YOU CANNOT TEST IT WITHOUT HARDWARE
The app requires a physical FlashAir SD card inserted in a powered-on
camera, broadcasting its own Wi-Fi access point. Without that card present
there is no network to join and no server to talk to, so the app will
correctly report a connection error. This is expected behavior, not a
defect.

DEMO VIDEO (shows the hardware and the app together on a physical iPhone)
https://<direct-link>/flashair-demo.mp4

WHAT THE VIDEO SHOWS
0:00  Canon DSLR powered on, FlashAir W-04 card inserted, Wi-Fi enabled in
      the camera menu
0:15  App launch; user taps Sync
0:20  iOS prompts "...would like to join the Wi-Fi network 'flashair'" —
      user taps Join. This is the NEHotspotConfiguration API and is the
      ONLY use of the Hotspot Configuration entitlement.
0:30  App lists the files found on the card and downloads them over HTTP
1:00  Photos appear in the iOS Photos app with original filenames and EXIF
      intact
1:15  App disconnects from the card's Wi-Fi and returns to the normal
      network

PERMISSIONS AND ENTITLEMENTS
- Hotspot Configuration (com.apple.developer.networking.HotspotConfiguration):
  used solely to join the SD card's own Wi-Fi access point for the duration
  of a transfer, and to disconnect immediately afterward. No other network
  is touched, scanned, or enumerated.
- Photos: ADD-ONLY access (PHPhotoLibrary .addOnly). The app only writes
  the files it downloaded. It never reads or enumerates the user's existing
  library.
- Local network: the card is an HTTP server at 192.168.0.1 on its own
  access point.
- App Transport Security: NSAllowsLocalNetworking is set because the card's
  firmware is HTTP-only and cannot be updated to support TLS. No internet
  host is contacted over cleartext.

NOTE FOR TESTING
A full card can take 10-30+ minutes depending on how many files it holds
(measured: 170 files / 769 MB in about 10 minutes). Please keep the app in
the foreground during a transfer; iOS suspends the downloads and may drop
the Wi-Fi association if the app is backgrounded.

APP NAME AND TRADEMARK
"FlashAir" appears in the app name to identify the hardware this app works
with — nominative use, not a claim of affiliation. FlashAir is a trademark
of Kioxia Corporation (formerly Toshiba Memory Corporation). Attribution
and a non-affiliation statement appear in the App Store description and
in the app itself, under Settings > About.

NO ACCOUNT REQUIRED. NO IN-APP PURCHASES. NO ADS.
```

Three things to pre-empt while you're in there:

- **5.1.1 / 5.1.2 (data collection).** The notes above say "add-only"
  explicitly, which is materially less alarming than full library access
  — and the binary now agrees: `NSPhotoLibraryUsageDescription` is gone
  from `info.properties`, only `NSPhotoLibraryAddUsageDescription`
  remains. That is the Phase 4 checkbox; if it ever comes back, these
  notes become a contradiction a reviewer can see.
- **"App joins a Wi-Fi network."** This draws scrutiny. Your defence is
  that the join is user-initiated, scoped to one SSID, transient, and
  torn down on both success and failure (`ImportViewModel.startImport`).
  State it plainly rather than waiting to be asked.
- **Discontinued hardware (4.2).** Kioxia ended FlashAir production. This
  is a low-to-moderate risk, not a fatal one — 4.2 is about apps that
  *do too little*, not apps whose hardware is old, and the store carries
  plenty of legacy-device apps. Frame it as substantial functionality:
  recursive card traversal, deduplicated incremental sync, EXIF and
  original-filename preservation, direct Photos integration. Don't
  volunteer "Toshiba discontinued these" — it isn't asked and it invites
  the question. **This is a judgment call, not a verified outcome.**

### Step 14 — App Privacy nutrition labels

**App Store Connect → your app → App Privacy → Get Started**

"Do you or your third-party partners collect data from this app?" →
**Yes.** Sentry counts, even though it is toggleable.

Three types under **Diagnostics** are unarguable — they match Sentry's own
Apple documentation and map 1:1 to the SDK options in
`Utils/Telemetry.swift`. Declare these, then read the Identifiers note
below before you hit Save:

| Data type | Why | Purpose | Linked to identity? | Used for tracking? |
|---|---|---|---|---|
| Diagnostics → **Crash Data** | `enableCrashHandler = true` | App Functionality | **No** | **No** |
| Diagnostics → **Performance Data** | `tracesSampleRate = 0.2`, `enableAppHangTracking = true` | App Functionality | **No** | **No** |
| Diagnostics → **Other Diagnostic Data** | breadcrumbs + the aggregate `sync_completed` event | App Functionality | **No** | **No** |

Beyond those three and the identifier discussed below, declare **nothing
else**. Specifically:

- **Not Photos or Videos.** The app writes *into* the library and reads
  *from the card*; no photo content ever leaves the device.
- **Not User Content.** Filenames travel with error reports, which is
  disclosed in `PRIVACY.md`, but they are diagnostic context, not user
  content, and belong in "Other Diagnostic Data".
- **Not Usage Data → Product Interaction.** `sync_completed` is aggregate
  counters with no identifiers; Sentry's own guidance puts this in Other
  Diagnostic Data.
- **Not Contact Info / Location.**

**Identifiers → User ID is a genuine judgment call, not a clear "no".**
sentry-cocoa attaches a random per-install UUID as `user.id` to *every*
event — `SentryClient.m`'s `setUserIdIfNoUserSet`, which is **not** gated
by `sendDefaultPii`. It is generated on first run, persisted in the app's
own cache directory, and exists so several reports from one install can
be grouped. It is not the IDFA or the IDFV, it is never joined to
anything else, and nothing about it is used for advertising — so **Used
for Tracking stays No** regardless. But it *is* a persistent identifier
that the app transmits, and Apple's questionnaire asks what you transmit,
not what you do with it.

The conservative answer, and the recommendation here: declare
**Identifiers → User ID**, purpose **App Functionality**, Linked to
identity **No**, Used for tracking **No**. Declaring nothing — on the
reading that this is diagnostic plumbing already covered by the
Diagnostics rows — is defensible and common in the wild, but it is a
reading, and **UNVERIFIED** which way an App Review privacy audit would
actually land. Declaring it costs one extra row and nothing else.

**The repo has already taken the conservative side**, so the default here
is to match it rather than decide afresh: the shipped
`PrivacyInfo.xcprivacy` carries an `NSPrivacyCollectedDataTypeUserID`
entry, and `PRIVACY.md` describes the identifier in plain language. These
three answers — the manifest, the policy, and this questionnaire — are
the ones that must agree; a binary declaring User ID under an App Privacy
label that doesn't is a discrepancy Apple can see without asking you.

"Used to Track You" is **No** everywhere: `sendDefaultPii = false`, no
IDFA, no ad SDK, no cross-app linking. Because tracking is No, **App
Tracking Transparency / `NSUserTrackingUsageDescription` is not
required** — do not add it.

**One honest judgment call:** Sentry's ingest can infer city-level geo
from the connecting IP (flagged in `docs/BETA-TESTING.md` and disclosed
in `PRIVACY.md`). Apple's labels describe what *your app collects and
transmits*, and an IP visible to a server as an unavoidable property of
making an HTTPS request is generally not declared as Coarse Location;
Sentry's guidance doesn't list location either. Leaving it undeclared is
the mainstream reading, **but it is a reading, not a rule.** If you want
it airtight, add the `beforeSend` geo-strip hook `docs/BETA-TESTING.md`
already proposes and the question disappears.

### Step 15 — Submit

App Store Connect → **iOS App `<your version>`** → select the build →
**Add for Review** → **Submit to App Review**.

If the Build picker is empty or doesn't list the build you just uploaded,
this is almost always step 7's version-record mismatch: the record still
says `1.0` and the build says `0.1.0`. Rename the version record, don't
re-tag.

Pre-flight:

- [ ] App Privacy complete (blocks submission)
- [ ] Age rating questionnaire answered (blocks submission)
- [ ] **App Review Information → contact**: first name, last name, phone
      in E.164 form (`+1…`), email. These are **required fields and they
      block submission**, and they are easy to skip past because they sit
      below the notes box. Use a phone and inbox you will actually answer
      — reviewers do call on hardware-dependent apps, and this one is
      exactly that
- [ ] App Review Information → **Sign-In Required: No**
- [ ] Privacy Policy URL + Support URL populated — and the privacy policy
      URL returns 200 (step 9)
- [ ] Screenshots for every device family the binary claims
- [ ] App Review Notes + demo video **link** present
- [ ] Build shows **no** "Missing Compliance"
- [ ] Version Release: **Manually release this version** — so a surprise
      approval doesn't go live while you're asleep

---

## Troubleshooting

### The Action fails midway — where it failed tells you what to fix

The release job is ordered so failures get cheaper the earlier they
happen: toolchain → XcodeGen → version resolve → cert → profile → ASC key
→ archive → upload → release assets.

- **No run at all**, no red, nothing in the Actions tab. Two causes, both
  silent by design: `release.yml` isn't in the commit the tag points at
  (step 10.5 — the workflow is resolved from the *tagged* commit, so a
  tag cut before the merge triggers nothing), or the release body
  contains `[skip-ios]` and the job's `if:` guard skipped it. Check the
  Actions tab filtered to the Release workflow; a skipped job appears as
  a run with a grey job, a missing workflow appears as no run whatsoever.
- **Failed before the archive** (cert / profile / key steps): nothing
  reached Apple. Fix the secret, then re-run. Re-running the same
  workflow run reuses the same `GITHUB_RUN_NUMBER`; **a fresh run gets a
  new one**, which is what you want if a build already uploaded.
- **Failed after `upload_to_testflight` succeeded** (e.g. attaching
  release assets): **do not re-run to "fix" it.** The build is already in
  Apple's processing queue; a second upload with a new run number just
  creates a duplicate build. TestFlight distribution is unaffected — the
  only thing you lost is the GitHub Release attachment.
  **Don't go looking in the run's Artifacts panel: on a release-triggered
  run there aren't any.** `release.yml`'s `upload-artifact` step is
  `if: github.event_name == 'workflow_dispatch'`, so the `.ipa` exists
  only in Apple's hands at that point. If you want the attachment,
  rebuild locally with
  `bundle exec fastlane ios build version:X.Y.Z build:<the same run number>`
  and `gh release upload vX.Y.Z FlashAirSync.ipa` — or accept the gap,
  which costs nothing that matters.
- **Archive succeeded, upload failed:** use the escape hatch —
  **Actions → Release → Run workflow** (`workflow_dispatch`, inputs
  `version` and `notes`) — rather than deleting and republishing the
  GitHub Release. A dispatch run has no Release to attach to, so the
  `.ipa` and dSYMs land as run artifacts instead.

### "No profile for team '99CP4GY776' matching 'flashair-sync' found"

The profile **Name** field must be exactly `flashair-sync` — not the
filename, not the UUID. Re-check step 5, re-download, re-set
`BUILD_PROVISION_PROFILE_BASE64`.

**It is not the profiles directory.** That is the other thing people
chase here — Xcode 16+ reads
`~/Library/Developer/Xcode/UserData/Provisioning Profiles` while the
legacy path is `~/Library/MobileDevice/Provisioning Profiles` — but
`release.yml`'s "Install provisioning profile" step already writes the
legacy path and `cp`s to the modern one, so the question is closed in
this repo. If you see this error here, it is the **Name** field.

### The profile is missing the Hotspot Configuration entitlement

**In this repo you will almost always meet this as a workflow failure,
not a signing failure.** `release.yml`'s "Install provisioning profile"
step runs a PlistBuddy preflight and aborts about 30 seconds into the run
with exactly this — grep the log for it:

```
::error::Provisioning profile lacks com.apple.developer.networking.HotspotConfiguration.
Enable the Hotspot capability on the us.v9n.flashair-sync App ID, regenerate
the 'flashair-sync' profile, and refresh BUILD_PROVISION_PROFILE_BASE64.
```

Without that preflight the same problem surfaces ~8 minutes later, at
signing, as *"Provisioning profile 'flashair-sync' doesn't support the
Hotspot Configuration capability"* or *"…doesn't include the
com.apple.developer.networking.HotspotConfiguration entitlement"* — the
first means the capability isn't enabled on the App ID, the second means
the profile predates enabling it. Either way it is the same fix.

Fix: step 2 → tick **Hotspot** → step 5 → **Edit → Save** the existing
profile to regenerate it → re-download → re-set
`BUILD_PROVISION_PROFILE_BASE64`. Verify with the `security cms -D`
command in step 5 *before* re-running the workflow — the profile is the
only thing that changed, so there is no point paying for another archive
to find out.

If it somehow slipped past signing too, App Store Connect rejects the
upload with an `ITMS-9016x "Invalid Code Signing Entitlements"` error
instead, by email, after the run went green.

Note that the old bundle ID `com.flashairsync` is the App ID that carried
this capability historically (it's why real-hardware Wi-Fi joins worked
in dev). `us.v9n.flashair-sync` is a brand-new App ID and inherits
nothing.

### "Signing for 'FlashAirSync' requires a development team"

`DEVELOPMENT_TEAM` is deliberately not committed. In CI, fastlane's
`update_code_signing_settings` writes it from `APPLE_TEAM_ID` — so this
error in a CI log means that secret is missing or empty. Locally it means
you haven't set Team in Xcode's Signing & Capabilities tab, which is
expected and only affects device builds.

### ITMS-90022 / ITMS-90023 / ITMS-90717 — app icon

*"does not contain an app icon … of exactly '120x120' pixels"*. The
archive succeeds and the upload bounces by email. Causes, in order of
likelihood:

1. No `Assets.xcassets` / `AppIcon.appiconset` in the target.
2. `ASSETCATALOG_COMPILER_APPICON_NAME` not set to `AppIcon`.
3. The 1024×1024 PNG has an **alpha channel**. Check with
   `sips -g hasAlpha icon.png`.

**Regenerating the icon: use the recipe in the repo.**
`ios/FlashAirSync/tools/make-icon.swift` produces the committed
`AppIcon-1024.png` byte-for-byte, and it encodes both hard constraints in
the bitmap context itself — 1024×1024 sRGB, and `.noneSkipLast` rather
than `.premultipliedLast`, which is what guarantees no alpha channel:

```bash
xcrun swift ios/FlashAirSync/tools/make-icon.swift \
  ios/FlashAirSync/FlashAirSync/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
sips -g pixelWidth -g pixelHeight -g hasAlpha -g space \
  ios/FlashAirSync/FlashAirSync/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

If you are flattening someone else's PNG instead, note that the obvious
`sips` incantation does **not** do it — `-s` *is* `--setProperty`, so
`sips -s format png --setProperty format png …` just sets the same
property twice and re-encodes the file with its alpha intact. Exit code 0,
same rejection on the next upload. Composite onto an opaque background
instead:

```bash
sips -g hasAlpha in.png   # confirm the problem first
# ImageMagick, if you have it:
magick in.png -background white -alpha remove -alpha off out.png
```

…or re-export from your editor with transparency off. Then re-check
`hasAlpha` before you upload; it is the only thing that settles it.

### ITMS-91053 — "Missing API declaration" (privacy manifest)

Since 1 May 2024, an upload whose code touches required-reason APIs
without a `PrivacyInfo.xcprivacy` declaration is rejected. The app ships
one at `ios/FlashAirSync/FlashAirSync/PrivacyInfo.xcprivacy`; this
section is why it exists and what belongs in it. The APIs it has to
cover, at minimum:

- `UserDefaults` (`SettingsView`, `Extensions`, `Telemetry`) →
  `NSPrivacyAccessedAPICategoryUserDefaults`, reason **`CA92.1`**
- `FileManager.attributesOfItem(atPath:)` (`SyncIndex`,
  `FlashAirClient`) → goes through `stat`, so plausibly
  `NSPrivacyAccessedAPICategoryFileTimestamp`, reason **`C617.1`**.
  **UNVERIFIED** — Apple doesn't publish the scanner's symbol list, and
  this call reads size, not timestamps. Declaring it costs nothing.

**The app-level manifest is required here, not belt-and-braces.** Sentry
ships its own `PrivacyInfo.xcprivacy`, but a dependency's manifest is only
aggregated into the app when it arrives inside a bundle the app embeds —
i.e. when the SDK links dynamically. It doesn't here: the `Sentry` SPM
product is a `.binaryTarget` static XCFramework (`file` on the sliced
binary reports `current ar archive`), so its manifest sits in a framework
bundle that is never embedded and cannot cover you. This was an open
question in an earlier draft of this document; it has been checked and it
is settled.

Convenient consequence: Sentry's own manifest declares the same three API
categories, so declaring the union is both correct and complete.

**How it is wired, and why it isn't just dropped in the source
directory.** The file must land at the **root of `FlashAirSync.app`** —
that is the only place the upload scanner looks. `project.yml` therefore
*excludes* `PrivacyInfo.xcprivacy` from the whole-directory `sources:`
glob and re-adds it as an explicit `buildPhase: resources` entry. The glob
alone would classify it correctly today, purely by XcodeGen's "unknown
extension ⇒ resource" default — but `.entitlements` is proof that
XcodeGen special-cases extensions into no build phase at all, and that
failure mode ships a manifest-less binary with a green build and no
warning. Saying it out loud costs two lines.

The committed manifest declares:

| Section | Entries |
|---|---|
| `NSPrivacyTracking` | `false`, no tracking domains — which is why no ATT prompt is needed |
| Collected data types | Crash Data, Performance Data, Other Diagnostic Data, **User ID** — all Linked `false`, Tracking `false`, purpose App Functionality |
| Accessed API types | `UserDefaults` `CA92.1`, `FileTimestamp` `C617.1`, `SystemBootTime` `35F9.1` (the last is Sentry's, ours by static linking) |

Read the file itself rather than this table when you need the reasoning —
each entry carries a comment naming the call sites it covers. **It has to
stay consistent with the App Privacy answers in step 14 and with
`PRIVACY.md`**; the User ID row in particular is the one that is easy to
answer differently in three places.

For reference, that is this shape:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key><false/>
  <key>NSPrivacyTrackingDomains</key><array/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array>
    <dict>
      <key>NSPrivacyCollectedDataType</key><string>NSPrivacyCollectedDataTypeCrashData</string>
      <key>NSPrivacyCollectedDataTypeLinked</key><false/>
      <key>NSPrivacyCollectedDataTypeTracking</key><false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
    </dict>
    <dict>
      <key>NSPrivacyCollectedDataType</key><string>NSPrivacyCollectedDataTypePerformanceData</string>
      <key>NSPrivacyCollectedDataTypeLinked</key><false/>
      <key>NSPrivacyCollectedDataTypeTracking</key><false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
    </dict>
    <dict>
      <key>NSPrivacyCollectedDataType</key><string>NSPrivacyCollectedDataTypeOtherDiagnosticData</string>
      <key>NSPrivacyCollectedDataTypeLinked</key><false/>
      <key>NSPrivacyCollectedDataTypeTracking</key><false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
    </dict>
    <!-- Sentry's per-install user.id UUID. See step 14. -->
    <dict>
      <key>NSPrivacyCollectedDataType</key><string>NSPrivacyCollectedDataTypeUserID</string>
      <key>NSPrivacyCollectedDataTypeLinked</key><false/>
      <key>NSPrivacyCollectedDataTypeTracking</key><false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
    </dict>
  </array>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key><array><string>CA92.1</string></array>
    </dict>
    <dict>
      <key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
      <key>NSPrivacyAccessedAPITypeReasons</key><array><string>C617.1</string></array>
    </dict>
    <dict>
      <key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategorySystemBootTime</string>
      <key>NSPrivacyAccessedAPITypeReasons</key><array><string>35F9.1</string></array>
    </dict>
  </array>
</dict>
</plist>
```

(The `SystemBootTime` entry is Sentry's, folded in because Sentry links
statically here — see above.)

### "The bundle version must be higher than the previously uploaded version"

Two consecutive uploads shipped the same `CFBundleVersion`. The classic
cause on a project shaped like this one is the version-injection gotcha,
and it is worth understanding even though **it is currently fixed**:
XcodeGen's *default* is to write **literal** `1.0` / `1` into the
generated `Info.plist` rather than `$(MARKETING_VERSION)` /
`$(CURRENT_PROJECT_VERSION)` references, and with literals in the plist
any approach that only sets *build settings* (agvtool,
`increment_build_number`, `xcargs`) never reaches the bundle — every
build ships as `1.0 (1)`, upload #1 succeeds, upload #2 is rejected.

`project.yml` overrides that default and the committed `Info.plist`
carries the references, so this is not the state of the repo today. If
someone deletes those two lines from `info.properties`, this is the
symptom you get — and the lane's `preflight_release` should hard-fail
first with instructions.

Diagnose from the artifact, not the source:

```bash
unzip -p FlashAirSync.ipa 'Payload/FlashAirSync.app/Info.plist' \
  | plutil -p - | grep -E 'CFBundleShortVersionString|CFBundleVersion'
```

If that shows `1.0` / `1` on a `v0.1.0` tag, the injection is broken —
see Phase 4's checklist item.

Also possible: `GITHUB_RUN_NUMBER` regressed. It is **repo-wide and
monotonic**, but it resets to 1 if a workflow file is renamed or
recreated. Never reset it; if you must, switch the build number to a
timestamp (`date -u +%Y%m%d%H%M`) or add an offset.

### The build never appears in TestFlight

fastlane went green, no email, nothing in ASC. In order:

1. Check **App Store Connect → your app → TestFlight → iOS Builds** for a
   build stuck in "Processing" — 5–30 minutes is normal, hours is not.
2. Check the email on the **Account Holder** address, not just yours —
   ITMS rejection mails go to the account contacts.
3. Check **Activity → All Builds**; a build that failed validation shows
   there with the reason.
4. If nothing at all: confirm the app record's bundle ID is exactly
   `us.v9n.flashair-sync` and that the API key's role is App Manager
   (step 6).

### "Missing Compliance" on every build

`ITSAppUsesNonExemptEncryption` isn't in the **built** plist. Remember
`Info.plist` is generated — putting it in the plist by hand is clobbered
on the next `xcodegen generate`. It goes in `project.yml` →
`targets.FlashAirSync.info.properties`.

### `GitCommitHash` shows `<sha>-dirty` in Settings → About

The working tree was dirty at archive time. The normal cause is that
`project.yml` was edited without regenerating and committing
`ios/FlashAirSync/FlashAirSync/Info.plist` — CI's own `xcodegen generate`
then mutates a tracked file mid-run. Fix: regenerate locally and commit
the plist. (The lane warns about this before building, so the run log
will name the offending file.)

If it shows `unknown` instead, git failed inside the build script — the
script degrades gracefully by design. Check that the workflow checks out
with `fetch-depth: 0`; a shallow checkout also means `git describe` prints
a bare short SHA instead of the tag.

### CI is red on `main` and it isn't you

`.github/workflows/ci.yml`'s mock-server "Test config endpoint" (`op=104`)
step has been failing since the M2 merge. It is unrelated to releases and
is tracked in `DEVELOPMENT.md`. Don't let the red badge stop a release
run — the release workflow is a separate file.

Three workflows exist and they are easy to confuse:

| File | Runs on | What red means |
|---|---|---|
| `ci.yml` | every push/PR, ubuntu | Android + mock server. Green as of 2026-10-29; not part of the release path either way |
| `ios-build.yml` | PRs and pushes touching `ios/**`, macOS | Unsigned build + the 8 unit tests. This one *is* about the app that ships. Reports **skipped**, not success, when a PR touches nothing under `ios/` |
| `release.yml` | a **published** GitHub Release (or `workflow_dispatch`) | The TestFlight upload. Nothing else triggers it |

---

## Things this document is not certain about

Flagged inline above; collected here so nothing gets laundered into
confident instruction:

- **Hotspot Configuration is self-serve** — high confidence (~95%) from
  Apple's capability matrix and DTS forum statements; the entitlement
  reference page itself could not be machine-read. Step 2 is its own
  test.
- **Whether `FileManager.attributesOfItem` actually trips the
  `FileTimestamp` scanner category.**
- **How long `upload_to_testflight` actually blocks** when
  `skip_waiting_for_build_processing: true` is paired with a non-empty
  `changelog:`. Nobody has run this pipeline yet; correct the estimate
  after run #1.
- **Whether Apple's privacy audit expects Sentry's per-install `user.id`
  declared under Identifiers → User ID** (step 14). The conservative
  answer is recommended there; the permissive one is common.
- **Whether a `github.com/.../blob/main/PRIVACY.md` URL has ever been
  rejected** as a privacy policy URL.
- **The App Review attachment size cap** (use a direct video link and it
  doesn't matter).
- **Whether EU DSA trader status also gates per-app at first submission.**
- **Beta App Review turnaround** — "2–7 days" is third-party reporting,
  not an Apple SLA.
- **The TestFlight "What to Test" limit** — 4000 characters is well
  attested through fastlane's behaviour, but not from an Apple doc, and
  there are reports Apple counts bytes for non-ASCII.
- **Whether `UIRequiresPersistentWiFi` suppresses the iOS Connection
  Assistant "no internet, switch?" prompt** (open question in
  `CLAUDE.md`). Assume it does not; warn users in-app and in the notes.
- **Whether the certificate in the local keychain is the same one
  baby-monitor's secret holds** — dates differ; check the portal.
- **Whether Xcode 26 will eventually require an Icon Composer `.icon`
  bundle** rather than `AppIcon.appiconset`. The appiconset is accepted
  today.
- **The trademark and discontinued-hardware review risks** are
  assessments, not observed outcomes.
- **This project's actual Sentry event retention.** `PRIVACY.md`
  deliberately says "under this project's retention settings" rather than
  naming a number, because nobody has read the number off the Sentry org
  settings. 90 days is the common default. If you want the policy to
  state a figure, go and confirm the real one first — a published privacy
  policy is the wrong place for a value you assumed.

---

## See also

- `PRIVACY.md` — the published privacy policy; the URL App Store Connect
  wants
- `docs/BETA-TESTING.md` — TestFlight notes template, telemetry defaults,
  pre-submission checklist
- `docs/REAL-WORLD-FINDINGS.md` — what real hardware does, and what
  testers and reviewers will actually hit
- `CLAUDE.md` "Local-environment Constraints" — XcodeGen, cleartext HTTP,
  signing notes
- `TODO.md` — the backlog, including the backgrounding fix that beta
  testers will report as a bug
- `ios/FlashAirSync/project.yml` — Info.plist source of truth; never edit
  the generated plist
- `fastlane/Fastfile`, `.github/workflows/release.yml` — the automation
  this document stops describing and starts pointing at
- `.github/workflows/ios-build.yml` — the PR-time unsigned build + tests;
  the cheap gate that catches most of what would otherwise fail a release
  run eight minutes in
- `ios/FlashAirSync/tools/make-icon.swift` — the deterministic recipe for
  the App Store icon, alpha constraint included
