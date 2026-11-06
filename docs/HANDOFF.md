# Handoff

**Read this first.** It's the single source of truth for "where are we and what's next". Whoever ends a work
session (person or agent) updates it before the final commit.

_Last updated: 2026-11-05._

## Current state

- **Phase 0 (foundations)** is done, and **Phase 1 (closet capture)** is built. Details are in
  [ROADMAP.md](ROADMAP.md).
- **Capture flow:**
  1. Closet → **+** → pick photos.
  2. Each photo becomes a `CaptureDraft`.
  3. `ImagePipeline` cuts out the item and measures colors, and `ClaudeTaggingService` tags it.
  4. The draft lands in the **Inbox** for review.
  5. **Add to closet** turns it into an `ItemRecord` with its photo and cutout.
- **`FitEngine`**:
  - Complete for daily suggestions and trip packing; 25 tests pass (`make test-engine`, about 1 s).
  - Swift 6 strict concurrency, no force unwraps.
- **App:**
  - Three tabs:
    - Today: occasion, feels-like temperature and rain → top 5 varied outfits.
    - Closet: grid by category, with color-swatch thumbnails until photos exist.
    - Settings: Claude API key in the Keychain, plus "Load demo closet" / "Clear closet" in staging.
  - Builds cleanly in Debug, Staging and Release.
  - `make verify-release` proves Release has no demo data. It was also checked against a Staging build, which it
    correctly rejects.
- **CI/CD:**
  - `.github/workflows/pipeline.yml` covers lint, engine tests, app tests, the Release guard, and deploy (staging on
    `main`, production on `v*` tags with approval).
  - Deploys skip with a notice until the App Store Connect secrets exist.
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

## Next steps, in order

1. **Confirm CI is green** on the latest `main` (`gh run list --limit 3`, then `gh run view <id> --log-failed`).
   Phase 1's app tests have only run there.
2. **Real-device trial of Phase 1** (Nadav, on FitMe β from TestFlight):
   1. Settings → paste the Claude API key.
   2. Closet → **+** → pick about 10 photos.
   3. Time the review, and note wrong tags and bad cutouts.
3. **Fix what the trial finds**, in this order:
   1. Cutout failures (photo tips: plain background, item laid flat).
   2. Tag errors: tune `ClaudeTaggingService.systemPrompt`, and add a regression test with the recorded response.
   3. Review speed: e.g. swipe gestures, or skipping straight to the next draft.
4. **Finish Phase 1 leftovers:** closet filters by color and formality. Build the in-app batch camera only if
   importing from Photos turns out too slow in practice.
5. **Then Phase 2** ([ROADMAP.md](ROADMAP.md#phase-2-outfit-engine-in-daily-use)): collage renderer, Open-Meteo
   weather, feedback buttons, and the Claude stylist pass. Reuse `ClaudeClient.structuredOutput`.

## Known engine issues (taste, not correctness)

Found by inspecting the fixture packing results. Fix them with a failing "should beat" test first.

- **Accent overuse:** the scorer rewards one accent color (0.95 against 0.85 for all neutrals), so a single
  statement bottom (red trousers) can end up in every work-trip outfit. Idea: add a statement-repeat penalty in
  `PackingOptimizer.adjusted`, and/or lower the accent bonus.
- **Bare legs in the cold:** dresses and skirts aren't weather-checked for legs, so a sundress can be suggested at
  7°C in the rain. Idea: treat one-pieces and skirts like shorts below about 12°C unless a future "tights" layer
  exists.
- **The fixture closet mixes menswear and womenswear,** so packing results mix polos and sundresses. A real closet
  won't. Don't tune weights to the fixture's quirks.

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
