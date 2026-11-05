# Handoff

**Read this first.** It's the single source of truth for "where are we and what's next". Whoever ends a work
session (person or agent) updates it before the final commit.

_Last updated: 2026-11-05._

## Current state

- **Phase 0 (foundations)** is done in code. See [ROADMAP.md](ROADMAP.md).
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

- **App unit tests run only in CI so far.** They passed on GitHub's runner (iPhone 17 Pro Max, iOS 26.5; pipeline run
  42122288461). This Mac has no iOS Simulator runtime: `xcodebuild -downloadPlatform iOS` failed twice with a
  MobileAsset catalog timeout. The first CI run caught two real bugs (unsigned test builds, and the demo closet reset
  missing unsaved items); both are fixed.
- **The app has never been launched or looked at** in a simulator or on a device. Only its tests and builds are
  verified.
- **The deploy job has never run for real.** It's blocked on the one-time Apple setup below. Expect to debug the
  first archive and upload (signing and App Store Connect app records).
- **The CI runner image** is `macos-26` with `latest-stable` Xcode. If GitHub's image lacks Swift 6.2 or later
  (`@concurrent` needs it), pin a newer image or Xcode version in `pipeline.yml`.

## Blocked on Nadav (one-time setup)

From [RELEASE_PROCESS.md → One-time setup](RELEASE_PROCESS.md#one-time-setup-owner-nadav), in this order:

1. Install the iOS Simulator runtime: Xcode → Settings → Components → iOS 27.x → Get. Then run `make test-app`.
2. Sign in to Xcode with the Apple ID and get the **Team ID**. Put it in `project.yml` (`DEVELOPMENT_TEAM`), or hand
   it to the agent.
3. Create the App Store Connect app records for both bundle IDs.
4. Create the GitHub environments `production` (with yourself as required reviewer) and `staging`. Do this **before**
   step 5.
5. Create an App Store Connect API key (Admin) and add the GitHub secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   `ASC_PRIVATE_KEY` and the variable `APPLE_TEAM_ID`.
6. Add yourself as an internal TestFlight tester for both apps.

## Next steps, in order

1. **Confirm CI is green** on the latest `main` (`gh run list --limit 3`, then `gh run view <id> --log-failed`). Fix
   anything red first.
2. **Once the setup above is done:** push any commit to `main`, watch the `deploy` job, and fix the signing or
   upload issues it reports. Then install FitMe β from TestFlight, load the demo closet, and check the Today tab.
3. **Start Phase 1** with `Services/ClaudeClient`:
   - Load the `claude-api` skill for the current Messages API shape and model IDs.
   - Define a `TaggingService` protocol that returns a decoded `Item` draft from an image, plus a fake for tests.
   - Read the key from `SecretStore` (`.claudeAPIKey`).
   - Unit-test request building and response decoding with recorded JSON fixtures; never call the network in tests.
4. Then `Services/ImagePipeline` (Vision cutout plus OKLab k-means), followed by `Features/Capture`. Follow the
   checklist in [ROADMAP.md → Phase 1](ROADMAP.md#phase-1-closet-capture-make-or-break).

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
