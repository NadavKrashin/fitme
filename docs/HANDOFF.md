# Handoff

**Read this first.** It's the single source of truth for "where are we and what's next". Whoever ends a work
session (person or agent) updates it before the final commit.

_Last updated: 2026-11-14._

## Current state

- **Phases 0 to 2 are done, Phase 3 (the trip packer) is built, and Phase 4 (learning and insights) is built:**
  - Phase 3: Trips tab, wizard, per-day weather, packing list, bag edits, swap, Claude's bag check, trip mode and
    debrief.
  - Phase 4: reactions that visibly move suggestions, color-pairing learning, Closet → Insights, and calendar
    hints on Today.
  - Details are in [ROADMAP.md](ROADMAP.md) and [ARCHITECTURE.md](ARCHITECTURE.md#learning-and-insights-phase-4).
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
  - Complete for daily suggestions, trip packing and closet analysis; 58 tests pass (`make test-engine`, about
    5 s).
  - Swift 6 strict concurrency, no force unwraps.
- **App:**
  - Five tabs:
    - Today: weather, calendar hints, occasion and feels-like → top 5 varied outfits, plus the stylist; links to a
      trip in progress.
    - Trips: plan, pack, edit the bag, trip mode, debrief.
    - Saved: outfits saved with ♥.
    - Closet: grid by category with item photos, the capture Inbox, item detail, and Insights.
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

## Phase 4: what's verified and what isn't

- **Verified locally:** 58 engine tests (new `LearningTests`, `ColorFamilyTests`, `AnalyzerTests`) and every app
  suite (new `InsightsModelTests`, `OccasionHintTests`, `TodayCalendarTests`) pass. Lint is clean.
- **Verified in the simulator** (Debug build, demo closet):
  - Today's calendar card: the "Plans today?" prompt, then two seeded events ("Gym" → Sport, "Dinner with Dana" →
    Date); "Dress for it" switches the occasion with a toast.
  - Insights: "50 pieces, 876 looks", workhorses (camel quarter-zip in 90 looks), resting pieces with "Never worn" /
    "Last worn 3 months ago", the taste card, and "Forget what FitMe learned" with its confirmation and toast.
  - A profile saved before this change (no color pairings) still loads.
- **Found and fixed while testing:** the first gap finder said a camel overcoat "unlocks 48 looks" although the demo
  closet already has a warm coat. Gaps now count only outfits the closet can't already make on some kind of day,
  with a test (`aCoatCountsForTheColdDaysItOpensUp`). The demo closet now shows "Nothing to buy".
- **Not verified:**
  - the system calendar permission prompt (simulator alerts don't take taps; access was granted with `simctl`)
  - the gap card with real gaps in the app (covered by engine tests and the earlier screenshot of its layout)
  - "You like / You skip" color pairings on screen (they need several reactions; covered by `LearningTests`)
  - analysis speed on a phone with a 150-piece closet (about 2 s for 134 items in a Mac release build)
  - whether learning feels right over weeks of real use
- **Simulator tip:** to test calendar hints, grant access with
  `xcrun simctl privacy <device> grant calendar io.github.nadavkrashin.fitme.staging`. The Calendar app's own
  first-run alerts can't be dismissed by taps, so seed events from a throwaway test in the app's test host instead.

## Nadav's Phase 4 trial (2026-11-13) and fixes

- **What he found, all fixed:**
  1. "Dress for it" marked every event with the same occasion. The model now tracks the event that was tapped
     (`TodayModel.isDressing(for:)`, test `onlyTheTappedEventIsMarked`).
  2. A workhorse in Insights bounced back before opening. Insights was pushed by destination and the rows by value;
     the Closet stack now pushes only values (`ClosetView.Route`). There is no UI test for this; it was checked in
     the simulator.
  3. "Worn today" was unclear, could not be undone, and wasn't shown anywhere. Wears are now stored
     (`WearEntry`): Today shows "Today you're wearing", "Wearing today" toggles back, Undo is offered, and
     Saved → Worn lists the history.
  4. A jacket over a cardigan over a shirt at 20°. New rule: only one layer at 14° and above (`LayeringTests`
     failed first, then passed).
  5. No way to see an outfit's pieces. New detail sheet from any outfit card.
- **Verified in the simulator:** a single layer at 20°, the detail sheet, wear → "Wearing today" with Undo,
  Saved → Worn, and a workhorse opening the item in one tap. 60 engine tests and every app suite pass.
- **Not verified:** the calendar fix on screen with three same-occasion events (covered by the test), and wear
  history across midnight (entries are grouped by the phone's calendar day).
- **Compiler note:** Swift 6.4.2 crashes on `try #require(x)()` in a test; bind the result first, then call it.
- **CI signing fix:** run 43544335491 failed to deploy because the account hit Apple's certificate limit. Every
  runner had signed the archive with automatic signing, creating a new Apple Development certificate each time.
  `deploy.sh` now archives unsigned and signs only at export (cloud-managed distribution). Run 43545495413
  uploaded **Staging build 21**.
- **For Nadav (optional):** the Apple Developer account still holds the old CI-made development certificates
  ("Created via API"). They're unused; revoke them under Certificates if you want the slots back.

## Find online (2026-11-14)

- **What it does:** Inbox → review a draft → **Find online** → type brand, item, style number or notes (or paste a
  link) → browse to the product page in the app → **Use this page** → pick a photo → the draft gets the shop's photo,
  re-cut and re-tagged with the shop's listing. Brand and product page show under "Found online" on the review and
  item screens. Details in [ARCHITECTURE.md](ARCHITECTURE.md#find-online).
- **Verified locally:** lint clean; 132 app tests and all engine tests pass (new `ProductQueryTests`,
  `ProductPageTests`, and product-photo tests in `CaptureModelTests` and `TaggingServiceTests`).
- **Verified in the simulator** (Debug, no API key): search form → DuckDuckGo results in the app → the search page
  and a category page are refused with a hint → Everlane product page → name "The Essential Organic Crew | Deep
  Navy" read → photo grid → flat shot downloaded, cut out, and shown on the review screen with "Found online" and a
  toast. Found and fixed: the search results page itself was accepted as a product (`ProductQuery.isSearchPage`).
- **Not verified yet:**
  - re-tagging from the listing with a real Claude call (the simulator has no API key)
  - J.Crew, Uniqlo, COS, Levi's or Ralph Lauren pages in the app browser (they refused plain requests; a real
    browser may well get through, but untested)
  - on a phone
- **Closet items (later the same day):** item detail has the same flow, with Undo in the toast. A card replaces the
  bare button: unmatched it says "Use the shop's photo" and what that means; matched it says "Matched to <brand>"
  with "View page" and "Change". Verified: 136 app tests (4 new for closet items: history kept, exact Undo, tagging
  failure, failed download); in the simulator, both card states and the sheet's new explanation. Not run end to end
  on a closet item in the simulator (the unit tests cover applying it).
- **Gotcha found:** a button in the same list row as a `NavigationLink` never fires (the row takes the tap); the
  card has its own row.
- **Known rough edges:** shop pop-ups (Everlane's "20% off") cover the page until closed; some listed photos fail
  to load in the grid.

## Next steps, in order

0. **Try Find online on real items** on the phone with the API key: J.Crew, Uniqlo, Levi's and COS especially, and
   judge the re-tags.

1. **Confirm CI is green** and TestFlight got the build (`gh run list --limit 3`).
2. **Nadav tries trips and insights on FitMe β:**
   - load the demo closet, plan a real upcoming trip, and judge the bag and the day plans
   - add the Claude API key and tap "Check my bag"; judge the suggestions
   - on Today, tap "Use my calendar"; check the hints for real events
   - react to a week of suggestions, then look at Closet → Insights → Your taste
   - on the trip: wear from "Today in…", then do the debrief at home
3. **Fix what that finds.** Likely candidates:
   - the day planner's 8 occasion chips per day make long trips a long scroll; consider presets ("same as
     yesterday", "all casual")
   - per-day manual weather edits (today a failed fetch falls back to mild days with a warning)
   - the statement floral shirt still leads many casual and travel plans; it may need a gentler share of the plan
   - keyword coverage for calendar hints (titles that should map to an occasion but don't)
4. **Leftovers:** calendar hints in the trip wizard, "swap one item" on a Today card (the engine's `alternatives` is
   a start), closet filters by color and formality, the in-app batch camera, and a dark-mode pass.
5. **Phase 5** ([ROADMAP.md](ROADMAP.md#phase-5-virtual-try-on-optional)): evaluate virtual try-on, only if wanted.
