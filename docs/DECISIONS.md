# Decision log

Short records of decisions that shape the codebase. Add a new entry at the top when you make one; never rewrite old
entries (supersede them instead).

---

### 2026-11-14: Shoes are scored, and ties rotate by day

- **Decision:**
  - A new score component, `shoes` (weight 0.12), rates how the shoes suit the outfit: their formality against the
    rest of the outfit, and their color against the trousers, as menswear shoe guides pair them. Brown goes with
    navy, grey, denim and earth tones; black goes with black and charcoal and is the formal choice; brown with black
    trousers is the classic miss. The table lives in `ShoeTone.pairings`.
  - Outfits with exactly the same score are ordered by a hash of the outfit and the day (`ranking(on:)`), not by
    item ID. Packing keeps the plain ID order where it compares outfits directly.
- **Why:** an analysis of 720 suggestions from the demo closet found white sneakers in 81 of 90 casual outfits and
  chelsea boots in 83 of 90 work outfits, from 0° to 32°. Shoes didn't move the score, so most outfits tied, and
  ties went to the lowest item ID. Formal chose brown suede loafers more often than black oxfords.
- **Sources:** [Bespoke Unit, trouser coordination](https://bespokeunit.com/shoes/trouser-coordination/),
  [FashionBeans, shoe colour combinations](https://www.fashionbeans.com/article/best-shoe-colour-combinations-men/),
  [Panama Jack, pairing shoes and trousers](https://www.panamajack.es/en/blogs/news/how-to-pair-men-s-shoes-and-trousers-a-practical-guide-for-getting-it-right-every-time).

### 2026-11-14: On a mild day a layer must be needed

- **Decision:** when the feels-like is 14° or warmer, a mid layer or jacket is a hard rule violation
  (`unneededLayer`) if the outfit is already warm enough without it. The one exception is a water-resistant jacket
  on a day that's likely to rain. Under 14° layering is left to the warmth target, as before.
- **Why:** Nadav's trial: Sport at a dry 21° suggested a navy rain shell over a grey hoodie. The warmth sum (3 + 2)
  was in range, so nothing stopped it, but the hoodie is enough on its own and nobody wears a rain shell in the sun.
- **Trade-off:** the engine sees one temperature. On a day that runs 10–27°, it won't add a jacket for the cool
  morning unless the slider is set to the morning temperature.

### 2026-11-14: Find online with a browser the owner drives

- **Decision:**
  - "Find online" opens a visible in-app browser (a DuckDuckGo search built from what the owner typed, or a pasted
    link). The owner browses to the product page and taps "Use this page"; only then is the page read.
  - The product is read from schema.org `Product` data, then Open Graph tags, then large images on the page.
  - The chosen photo goes through the normal pipeline, and the shop's listing text goes to the tagger beside it.
  - Brand and product URL are stored on `CaptureDraft` and `ItemRecord` (optional fields, so old stores migrate).
- **Why:** J.Crew, Uniqlo, COS and Levi's refuse plain requests (403). A hidden web view posing as a phone browser
  would be fragile and is the kind of bot-protection workaround we don't want. With a visible browser the owner
  confirms the match by seeing the real page, and no paid search call runs. Rejected: a Claude web-search call that
  returns candidates (costs a few cents per item and still can't read the blocked pages).

### 2026-11-13: One layer on mild days, and a wear history

- **Decision:**
  - A jacket over a mid layer is a hard rule violation (`tooManyLayers`) unless the feels-like is under 14°.
  - "Wear this" writes a `WearEntry` with each piece's previous wear date, so a wear can be taken back exactly,
    and Saved → Worn can list the history. Wearing goes through `FeedbackRecorder.wear`; `record` is for likes and
    dislikes only.
- **Why:** Nadav's trial: at 20° the engine stacked a denim jacket over a cardigan over a linen shirt. The warmth
  sum (1 + 2 + 2) was in range, but nobody dresses like that. "Worn today" was a session-only flag with no undo and
  nowhere to see it, which confused him.

---

### 2026-11-11: Learning that shows, and an honest gap finder

- **Decision:**
  - Learned taste is added on top of the style score (up to 8 points either way, limited by the room left to 0 or
    100) instead of being one weighted component (5%). With no opinion the score is exactly the style score; the
    blend without the old neutral affinity term shifts every score by about 1–2 points.
  - Reactions also teach color-family pairings, at a fifth of the item-pair rate, so taste carries over to pieces
    never reacted to.
  - A dislike moves item pairs further (−0.4) than a like (+0.25): a rejected outfit should not come back.
  - The closet analyzer judges a missing staple by the outfits it adds on kinds of day the closet can't already
    dress, not by every look it's in. A second coat beside one that does the same job adds little.
  - Calendar titles are matched to occasions with keywords on the device. They're never sent to Claude.
- **Why:** with the old 5% weight, a like or dislike moved an outfit by under a point, so learning was invisible.
  Counting every look made any coat "unlock 48 looks" in a closet that already had one. Keywords cover the common
  events ("dinner", "wedding", "gym") without sending private calendar data anywhere.

---

### 2026-11-06: Trip weather, edits and learning

- **Decision:**
  - Per-day trip weather comes from Open-Meteo: the forecast up to 16 days ahead, and beyond that the same dates
    averaged over the last 3 years from its archive. Cities come from Open-Meteo's geocoding.
  - Each day dresses for the middle of its feels-like range; layers cover the cool morning.
  - Trips are stored as one JSON blob per `TripRecord`. Fields added later must decode from old trips (see the
    standards).
  - The bag is the optimizer's first answer, and every edit afterwards (leave out, bring, stylist change) only
    replans the days for the edited bag. It never repacks behind the user's back.
  - An item that came home unworn costs a third more to pack per such trip.
- **Why:** no API keys, the same provider as daily weather, and typical weather means a trip two months out still
  gets a sensible plan. Replanning instead of repacking keeps the user in control. The unworn penalty is the
  feedback loop the Phase 3 goal (wear 90% of what's packed) needs, without a separate model.

---

### 2026-11-06: Warm editorial design system

- **Decision:**
  - Nadav picked direction A (warm editorial) from three mockups.
  - All colors, type and shapes live in `UI/Theme.swift`: cream canvas, ink, terracotta, sage, butter, and a muted
    tint per occasion, each with a dark-mode value.
  - Serif (New York) headlines, including navigation titles via `Theme.applyNavigationBarAppearance()`.
  - Shared pieces in `UI/Components.swift`: `card()`, `PillButtonStyle`, `CircleIconButton`, toasts.
- **Why:** the stock look read as "an app from 2012, one color". One token file keeps every screen consistent.
  Views never hard-code colors.

### 2026-11-06: Demo closet is menswear with AI-generated product photos

- **Decision:**
  - The 50-item demo closet is menswear only.
  - Each item has a flat-lay product photo generated with Higgsfield `gpt_image_2_6`: 52 images, 13 credits, two
    white shirts re-shot on grey.
  - The photos were cut out with the app's own Vision subject lift and bundled as `DemoData/Images/demo-<id>.png`,
    excluded from Release.
- **Why:**
  - Nadav is the user (male), and color-swatch icons made it impossible to judge whether outfits look good.
  - The engine test fixture stays separate and frozen.

### 2026-11-06: ♥ means "save"; reactions are separate states

- **Decision:**
  - ♥ saves the outfit (`SavedOutfit`, Saved tab) and records a like. Tapping it again unsaves and reverts the like.
  - ✕ hides the outfit for the session and records a dislike, with an Undo toast that reverts it
    (`StyleProfile.revert`).
  - "Wear this" is tracked separately (`TodayModel.worn`).
- **Why:**
  - Feedback that only tinted an icon felt like it did nothing.
  - A single reaction per outfit let a like overwrite "worn" (Nadav's bug report).

### 2026-11-06: A lone statement piece is neutral in scoring

- **Decision:** `statementBudget` gives 1.0 for zero or one statement piece, down from 0.9 / 1.0.
- **Why:** the small bonus put the floral shirt at the top of every casual, travel and beach list.

### 2026-11-06: Stylist on demand, from text descriptions

- **Decision:**
  - The Claude stylist runs only when the user taps "Ask the stylist", not on every input change.
  - It gets text descriptions (names, color names plus hex, pattern, fit, statement flag) of 12 engine candidates
    labeled A to L.
  - The schema's enum only allows those labels, and it returns up to 3 picks with reasons.
- **Why:**
  - Sliders change often, so automatic calls would cost money and add latency constantly.
  - Text is a fraction of the cost of 12 collage images and works for items without photos (demo closet).
  - Label enums make inventing an outfit impossible.
  - Revisit with images if the picks feel color-blind.

### 2026-11-06: Weather from Open-Meteo with a rounded location

- **Decision:** `OpenMeteoWeatherService` (free, no key) with a one-shot Core Location fix at kilometer accuracy,
  rounded to two decimals before sending. The forecast pre-fills feels-like and rain, and the user can still
  override both.
- **Why:**
  - WeatherKit needs extra entitlements and sends the exact location to Apple.
  - Open-Meteo needs nothing, and about 1 km of precision is plenty for clothing.

### 2026-11-06: Crop worn-item cutouts with a box from the tagging call

- **Context:** Vision's subject lift treats a person and the clothes they wear as one subject, so worn photos kept
  the face and legs (from Nadav's first real trial).
- **Decision:** the tagging schema also asks for `itemBox`, the item's tight bounding box in thousandths of the
  tagging image. `ImagePipeline.crop` cuts the cutout to it, with a 3% margin, and re-measures colors. An invalid box
  is dropped without losing the tags.
- **Why:**
  - It costs nothing extra, because it rides the tagging call that already happens.
  - On-device person or garment segmentation can't separate clothes from the wearer.
  - Remaining limit: arms or hands inside a worn top's box stay. The Inbox tip recommends flat or hanging shots.

### 2026-11-06: Tagging with Claude Opus 5.5 at low effort, colors measured locally

- **Decision:**
  - `ClaudeTaggingService` calls `claude-opus-5-5` with `effort: "low"` and a JSON schema generated from the
    engine's enums, with the server-side fallback `fallbacks: "default"` on.
  - Colors come from on-device OKLab k-means over the cutout's pixels, not from the model.
- **Why:**
  - The claude-api skill's default model is Opus 5.5. At low effort, a ~1k-token image costs about a cent, so roughly
    a dollar for a whole closet. The model is one constant (`ClaudeTaggingService.model`) if cost ever matters.
  - Models are imprecise with exact color values, and the engine's color math needs exact OKLab values.
  - Generating the schema from the enums means it can never drift from the decoder.

### 2026-11-06: Unreviewed photos are `CaptureDraft`s, not closet items

- **Decision:** a separate SwiftData model holds photos from import until review. Confirming creates the
  `ItemRecord`.
- **Why:**
  - Unreviewed or mis-tagged items must never reach outfit suggestions.
  - Saving the draft before processing means a quit or crash never loses a photo; `resumePending` picks it up.

### 2026-11-06: Import from Photos first, in-app camera later

- **Decision:** Phase 1 ships a multi-select import from Photos, not an in-app batch camera.
- **Why:**
  - Shooting in the Camera app and then multi-selecting is already a fast batch flow.
  - It can be verified in the simulator, while camera code can't.
  - Revisit if the real-closet trial shows it's slow.

### 2026-11-05: Trunk-based git, tags for production

- **Decision:**
  - `main` is the only long-lived branch, and every push deploys Staging.
  - Production is a `vX.Y.Z` tag cut by `make release`, gated by manual approval in the GitHub `production`
    environment.
  - Short-lived PR branches only for risky work.
- **Why:** the owner wants no scattered branches but a real staging/prod split. Tags make "what's in prod" exact
  and roll-forward simple.

### 2026-11-05: Staging and production as separate apps on one phone

- **Decision:**
  - Two bundle IDs: `io.github.nadavkrashin.fitme.staging` ("FitMe β") and `io.github.nadavkrashin.fitme`.
  - The demo closet is compiled only into Debug and Staging (`STAGING` flag plus `EXCLUDED_SOURCE_FILE_NAMES`), and
    CI verifies Release is clean.
- **Why:** testing with demo fits must never touch the real closet. Separate bundle IDs give separate containers
  and Keychains for free.

### 2026-11-05: CI/CD on GitHub Actions with cloud signing; no fastlane

- **Decision:**
  - A single `pipeline.yml` on macOS runners (free for the public repo).
  - Deploys use `xcodebuild archive` and `-exportArchive` (destination `upload`) with an App Store Connect API key
    and `-allowProvisioningUpdates`.
- **Why:** no certificates or profiles to manage, no Ruby toolchain, and the whole pipeline is readable in two
  scripts. Xcode Cloud was rejected because its config lives outside the repo.

### 2026-11-05: XcodeGen for the project file

- **Decision:** `project.yml` is the source of truth. `FitMe.xcodeproj` is generated and git-ignored.
- **Why:** configurations, bundle IDs and settings stay reviewable as text, with no `.pbxproj` merge conflicts.

### 2026-11-05: Swift 6, Swift Testing, SwiftFormat and SwiftLint

- **Decision:** Swift 6 language mode with strict concurrency everywhere; `import Testing` for all tests; the
  formatter and linter enforced in CI.
- **Why:** catch data races and style drift mechanically. See [ENGINEERING_STANDARDS.md](ENGINEERING_STANDARDS.md).

### 2026-11-05: Hybrid outfit engine (rules + scoring locally, LLM as judge)

- **Decision:**
  - The deterministic `FitEngine` generates and scores candidates.
  - Claude (Phase 2) only re-ranks and critiques a short list by ID.
- **Why:** rules alone produce dull or odd outfits. An LLM alone hallucinates items, misses combinations and is
  expensive. Keeping the core deterministic also keeps it testable.

### 2026-11-05: Packing as optimization, not a merged list

- **Decision:** choose the capsule that maximizes good outfits per unit of suitcase space (greedy marginal gain),
  then assign outfits to days.
- **Why:** generating outfits per day and taking the union is how people overpack. This is the product's
  differentiator.

### 2026-11-05: Personal tool, native iOS, local-first

- **Decision:**
  - SwiftUI, SwiftData, iOS 17+.
  - The Claude API key is entered on device and stored in the Keychain; there's no backend.
- **Why:** fastest route to something useful for one user. A proxy, auth and sync only come in Phase 6 if it goes
  public.
