# Handoff

**Read this first.** It's the single source of truth for "where are we and what's next". Whoever ends a work
session (person or agent) updates it before the final commit.

_Last updated: 2026-11-06._

## Current state

- **Phases 0 to 2 are done, and Phase 3 (the trip packer) is built:** Trips tab, wizard, per-day weather, packing
  list, bag edits, swap, Claude's bag check, trip mode and debrief. Details are in [ROADMAP.md](ROADMAP.md) and
  [ARCHITECTURE.md](ARCHITECTURE.md#trip-packer-phase-3).
- **Redesign after Nadav's second trial (2026-11-06):**
  - Warm editorial design system (`UI/Theme.swift`, `UI/Components.swift`), applied to every screen.
  - Saved tab: ♥ saves.
  - ✕ hides with an Undo toast.
  - Toasts confirm every reaction.
  - Menswear demo closet with real product photos.
  - Fixed: liking no longer resets "Wear this".
- **Capture flow:**
  1. Closet → **+** → pick photos.
  2. Each photo becomes a `CaptureDraft`.
  3. `ImagePipeline` cuts out the item and measures colors, and `ClaudeTaggingService` tags it.
  4. The draft lands in the **Inbox** for review.
  5. **Add to closet** turns it into an `ItemRecord` with its photo and cutout.
- **`FitEngine`**:
  - Complete for daily suggestions and trip packing; 42 tests pass (`make test-engine`, about 2 s).
  - Swift 6 strict concurrency, no force unwraps.
- **App:**
  - Five tabs:
    - Today: weather, occasion and feels-like → top 5 varied outfits, plus the stylist; links to a trip in progress.
    - Trips: plan, pack, edit the bag, trip mode, debrief.
    - Saved: outfits saved with ♥.
    - Closet: grid by category with item photos, the capture Inbox, item detail.
    - Settings: Claude API key in the Keychain, plus "Load demo closet" / "Clear closet" in staging.
  - Builds cleanly in Debug, Staging and Release.
  - `make verify-release` proves Release has no demo data. It was also checked against a Staging build, which it
    correctly rejects.
- **CI/CD:**
  - `.github/workflows/pipeline.yml` covers lint, engine tests, app tests, the Release guard, and deploy (staging on
    `main`, production on `v*` tags with approval).
  - Every push to `main` uploads a Staging build to TestFlight. The production path (tag → approval → upload) has
    not run yet.
- **Docs:**
  - [ENGINEERING_STANDARDS.md](ENGINEERING_STANDARDS.md): the rules for all code.
  - [RELEASE_PROCESS.md](RELEASE_PROCESS.md): branching, environments, the pipeline, one-time setup.
  - [ARCHITECTURE.md](ARCHITECTURE.md), [DECISIONS.md](DECISIONS.md), [CHANGELOG.md](../CHANGELOG.md).

## Not verified yet

- **App unit tests run only in CI so far.** The pipeline is green on `main` (run 42128248879: lint, engine tests,
  app tests on an iPhone 17 Pro Max with iOS 26.5, the Release guard, and the deploy skip notice). This Mac has no
  iOS Simulator runtime: `xcodebuild -downloadPlatform iOS` failed twice with a MobileAsset catalog timeout.
- **What CI caught along the way, all fixed:**
  - unsigned simulator test builds (no Keychain entitlement, read-only store)
  - the demo closet reset missing unsaved items
  - a flaky test comparing JSON encodings of a `Set`
- **GitHub environments:** the workflow auto-created `staging`, which has no rules and that's intended.
  `production` doesn't exist yet; create it with a required reviewer before adding any secrets.
- **CI quirk:** one deploy job failed with "Unable to fetch the information for the environment" during a GitHub
  macOS capacity incident, and passed on rerun. If it recurs, rerun with `gh run rerun <id> --failed`.
- **The app has been launched only once,** on Nadav's iPhone (Staging, installed from a local signed build on
  2026-11-06). No UI tests exist yet.
- **The staging deploy works end to end.** Run 42159671605 archived with cloud signing and uploaded Staging build 8
  to App Store Connect. Gotcha: `ASC_PRIVATE_KEY` must be set from the file with a `<` redirect. Pasting into gh's
  prompt keeps only one line, and `deploy.sh` now rejects that with a clear message.
- **The production deploy (tag → approval → upload) has not run yet.** The first `make release` will be its test.
- **The CI runner image** is `macos-26` with `latest-stable` Xcode. If GitHub's image lacks Swift 6.2 or later
  (`@concurrent` needs it), pin a newer image or Xcode version in `pipeline.yml`.

## Account setup (done 2026-11-06)

All done except TestFlight testers. Details are in
[RELEASE_PROCESS.md → One-time setup](RELEASE_PROCESS.md#one-time-setup-owner-nadav).
- Team `4ARX779852` is in `project.yml` and the GitHub variable `APPLE_TEAM_ID`.
- Nadav's iPhone 16 Pro (UDID `00008140-000129522413C01C`) is registered.
- Both bundle IDs are registered.
- App records: **FitForMe** (production) and **FitMe Staging**.
- GitHub `production` environment: requires Nadav's approval, `v*` tags only.
- Secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` are set (key "FitMe CI", Admin).

Still open for Nadav:
1. Install the iOS Simulator runtime through Xcode → Settings → Components → iOS → Get. The command-line
   `xcodebuild -downloadPlatform iOS` hangs at the catalog step on this Mac, even outside the agent sandbox (tried
   four times). Then run `make test-app`.
2. After the first TestFlight upload, add yourself as an internal tester in each app's TestFlight tab and install
   TestFlight on the iPhone.

To run a local build on the phone (with the phone connected):

```bash
xcodebuild -project FitMe.xcodeproj -scheme FitMe-Staging -configuration Staging -destination 'id=00008140-000129522413C01C' -allowProvisioningUpdates -allowProvisioningDeviceRegistration -derivedDataPath DerivedData build
```
```bash
xcrun devicectl device install app --device 00008140-000129522413C01C DerivedData/Build/Products/Staging-iphoneos/FitMe.app
```

## Phase 1: what's verified and what isn't

- **Verified locally:**
  - 32 engine tests pass, including `ColorExtractor`.
  - The app and tests build with no warnings, lint is clean, and `verify-release` passes.
- **Verified only by CI** (this Mac still has no simulator runtime): the app tests, green in run 42164034673, which
  also uploaded **Staging build 11**.
  - `ClaudeClientTests`, `TaggingServiceTests`, `CaptureModelTests`, `ImagePipelineTests`.
  - They use fake transports and processors, so no real API call has been made yet.
  - The first CI run caught a real bug: resume-after-relaunch never found its drafts, because of the SwiftData enum
    predicate pitfall now noted in the standards. It's fixed.
- **Not verified at all:**
  - A real Claude call. Needs Nadav's API key in Settings on the phone.
  - Vision subject lift on real photos. The CI simulator may fall back to the full photo.
  - The full capture UI flow on a device.
  - The Phase 1 goals: 100 items in under 90 minutes, and at least 85% of tags right.

## First real-closet trial (2026-11-06) and fixes

- **Nadav's feedback:** tags fine, flow fast. Two problems, both fixed:
  - Worn photos kept face and legs in the cutout. Now cropped to the `itemBox` that Claude returns with the tags.
  - The inbox looked empty while photos loaded, which led to adding them twice. Now there's an "Importing N
    photos…" row, and fingerprinting skips duplicates.
- **Not re-verified on the phone yet:** the crop fix on real worn photos (arms and hands inside a top's box are
  expected to stay).

## Phase 2: what's verified and what isn't

- **Verified locally:**
  - 34 engine tests pass, including the two new taste rules.
  - The app and tests build without warnings, lint is clean, and `verify-release` passes.
- **Verified only by CI:** `TodayModelTests`, `FeedbackRecorderTests`, `WeatherServiceTests`, `StylistTests`, all
  green in run 42167171629, which also uploaded **Staging build 15**. The trial fixes (crop, import progress,
  duplicates) shipped in build 13 (run 42166272190).
- **Not verified at all:**
  - A real Open-Meteo call, and the location permission prompt.
  - A real stylist call, and its quality.
  - Collage looks on a device.
  - The Phase 2 goal: at least 70% of suggestions rated "I'd wear that" over two weeks.

## Verified in the simulator (2026-11-06, iPhone 18 Pro, iOS 27.2)

This Mac now has the iOS Simulator runtime, so `make test` runs everything locally.
- All engine and app suites pass.
- Checked by driving the app and taking screenshots:
  - live Open-Meteo weather (simulated Tel Aviv location) with automatic rain
  - location permission prompt text
  - demo closet with photos in Closet and Today
  - ♥ → Saved tab
  - ✕ removes the card
  - "Wear this" → "Worn today" with ♥ still filled
  - toast above the tab bar
  - Settings
- **Not verified:**
  - Inbox, review and item-detail screens in the new style (they only got theming; worth a look)
  - a real stylist call (needs an API key)
  - dark mode
- **Simulator tips:**
  - Grant location with `xcrun simctl privacy <device> grant location io.github.nadavkrashin.fitme.staging`; it
    restarts the app.
  - System alerts don't receive simulated taps.
  - Screenshots can lag about one action, so wait about a second.

## Phase 3: what's verified and what isn't

- **Verified locally:** 42 engine tests and every app suite pass, including 7 new trip suites (weather, layout,
  planner, both screen models, the reviewer, storage compatibility). Lint is clean.
- **Verified in the simulator** (Staging Debug build, demo closet, live Open-Meteo):
  - city search
  - real forecasts for the next days, and "typical" weather for past dates
  - packing a 7-day Lisbon & Porto trip (13 pieces → 64 outfits; carry-on with laundry every 3 days: 9 → 32)
  - tick-off persists across a repack
  - "Leave at home" with Undo, swap, edit and repack (plans kept)
  - trip mode wear, the Today card, the debrief ("You wore 6 of 9")
  - the stylist check's missing-key message
- **Found and fixed while testing:**
  - "Pack my bag" only popped back a step (pushed view's `dismiss`); the sheet now closes.
  - City search wasn't focused.
  - Swap offered near-copies (same shirt, other shoes); `OutfitGenerator.alternatives` now leads with another top.
  - Leaving a top out hid that a plan now repeats a top; repeats are flagged.
  - The debrief didn't pre-tick worn pieces (`onAppear` in a sheet); it now initializes its state.
- **Not verified:**
  - a real "Check my bag" call (needs the API key) and the quality of its suggestions
  - multi-stop trips more than 16 days out (archive path only tested on past dates and in unit tests)
  - dark mode on the trip screens
  - packing speed on a phone with a full 150-item closet (about 1.5 s for the fixture in Debug on a Mac)

## Next steps, in order

1. **Confirm CI is green** and TestFlight got the build (`gh run list --limit 3`).
2. **Nadav tries trips on FitMe β:**
   - load the demo closet, plan a real upcoming trip, and judge the bag and the day plans
   - add the Claude API key and tap "Check my bag"; judge the suggestions
   - on the trip: wear from "Today in…", then do the debrief at home
3. **Fix what that finds.** Likely candidates:
   - the day planner's 8 occasion chips per day make long trips a long scroll; consider presets ("same as
     yesterday", "all casual")
   - per-day manual weather edits (today a failed fetch falls back to mild days with a warning)
   - the statement floral shirt still leads many casual and travel plans; it may need a gentler share of the plan
4. **Leftovers from earlier phases:** "swap one item" on a Today card (the engine's `alternatives` is a start), closet
   filters by color and formality, the in-app batch camera, and a dark-mode pass.
5. **Phase 4** ([ROADMAP.md](ROADMAP.md#phase-4-learning-and-insights)): never-worn items, orphans, gap suggestions.

## Known engine issues (taste, not correctness)

- **Fixed in Phase 2 (2026-11-06), each with a test:**
  - Statement pieces now rotate like tops in packing (`StatementRotationTests`).
  - Light dresses are excluded below 15°C (`LegCoverageTests`).
- **Open:** in the menswear demo closet the statement floral shirt is often the first pick for casual and travel
  plans. One statement piece per outfit is allowed and scored as neutral; whether it should appear less often is a
  taste call for Nadav.
- **Open:** the fixture closet mixes menswear and womenswear, so packing results mix polos and sundresses. A real
  closet won't. Don't tune weights to the fixture's quirks.

## Conventions every session must follow

- Read [ENGINEERING_STANDARDS.md](ENGINEERING_STANDARDS.md) before writing code. `make lint test` before every
  commit.
- Commit to `main` and **push right away** (the owner pre-authorized this). Avoid branches unless a change is risky;
  delete them after merging.
- Never edit `FitMe.xcodeproj`; edit `project.yml` and run `make project`.
- At the end of a session:
  - update this file (state, what wasn't verified, next steps)
  - tick [ROADMAP.md](ROADMAP.md)
  - add user-visible changes under `Unreleased` in [CHANGELOG.md](../CHANGELOG.md)
  - log any new decision in [DECISIONS.md](DECISIONS.md)
