# Roadmap

The product plan, by phase. Tick items as they land, and keep [HANDOFF.md](HANDOFF.md) in sync.

**Goal:** stop overpacking. FitMe knows your closet, suggests outfits that look good (color, formality, weather,
occasion), and packs the **smallest set of items that covers a trip**.

**Decisions so far:** personal tool first; native iOS; Claude vision for tagging and styling judgement; flat-lay
collages now, try-on later. The reasoning is in [DECISIONS.md](DECISIONS.md).

## Phase 0: Foundations ✅ (except signing)

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
- [ ] One-time account setup (Nadav): see [RELEASE_PROCESS.md](RELEASE_PROCESS.md#one-time-setup-owner-nadav).
- [ ] First TestFlight build of FitMe β on the phone.

## Phase 1: Closet capture (make-or-break)

Goal: catalog about 100 items in **under 60–90 minutes**, with at least 85% of tags right.

- [ ] `Services/ClaudeClient`:
  - Messages API over `URLSession`
  - image content blocks
  - JSON-schema structured output
  - a protocol with a fake
  - model IDs in one place (see the `claude-api` skill for current IDs)
- [ ] `Services/ImagePipeline`: Vision `VNGenerateForegroundInstanceMaskRequest` cutout → square padded PNG → OKLab
  k-means (k ≤ 3) colors with proportions.
- [ ] `ItemRecord`: add the photo and the cutout (`@Attribute(.externalStorage)`).
- [ ] `Features/Capture`:
  - batch camera ("shoot many in a row") and multi-select from Photos
  - concurrent pipeline
  - an "Inbox to review" with every field pre-filled
- [ ] Review screen: swipe through items, fix tags, confirm.
- [ ] Item detail and edit. Closet filters (category, color, formality, season).
- [ ] `ItemThumbnail` shows the cutout when one exists.

## Phase 2: Outfit engine in daily use

Goal: at least 70% of top-5 suggestions rated "I'd wear that" over two weeks.

- [ ] Flat-lay collage renderer (outerwear, top, bottom, shoes stacked; accessories at the side).
- [ ] `Services/WeatherService`: Open-Meteo current weather and forecast. Today's weather becomes automatic.
- [ ] Feedback on suggestions (👍 / 👎 / wore it / swap one item), persisted to `StyleProfile`.
- [ ] Claude stylist pass: re-rank the top 12–15 candidates and add a one-line "why it works". The model may only
  return candidate IDs.
- [ ] "Build around this item" from item detail (the engine already supports `mustInclude`).
- [ ] Engine taste fixes (see "Known engine issues" in [HANDOFF.md](HANDOFF.md)).

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
