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
| `FitMe/Models/` | SwiftData `@Model` types: `ItemRecord` (closet item, photo and cutout), `CaptureDraft` (unreviewed photo), `StyleProfileRecord` (learned taste), and `Persistence` (store setup). |
| `FitMe/Services/` | Side-effecting services behind protocols: `SecretStore` (Keychain), `Claude/ClaudeClient` (Messages API over an `HTTPTransport`), `Tagging/ClaudeTaggingService`, `ImagePipeline` (Vision cutout, box crop, colors), `Weather/OpenMeteoWeatherService` + `CoreLocationLocator`, `Stylist/ClaudeStylist`. |
| `FitMe/UI/` | Shared views (`ItemThumbnail`, `OutfitRow`), display helpers, `PreviewData` (Debug only). |
| `FitMe/DemoData/` | Staging-only demo closet. Compiled out of Release. |
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
| Hard rules | `Rules.swift` | Removes items or outfits that are never acceptable: structure, a formality spread of 3 or more, occasion formality, required sportswear, dress shoes for formal events, and warmth against temperature, rain or cold limits. |
| Soft score | `Scorer.swift` | Weighted 0–100 score from color harmony, pattern balance, formality cohesion, occasion fit, weather fit, silhouette balance, statement-piece budget, learned affinity and novelty. The weights are in `ScoreWeights`. |
| Generation | `OutfitGenerator.swift` | Beam search: bases (top+bottom or one-piece) → shoes → mid layer → outerwear, keeping the best partial outfits at each step. `suggest` picks a varied top N, each with a different top. `allOutfits` is exhaustive, for small pools. |
| Packing | `PackingOptimizer.swift`, `Trip.swift` | Groups trip slots by occasion and weather band. Greedily adds the item with the best marginal gain per packing cost, falling back to injecting a whole outfit. Prunes redundant items, then assigns outfits to days. A top or one-piece is used once per laundry cycle. |
| Learning | `StyleProfile.swift` | Item-pair affinities from 👍 / 👎 / "wore it". |

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

## Daily outfits (Phase 2)

- **`TodayModel`** owns the inputs (occasion, feels-like, rain), the suggestions, the session's reactions, and the
  weather and stylist state.
  - With `anchor` set, the same model powers "Outfits with this item".
  - `OutfitPlanner` is the shared view.
- **Weather:** `OpenMeteoWeatherService.forecastHere()` (location rounded to about 1 km) pre-fills the inputs on open.
- **Feedback:** `FeedbackRecorder` writes reactions to `StyleProfileRecord` and wear history to `ItemRecord`. The
  profile feeds `OutfitContext.profile`, so liked pairs score higher next time.
- **Stylist:** `ClaudeStylist.pick` gets 12 diversified engine candidates as labeled text and returns up to 3
  label-constrained picks with reasons.

## Planned additions

Each lands in its own folder, following the same pattern. Details are in [ROADMAP.md](ROADMAP.md).

- `Services/WeatherService` (Open-Meteo)
- `Features/Trips`
