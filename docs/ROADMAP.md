# Roadmap

The product plan, by phase. Tick items as they land, and keep [HANDOFF.md](HANDOFF.md) in sync.

**Goal:** stop overpacking. FitMe knows your closet, suggests outfits that look good (color, formality, weather,
occasion), and packs the **smallest set of items that covers a trip**.

**Decisions so far:** personal tool first; native iOS; Claude vision for tagging and styling judgement; flat-lay
collages now, try-on later. The reasoning is in [DECISIONS.md](DECISIONS.md).

## Phase 0: Foundations ✅

- [x] `FitEngine`:
  - color math
  - rules
  - scorer
  - generator
  - packing optimizer
  - style profile
  - 25 tests
- [x] Swift 6 strict concurrency, Swift Testing, SwiftFormat and SwiftLint, Makefile.
- [x] XcodeGen project with Debug, Staging and Release, separate bundle IDs, and staging and prod icons.
- [x] App shell:
  - Today (suggestions by occasion and weather)
  - Closet (grid by category)
  - Settings (Claude API key in Keychain, demo closet in staging)
- [x] CI/CD pipeline: lint, tests, Release demo-data guard, TestFlight deploy for staging and production.
- [x] One-time account setup (Nadav): see [RELEASE_PROCESS.md](RELEASE_PROCESS.md#one-time-setup-owner-nadav).
- [x] First TestFlight upload of FitMe β (Staging build 8, 2026-11-06).
- [ ] Install FitMe β from TestFlight on the phone (Nadav adds himself as an internal tester).

## Phase 1: Closet capture (make-or-break)

Goal: catalog about 100 items in **under 60–90 minutes**, with at least 85% of tags right.

- [x] `Services/Claude/ClaudeClient`:
  - Messages API over `URLSession`
  - base64 image blocks
  - `output_config.format` JSON schema
  - `fallbacks: "default"`
  - an `HTTPTransport` protocol faked in tests
- [x] `Services/Tagging`: `ClaudeTaggingService`
  - `claude-opus-5-5` at low effort; the model is one constant
  - schema generated from the engine's enums
  - out-of-range values rejected
- [x] `Services/ImagePipeline`:
  - Vision subject lift → 512 px transparent PNG cutout and a 1024 px JPEG on white for tagging
  - colors from the cutout via `FitEngine.ColorExtractor` (OKLab k-means)
  - falls back to the full photo when Vision can't lift a subject
- [x] `ItemRecord` stores the photo and the cutout (`.externalStorage`). New `CaptureDraft` model for unreviewed
  items.
- [x] `Features/Capture/CaptureModel`:
  - multi-select import from Photos
  - drafts saved before processing
  - three processed at a time
  - resumes after relaunch
  - retry on failure
- [x] Inbox and review:
  - each draft pre-filled
  - "Add to closet" jumps to the next draft
  - "Accept all" for drafts that look right
- [x] Item detail and edit (saved on leaving the screen), delete, laundry toggle. Closet filters by category, plus
  name search.
- [x] `ItemThumbnail` shows the cutout when one exists, including in Today's suggestions.
- [ ] **In-app batch camera.** Not built. Today's flow is to shoot items in the Camera app, then multi-select them in
  FitMe.
- [ ] Closet filters by color and formality (only category and search exist).
- [x] First real trial (Nadav, about 10 photos, 2026-11-06): tags fine and flow fast. Fixed:
  - worn photos kept the face and legs → crop to Claude's item box
  - the inbox looked empty during import → importing row and banner
  - re-adding created duplicates → SHA-256 fingerprints skip them
- [ ] Re-check worn-photo cutouts after the crop fix, and time a full closet (target under 90 minutes for 100
  items).

## Phase 2: Outfit engine in daily use

Goal: at least 70% of top-5 suggestions rated "I'd wear that" over two weeks.

- [x] Flat-lay collage (`UI/OutfitCollage`): top or one-piece over bottom on the left; outerwear, mid layer and
  shoes on the right. Used in `OutfitCard`.
- [x] `Services/Weather`:
  - Open-Meteo forecast for the current location, rounded to about 1 km, when-in-use permission
  - fills feels-like and rain on open
  - manual edits still work
- [x] Feedback: 👍 / 👎 / "Wear this" on every card.
  - Stored in `StyleProfileRecord` (affinities) via `FeedbackRecorder`.
  - "Wear this" updates `wearCount` and `lastWorn`, so novelty rotates items.
  - 👎 hides the outfit for the session.
- [x] Claude stylist (`Services/Stylist/ClaudeStylist`):
  - on demand ("Ask the stylist")
  - picks up to 3 of 12 engine candidates with one-line reasons
  - text-only descriptions with color names
  - the schema only allows candidate letters
- [x] "Outfits with this" from item detail (`TodayModel.anchor` → `mustInclude`).
- [x] Engine taste fixes: statement pieces rotate in packing, and light dresses stay out of the cold.
- [ ] "Swap one item" on a card. Not built.
- [ ] Two weeks of daily use to measure the goal (Nadav).

## Phase 3: Trip packer (the differentiator)

Goal: on a real trip, wear at least 90% of what's packed, while packing noticeably less than usual.

- [ ] Trip wizard: legs and cities, dates, per-day activities, laundry, luggage size.
- [ ] Open-Meteo forecast or climate normals per day.
- [ ] Packing result: "N items → M outfits", day-by-day collages, checklist with `Essentials`.
- [ ] Claude capsule review (missing or redundant items, weak days) as one-tap swaps.
- [ ] Trip mode: today's outfit, swap, mark worn. Post-trip debrief: what did you actually wear?

## Phase 4: Learning and insights

- [ ] Tune affinity learning.
- [ ] Never-worn items, "orphans" that match nothing, and gap suggestions ("one white sneaker unlocks 9 outfits").
- [ ] Saved favorite outfits, calendar hints.

## Phase 5: Virtual try-on (optional)

- [ ] Evaluate try-on APIs for cost, latency and accuracy, then add an optional "see it on me".

## Phase 6: Only if going public

- [ ] API key proxy with per-user limits, Sign in with Apple, CloudKit sync, privacy policy, App Store listing.
