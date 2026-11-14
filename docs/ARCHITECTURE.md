# Architecture

FitMe is a local-first iOS app with two layers:
- **`FitEngine`**, a pure Swift package that decides what looks good and what to pack.
- **The app**, a thin SwiftUI shell around it: UI, persistence, networking and wiring.

```
┌──────────────────────────── FitMe app (SwiftUI, iOS 17+) ────────────────────────────┐
│  Features/Today   Features/Closet   Features/Settings   (Phase 1+: Capture, Trips)    │
│        │                │                  │                                          │
│        ▼                ▼                  ▼                                          │
│   TodayModel      @Query ItemRecord   SettingsModel ──► SecretStore (Keychain)        │
│        │           (SwiftData)                                                        │
│        │   ItemRecord ⇄ Item mapping                                                  │
└────────┼──────────────────────────────────────────────────────────────────────────────┘
         ▼
┌──────────────── FitEngine (pure Swift, no UI / SwiftData / network) ─────────────────┐
│  ColorMath (OKLab/OKLCH, neutrality)                                                 │
│  Item, Outfit, Occasion, Weather, TripDay           ← value types, Sendable          │
│  Rules (hard filters) → OutfitScorer (soft 0–100) → OutfitGenerator (beam search)    │
│  PackingOptimizer (greedy capsule + day plan)        StyleProfile (learned affinity) │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## Repository layout

| Path | What lives there |
|---|---|
| `project.yml` | XcodeGen spec: targets, the three build configurations, bundle IDs. `FitMe.xcodeproj` is generated and git-ignored. |
| `FitMe/App/` | `FitMeApp` (entry), `RootView` (tabs), `AppDependencies` (service container), `AppEnvironment` (staging/prod switch). |
| `FitMe/Features/<Feature>/` | One folder per screen: the SwiftUI view plus its `@Observable` model. |
| `FitMe/Models/` | SwiftData `@Model` types: `ItemRecord` (closet item, photo and cutout), `CaptureDraft` (unreviewed photo), `StyleProfileRecord` (learned taste), `SavedOutfit` (♥ outfits), and `Persistence` (store setup). |
| `FitMe/Services/` | Side-effecting services behind protocols: `SecretStore` (Keychain), `Claude/ClaudeClient` (Messages API over an `HTTPTransport`), `Tagging/ClaudeTaggingService`, `ImagePipeline` (Vision cutout, box crop, colors), `Weather/OpenMeteoWeatherService` + `CoreLocationLocator`, `Stylist/ClaudeStylist`. |
| `FitMe/UI/` | Design system (`Theme` tokens, `Components`: cards, pills, toasts, `ChipButton`), shared views (`ItemThumbnail`, `OutfitCollage`/`OutfitCard`, `ItemEditorSections`), display helpers, `PreviewData` (Debug only). |
| `FitMe/DemoData/` | Staging-only menswear demo closet (`DemoCloset.json`) and its product-photo cutouts (`Images/demo-<id>.png`). Excluded from Release. |
| `FitMe/Resources/` | Asset catalog: app icons (prod and staging) and the accent color. |
| `FitMeTests/` | App unit tests (Swift Testing), run in the Debug configuration. |
| `Packages/FitEngine/` | The engine and its tests, plus a frozen fixture closet. |
| `scripts/` | Release, deploy, verification and icon scripts used by `make` and CI. |
| `.github/workflows/pipeline.yml` | The single CI/CD pipeline. |
| `docs/` | This documentation. Start with [HANDOFF.md](HANDOFF.md). |

## The engine

| Stage | File | Role |
|---|---|---|
| Color | `ColorMath.swift` | Converts hex to perceptual OKLab/OKLCH. Classifies colors as neutral (black, white, grey), soft neutral (navy, denim, camel, khaki, olive) or chromatic. |
| Hard rules | `Rules.swift` | Removes items or outfits that are never acceptable: structure, a formality spread of 3 or more, occasion formality, required sportswear, dress shoes for formal events, warmth against temperature, rain or cold limits, and a jacket over a mid layer above 14° (`Weather.allowsStackedLayers`). |
| Soft score | `Scorer.swift` | Weighted 0–100 score from color harmony, pattern balance, formality cohesion, occasion fit, weather fit, silhouette balance, statement-piece budget and novelty, then moved by up to `learnedPoints` (8) by learned taste, never past 0 or 100. The weights are in `ScoreWeights`. |
| Generation | `OutfitGenerator.swift` | Beam search: bases (top+bottom or one-piece) → shoes → mid layer → outerwear, keeping the best partial outfits at each step. `suggest` picks a varied top N, each with a different top. `allOutfits` is exhaustive, for small pools. |
| Packing | `PackingOptimizer.swift`, `Trip.swift` | Groups trip slots by occasion and weather band. Greedily adds the item with the best marginal gain per packing cost, falling back to injecting a whole outfit. Prunes redundant items, then assigns outfits to days. A top or one-piece is used once per laundry cycle. |
| Learning | `StyleProfile.swift`, `ColorFamily.swift` | Item-pair affinities from ♥ / ✕ / "wore it", plus slower color-family pair affinities ("navy with white") that carry a liked look over to other pieces. Pair opinions add up through `tanh`, so a liked outfit as a whole moves more than one sharing a single pair. |
| Closet analysis | `ClosetAnalyzer.swift`, `GapCatalog.swift` | Searches every piece in 17 typical kinds of day (4 occasions × 4 temperatures, plus a beach day) and counts its looks (base and shoes, layers aside). Finds hard-to-style pieces (under 3 looks) and staples from `GapCatalog` that would add outfits the closet can't make yet. |

**Determinism:** everything sorts with an id tie-breaker, so the same input gives the same output. Tests depend on
this.

**Performance:** a 66-item closet runs a daily suggestion in about 0.1 s and a 10-day packing plan in under 1 s
(debug build). The app runs suggestions off the main actor (`TodayModel.suggest` is `@concurrent`).

## App data flow

1. SwiftData stores `ItemRecord`s. Views read them with `@Query`.
2. `ItemRecord.item` maps each record to an engine `Item`.
3. Feature models (`TodayModel`) call the engine with `[Item]` plus context and publish the results.
4. Services come from `AppDependencies` through `@Environment(\.dependencies)`. The live default uses the Keychain;
   previews and tests inject fakes (`InMemorySecretStore`).

## Environments

- **Debug and Staging** define `STAGING`: bundle ID `…fitme.staging`, display name "FitMe β", orange icon, demo
  closet available.
- **Release** is production: bundle ID `…fitme`. The demo closet resource is excluded and its code is compiled out;
  `scripts/verify-release.sh` enforces this.
- See [RELEASE_PROCESS.md](RELEASE_PROCESS.md).

## Capture pipeline (Phase 1)

```
PhotosPicker ─► CaptureModel.importPhotos ─► CaptureDraft(.processing) saved first
                     │  (3 at a time, off the main actor)
                     ├─► ImagePipeline.process ─► photo JPEG, cutout PNG, tagging JPEG, colors (FitEngine.ColorExtractor)
                     └─► ClaudeTaggingService.tags ─► ItemTags (JSON schema built from the engine enums)
                     ▼
           CaptureDraft(.ready / .failed) ─► Inbox ─► DraftReviewView ─► ItemRecord (closet)
```

- **Colors** come from pixels, never from the model. The model tags category, pattern, formality, warmth, fit,
  style and water resistance.
- **Drafts live in their own model** so unreviewed items never reach the closet or the engine.
- **`CaptureModel` lives at app level,** so processing continues across screens and resumes after relaunch.

### Find online

```
DraftReviewView ─► FindOnlineView (brand, item, style number, notes, or a pasted link)
                     └─► ProductQuery.destination ─► ProductBrowserView (visible WKWebView, the owner browses)
                            └─► "Use this page" ─► PageSnapshot (JS) ─► ProductPage (schema.org Product, og: tags, big images)
                                   └─► ProductPickView ─► CaptureModel.useProductPhoto
                                          ─► download ─► ImagePipeline ─► ClaudeTaggingService(listing:) ─► draft
```

- **The owner drives the browser.** Nothing is fetched from a shop except the page they open and the one photo they
  pick, so there is no scraping and no bot protection to get around.
- **Parsing is in Swift** (`ProductPage`), so it is unit-tested; the page script only collects raw data.
- **The shop's listing is sent to the tagger as text** and is trusted over the photo for type, material and fit.
- **The original photo is kept** (`originalImage`); brand and product URL are stored on the draft and the item.
- **Closet items** use the same sheet. `CaptureModel.useProductPhoto(…for: ItemRecord)` keeps the item's id, wear
  history and laundry state, and returns an `ItemRecord.Snapshot` for Undo.
- **`ProductMatchCard`** (`UI/`) is the one entry point on both screens: it explains the feature when unmatched and
  shows the brand, "View page" and "Change" once matched.

## Daily outfits (Phase 2)

- **`TodayModel`** owns the inputs (occasion, feels-like, rain), the suggestions, the session's reactions, and the
  weather and stylist state.
  - With `anchor` set, the same model powers "Outfits with this item".
  - `OutfitPlanner` is the shared view.
- **Weather:** `OpenMeteoWeatherService.forecastHere()` (location rounded to about 1 km) pre-fills the inputs on open.
- **Feedback:** `FeedbackRecorder` writes reactions to `StyleProfileRecord`, saved outfits to `SavedOutfit`, and
  wear history to `ItemRecord`. The profile feeds `OutfitContext.profile`, so liked pairs score higher next time.
  - `TodayModel` keeps hidden and worn as separate sets.
  - Every reaction publishes a `Toast`; ✕ includes an undo.
- **Look:** every color, font and shape comes from `UI/Theme.swift`, and screens compose `UI/Components.swift`.
  Tabs: Today, Trips, Saved, Closet, Settings.
- **Stylist:** `ClaudeStylist.pick` gets 12 diversified engine candidates as labeled text and returns up to 3
  label-constrained picks with reasons.

## Trip packer (Phase 3)

- **Data:** `TripRecord` stores a `TripDetails` value as JSON, with its dates mirrored as columns for sorting.
  - `TripDetails` holds the plan the user made (stops with nights, start date, laundry, luggage, one `TripDayPlan`
    per day with occasions and `DailyWeather`).
  - It also holds what FitMe made from it: packed item ids, one `PlannedOutfit` per occasion per day, the
    packing-list ticks, and the `TripDebrief`.
  - `laidOut()` turns stops and nights into days (one per night plus the day home). Days point at their stop by id,
    and keep their occasions and weather when an edit doesn't change them.
- **Weather:** `OpenMeteoTripWeather` searches cities (Open-Meteo geocoding) and returns per-day weather.
  - Days within 16 days use the forecast.
  - Later or past days use "typical" weather: the same dates averaged over the last 3 years from the archive API,
    with rain chance as the share of those years it rained.
  - The engine dresses each day for the middle of its feels-like range (`DailyWeather.dressFor`).
- **Packing:** `TripPlanner` wraps the engine off the main actor.
  - `pack` runs `PackingOptimizer.pack` with the luggage limits (carry-on: 2 shoes, 1 coat), laundry, the style
    profile, and `packedUnworn` from finished trips.
  - `replan` runs `PackingOptimizer.plan(packed:)` after the user leaves an item out, brings one, or applies a
    stylist change. Worn outfits are kept.
  - `alternatives` powers Swap via `OutfitGenerator.alternatives(to:)`, which leads with a different top.
  - `markingRepeats` flags outfits that repeat a top or statement piece within a laundry cycle.
- **Screens:**
  - `TripsView`: the list.
  - `TripWizardView` with `TripWizardModel`: stops, dates, laundry and luggage, then each day's occasions, then pack.
  - `TripDetailView` with `TripModel`: headline, trip mode ("Today in…", wear, swap), days, packing list,
    stylist check, debrief.
  - Today shows a card linking to a trip in progress.
- **Stylist check:** `ClaudeCapsuleReviewer` sends the day plan, the packed pieces (`P1…`) and the rest of the
  closet (`C1…`) as text. The schema only allows those labels (or `none`), so every suggested change maps to a real
  item and applies with one tap through `TripModel.apply`.
- **Learning:** a finished trip's debrief records what was worn. Each trip an item came home unworn adds a third to
  its packing cost (`PackingOptions.packedUnworn`).

## Learning and insights (Phase 4)

- **Taste:** `FeedbackRecorder` still records every reaction, now into item pairs and color-family pairs. One ✕
  drops an outfit out of the next day's top five, and one ♥ brings a look just outside it in (engine tests
  `LearningTests`). `resetLearning()` deletes the profile; saved outfits and wear history stay.
- **Insights screen:** Closet → Insights (`InsightsView`, `InsightsModel`). The analysis runs off the main actor
  (about 0.25 s for the 50-piece demo closet in a release build) every time the screen opens or the closet changes.
  Sections:
  - the headline (pieces and looks)
  - best next buy
  - hard to style
  - workhorses
  - resting (never worn after 14 days, or not worn for 60)
  - your taste, with learned color pairings and "Forget what FitMe learned"
- **Wear history:** `FeedbackRecorder.wear` writes a `WearEntry` (outfit, occasion, date, and each piece's earlier
  `lastWorn`) and `unwear` reverses it exactly. Today shows today's entries and toggles "Wearing today"; Saved →
  Worn lists every entry by day.
- **Outfit detail:** `OutfitDetailView` (a sheet from any outfit card in Today, Saved, Worn or a trip day) lists the
  pieces in wearing order with colors, dress code, warmth and fit, each linking to its item.
- **Closet filters:** `ClosetFilter` (category, search, colors, dress codes, brands; any pick within a kind, all
  kinds together) and `ClosetFilterSheet`.
- **Swap one item:** `OutfitGenerator.swaps(replacing:in:from:context:)` (same slot, plus going without a layer);
  `OutfitDetailView.Swapping` connects it to Today, which replaces the suggestion in place.
- **Calendar hints:** `EventKitCalendar` (an actor around `EKEventStore`) reads the rest of today's events once the
  user taps "Use my calendar" on Today. `OccasionHint` maps titles to occasions with English and Hebrew keywords,
  most demanding dress code first, on device. Today shows up to three events with "Dress for it", which switches
  the occasion. Nothing prompts for access until the user asks. The trip wizard uses the same reader for new days, but
  only when access was already granted.
