# Decision log

Short records of decisions that shape the codebase. Add a new entry at the top when you make one; never rewrite old
entries (supersede them instead).

---

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
