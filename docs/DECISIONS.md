# Decision log

Short records of decisions that shape the codebase. Add a new entry at the top when you make one; never rewrite old
entries (supersede them instead).

---

### 2026-11-14: Rotation by piece

- **Decision:** novelty weighs 0.12 (was 0.03) and is the stalest of the top and the trousers: a top worn in the
  last 2 days scores 0.2, in 4 days 0.6, in a week 0.85; trousers worn today 0.6, yesterday 0.85. Shoes and layers
  don't count.
- **Why:** a top worn yesterday cost about 2 points, so it came straight back. Closet-rotation advice is not to
  repeat a shirt two days running, while trousers, shoes and jackets repeat.

### 2026-11-14: Fabric

- **Decision:**
  - Items have an optional `fabric` (`Fabric`: cotton, linen, wool, cashmere, flannel, corduroy, denim, silk, leather,
    suede, canvas, fleece, technical, other). Unknown changes nothing, so items tagged before keep working.
  - Comfort: linen feels thin below 16° even under a layer (0.7, 0.4 below 10°); flannel, corduroy, cashmere and
    fleece feel heavy from 24° (0.7, 0.4 from 28°); wool from 27° (0.7).
  - Rain: suede shoes cost 0.6 and canvas 0.85 on top of the cover score.
  - Formal leaves out denim, canvas, fleece and technical fabric.
  - Tagging asks for fabric (a shop listing's Material line wins); the edit screen has a Fabric picker; every demo
    item has one. Named `Fabric`, not `Material`, which SwiftUI already uses.
- **Why:** the analysis found a linen shirt under a puffer at 0° and suede loafers on a rainy date; warmth alone
  can't tell linen from flannel or suede from leather.

### 2026-11-14: One warmth scale for tagging and the engine

- **Decision:** the tagging rubric's warmth examples now match the scale the engine's rules and the demo closet use:
  1 t-shirt, polo, linen shirt, shorts, sandals; 2 oxford, chinos, sneakers, loafers, cardigan, blazer, denim jacket,
  rain shell; 3 sweater, hoodie, fleece, jeans, wool trousers, leather or field jacket, trench; 4 heavy knit, boots,
  lined jacket; 5 wool coat, puffer, parka. A test checks the rubric against these levels.
- **Why:** the rubric called a tee "light (2)" and a light jacket 3, one step warmer than the engine assumes, so
  photographed items were judged too warm for hot days and too thin as layers.
- **Not done:** items tagged before this keep their warmth; there's no automatic re-tag.

### 2026-11-14: Dress for the rest of the day, not one temperature

- **Decision:**
  - `Weather.dayRange` carries the feels-like span of the rest of the day. When it swings 6° or more (`swing`), the
    base (top) must suit the warm end (`warmestC`), trousers and shoes the middle (`legsC`), and the full outfit
    with its layers the cool end (`coolestC`). A layer is "needed" when the base alone is too cool for the coolest
    part. Stacked layers need the whole day under 20° and part of it under 14°. Old saved weather decodes without it.
  - Today asks Open-Meteo for hourly feels-like and takes the range from now until 11 pm (the daily min was usually
    at 3 am). The range applies while the slider shows the forecast's "now"; a temperature set by hand is dressed
    for exactly. The card reads "Feels 18–27° rest of today".
- **Why:** on a 10–27° day the engine only saw the current temperature, and the daily low it showed was from the
  small hours. Guides on changeable weather say to dress a light base for the warm part and a layer that comes off
  for the cool part.

### 2026-11-14: Style coherence from the pieces' style tags

- **Decision:** a new score component, `style` (weight 0.10), rates whether the pieces' style tags mix
  (`StyleTag.compatibility`): classic with minimal or preppy, street with sporty or edgy, outdoor with street or
  sporty, and boho with romantic all score 1. Technical sportswear or outdoor gear with classic tailoring, boho or
  romantic pieces clashes (0.4–0.6), and unnamed pairs score 0.85. Each pair of tagged pieces takes its best-mixing
  tags; the weakest pair counts as much as the average; untagged pieces go with anything.
- **Why:** tags were only used to require sportswear for Sport. The analysis found a denim jacket over a green fleece
  over a floral camp shirt, and a puffer over a shawl cardigan over a floral shirt with running shoes.

### 2026-11-14: Hike is its own occasion; sport and beach kits

- **Decision:**
  - New `Occasion.hike`: every core piece is sporty or outdoor, and outdoor shoes (hiking boots) are preferred
    (other shoes score 0.7 for fit). `requiredStyle` became `requiredStyles` (any of), and `Violation.missingStyle`
    lost its payload.
  - Sport means a run or the gym: no outdoor-tagged bottoms or shoes (hiking trousers and boots).
  - Beach: no outdoor-tagged pieces; from 22° no jeans-weight bottoms and no boots; sandals preferred, running shoes
    least (0.7).
  - Calendar: "hike", "hiking", "trek", "trail" and "טיול רגלי" map to Hike; "jog" joins Sport.
- **Why:** Nadav's calendar had "Run: Jog 2-45min", and Sport suggested hiking pants with hiking boots (52 of 88
  sport outfits used hiking boots). Beach suggested hiking boots in 39 of 90 outfits and sandals in 7.

### 2026-11-14: Dress codes for formal, work, smart casual and dates

- **Decision** (`DressCode.swift`):
  - Formal: every top, bottom, layer and pair of shoes is formality 4+, and the outfit wears a tailored jacket
    (formality 4+) in any weather. The jacket doesn't count against the heat or as an unneeded layer.
  - Work is business casual: no sporty or outdoor tops, bottoms or shoes; tops formality 2+ and not graphic or
    statement; no shorts and no light- or mid-wash jeans (dark denim passes); shoes formality 2+.
  - Smart casual and dates: no sporty or outdoor tops, bottoms or shoes, and no graphic tees.
  - A suit jacket (found by name, not tracksuits or swimsuits) only goes with suit trousers of the same color
    (`Violation.splitSuit`).
- **Why:** the analysis found a rust knit polo with suit trousers for formal, a polo under a suit jacket, light-wash
  jeans with sneakers for work, and a floral camp shirt with dark jeans and chelsea boots for work.
- **Sources:** [Resident, men's formal dress codes](https://resident.com/resource-guide/2026/02/09/mens-guide-to-formal-dress-codes),
  [Opumo, men's dress codes](https://opumo.com/magazine/mens-dress-codes),
  [The Black Tux, cocktail attire](https://theblacktux.com/blogs/resources/what-is-cocktail-attire-an-essential-men-s-dress-code-guide),
  [Berle, dress code guide](https://berle.com/blogs/announcements/ultimate-guide-mens-dress-codes).

### 2026-11-14: Color judged by stylist pairings (supersedes "Neutrals first, color by mood")

- **Decision:**
  - Colors are named the way menswear color guides name them (`StyleColor`: navy, burgundy, rust, forest, light
    blue...), and an outfit's color score comes from how well each pair goes together: the average and the weakest
    pair count equally, so one clash shows.
  - Neutrals never clash with each other, except navy with black (0.6, "accidentally dark"), brown with black (0.75,
    contested) and navy with charcoal (0.85). Named classics score 1: navy with burgundy, rust, pink, forest or
    mustard; grey with burgundy or pink; olive with burgundy, rust or mustard; brown with pink, rust or blue; white
    with any color. A neutral with any other color scores 0.9; two colors are judged by hue unless the guides name
    them (red with green 0.35).
  - More than two accent colors costs 0.15 each, more than three colors in all 0.05 each. The Color mood stays:
    Mixed is merit only, Neutral pushes color back, Colorful lifts it.
  - Outfit variety weighs what makes outfits look different: the top (3) and trousers (2) more than layers (1.5) and
    shoes (1), so the same sneakers on two suggestions don't count as a repeat.
- **Why:** the previous entry made all-neutral outfits score highest. Nadav meant the opposite of a blanket rule: color
  should be judged on real style advice, so a navy-and-burgundy outfit can be as good as navy, grey and white. With
  this, about 38% of the probe's suggestions carry a color, chosen because the pairing is a classic.
- **Sources:** [Aza Fashions, menswear colour cheat sheet](https://www.azafashions.com/blog/menswear-colour-cheat-sheet/),
  [Ape to Gentleman, outfit colour combinations](https://www.apetogentleman.com/outfit-colour-combinations/),
  [Real Men Real Style, colour rules](https://www.realmenrealstyle.com/match-colors-style-rules/),
  [Louis Copeland, matching colours](https://www.louiscopeland.com/blogs/news/how-to-match-your-clothing-colours-complete-mens-guide),
  [Westwood Hart, wardrobe palette](https://westwoodhart.com/blogs/westwood-hart/best-clothing-colors-for-men-wardrobe-palette).

### 2026-11-14: Weather for the whole outfit, and rain that counts

- **Decision:**
  - Every top, bottom and pair of shoes has a comfortable feels-like range by its warmth (tables in `OutfitScorer`):
    shorts and sandals from 22°, jeans up to 27°, boots up to 22°, a tee from 18° (from 4° under a layer). The
    weather score is multiplied by the fit of the least suitable piece, so one piece dressed for another season
    drags the outfit down. Weather now weighs 0.18 (was 0.13).
  - Hard limits move with it: shorts from 20° (was 16°), sandals from 20° and never in rain, boots (warmth 4+) not
    on dry days from 24°, sweaters and hoodies not from 24° (was 27°).
  - The beam judges each piece's weather while the outfit is assembled, and on rainy days whether the shoes keep
    water out, so warm bases and boots aren't pruned before layers are added.
  - Rain: a water-resistant jacket and shoes score 1; jacket only 0.75 below 15° (0.9 above); shoes only 0.6;
    neither 0.35. On a trip, rainy days require a water-resistant jacket, and cold rainy days water-resistant shoes,
    whenever the closet has them (not for formal events).
  - What you've learned is no longer squeezed into the room left below 100: a like adds up to its full 8 points.
    The app shows `matchPercent`, clamped to 0...100.
- **Why:** the 720-suggestion analysis found dark jeans and chelsea boots at 32°, a linen shirt under a puffer with
  sneakers at 0°, a cable-knit with shorts at 17–20°, and rain costing about 3 points. Only upper-body warmth was
  scored. With good outfits all in the high 90s, a like on a near-top outfit could add under 3 points.
- **Sources:** temperature dressing guides put shorts at roughly 23–28°C and up, long trousers below about 20°C, and
  light fabrics in the heat ([Nike, layering by season](https://www.nike.com/a/how-to-layer-clothes),
  [Proper Cloth, hot weather](https://propercloth.com/reference/how-to-dress-in-hot-weather-a-mens-summer-style-guide/),
  [Proper Cloth, shorts](https://propercloth.com/reference/how-to-style-mens-shorts-a-modern-guide-for-summer/)).

### 2026-11-14: Neutrals first, color by mood

- **Decision:**
  - Color scoring follows menswear color guides: an all-neutral outfit (black, grey, white, navy, denim, beige,
    brown, camel, khaki, olive) scores full marks; one accent scores a little less, so it wins only when it makes the
    outfit better on other counts or your taste favors it. Two or more accents must relate by hue, as before. More
    than three color groups in one outfit costs 0.05 each (the "rule of three").
  - A color mood on Today (`Palette`: Neutral, Mixed, Colorful; Mixed by default) shifts this: Neutral pushes accents
    well back, Colorful puts an outfit with one accent ahead of an all-neutral one. "Ask the stylist" is told the mood.
  - Packing now counts bottom wears in its coverage check, the same limit the day plan applies.
- **Why:** the engine scored a lone accent above an all-neutral outfit (0.95 against 0.85), so the green polo, rust
  polo and floral shirt led nearly every list. Nadav doesn't always want color: only when it looks good or he's in the
  mood. The packing change surfaced here: with neutrals preferred, one pair of jeans covered six outfits on a five-day
  trip, above the three-wear limit the day plan enforces, because capsule selection never checked that limit.
- **Sources:** [Real Men Real Style, 3-color outfits](https://www.realmenrealstyle.com/3-color-outfits/),
  [The VOU, three-colour rule](https://thevou.com/blog/three-colour-rule-style-guide-men/),
  [Westwood Hart, classic menswear palette](https://westwoodhart.com/blogs/westwood-hart/mens-wardrobe-color-combinations-classic-menswear-palette).

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
