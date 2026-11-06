# Engineering standards

These rules apply to every change, whether a person or an AI agent writes it. A change that breaks one of them is
not done. CI enforces the mechanical rules (format, lint, tests); the rest are checked in review against
[the checklist at the bottom](#pre-commit-checklist).

## Principles

1. **Clarity over cleverness.** Code is read far more often than it is written. Choose the plain solution.
2. **Small, focused units.** A function does one thing, a type has one reason to change, and a file holds one main type.
3. **Make wrong states unrepresentable.** Use enums, non-optional properties and value types instead of flags and
   runtime checks.
4. **Pure core, thin shell.** Styling logic lives in `FitEngine` (pure, deterministic, fully tested). The app layer
   is UI, persistence, networking and wiring. No styling rules in views.
5. **No speculative code.** Build what the current phase needs: no "for later" parameters, protocols with one
   conformer and no test fake, or unused abstractions.

## Swift

- **Language mode:** Swift 6 with complete strict concurrency, on both the app and `FitEngine`. Do not silence
  diagnostics with `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` unless a comment explains why
  it is safe.
- **Value types first.** Use `struct`/`enum` by default. Use `final class` only for identity or reference semantics
  (SwiftData `@Model`, `@Observable` state). Use `actor` for shared mutable state across tasks.
- **Access control:** start `private`, widen only when needed. `FitEngine` exposes `public` API deliberately;
  everything else is `internal` or tighter.
- **Optionals:**
  - No force unwrap (`!`) or `try!` in app or engine code. Use `guard let`, a default, or a thrown error.
  - The only exceptions are test code and compile-time-provable invariants (e.g. a literal URL), each with a short
    comment saying why it can't fail.
- **Errors:**
  - Throw typed domain errors (`enum TaggingError: Error`) and map them to user-facing messages at the UI edge.
  - Never swallow an error with an empty `catch` or `try?` unless "absent" is the meaning. Log it if it's
    unexpected.
- **Naming:**
  - Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
  - Names describe intent (`packingCost`, not `val2`). Booleans read as assertions (`isAvailable`,
    `allowsLayers`).
  - Do not use names that clash with Foundation/SwiftUI types (we already hit `Category` and `Pattern`).
- **Magic numbers:**
  - Domain tuning constants (score weights, temperature bands) live in one named place with a comment saying what
    they mean.
  - Literals inline only when self-explanatory (`/ 100` for percent).
- **Comments:**
  - Explain *why*, not *what*. Public API gets a `///` doc comment when its name doesn't fully explain it.
  - No commented-out code, no "TODO" without a roadmap item, no changelog-style comments ("added X").
- **Formatting:** SwiftFormat ([.swiftformat](../.swiftformat)) is the source of truth; run `make format`. Max line
  length is 120.
- **Linting:** SwiftLint ([.swiftlint.yml](../.swiftlint.yml)) runs in CI. A `// swiftlint:disable` needs a reason
  on the same line.

## App architecture (SwiftUI)

- **Feature folders:** `Features/<Feature>/` holds that feature's views and its `@Observable` model. Shared UI
  goes in `UI/`, and services in `Services/`.
- **State:**
  - Views stay small and declarative.
  - Logic beyond formatting goes into the feature's `@Observable` model (MVVM-lite), which you can test without UI.
  - Use `@State` for view-local state only.
- **Dependencies:**
  - Services are protocols injected through `AppDependencies` (created once in `FitMeApp`, passed via the SwiftUI
    environment).
  - No global singletons, and no `static shared` for anything with state or side effects.
- **Persistence:**
  - SwiftData `@Model` types live in `Models/` and map to and from `FitEngine` value types (`ItemRecord` ↔ `Item`).
  - The engine never imports SwiftData.
  - Never `#Predicate` on a Codable enum property: SwiftData stores it as a composite value, and the predicate
    silently matches nothing. Filter in Swift, or store the raw value in its own `String` property.
- **Networking:** use `async`/`await` with `URLSession`. Clients are protocols with a fake for tests and previews.
  Never block the main actor.
- **Secrets:**
  - API keys are entered at runtime and stored in the Keychain.
  - Never put a secret in source, `Info.plist`, xcconfig, logs or crash reports.
- **Logging:** use `os.Logger` with the category set to the feature. No `print` outside tests. Never log personal
  data or keys.
- **Previews:** every screen has a `#Preview` backed by fake services and demo data.
- **Accessibility:**
  - Dynamic Type works.
  - Interactive elements have labels.
  - Color is never the only carrier of meaning, which matters in a color-heavy app.

## Environments

There are two environments and three build configurations; see [RELEASE_PROCESS.md](RELEASE_PROCESS.md).

- Environment-specific behavior is decided at compile time. The `STAGING` condition may be read in only three
  places:
  - `App/AppEnvironment.swift`
  - the `DemoData/` folder (each file is wrapped in `#if STAGING`)
  - the single call site that mounts the demo settings section

  Everything else asks `AppEnvironment.current`.
- Previews and `PreviewData` are wrapped in `#if DEBUG` so Release builds compile without them.
- Demo data (the demo closet) is **only compiled into Debug and Staging**. Production builds must not contain it;
  CI checks this.

## Testing

- **Framework:** Swift Testing (`import Testing`, `@Test`, `#expect`) for all tests.
- **Engine (`FitEngine`):**
  - Every rule, scoring component and optimizer behavior has a test.
  - Taste regressions ("this should beat that") are tests too.
  - Tests must be deterministic: inject dates, and sort before comparing.
- **App:**
  - Test feature models and services with fakes.
  - UI tests cover only the critical flows (capture → closet, trip → packing list).
- **Bugs:** a bug fix starts with a failing test that reproduces it.
- **Fixtures:** the engine test closet (`Packages/FitEngine/Tests/.../closet.json`) is frozen; change it only
  together with the tests that depend on it. The app's demo closet is separate and may change freely.

## Git

- Trunk-based: `main` is the only long-lived branch (details in [RELEASE_PROCESS.md](RELEASE_PROCESS.md)).
- Small commits that each build and pass tests.
- Commit messages:
  - Imperative subject of 72 characters or less ("Add packing optimizer"), a blank line, then a body explaining
    *why* when it isn't obvious.
  - AI-authored commits end with the `Co-Authored-By` trailer.
- Never commit generated files (`*.xcodeproj` is generated by XcodeGen), build output, secrets or personal photos.

## AI-authored code: anti-patterns we reject

AI agents write much of this codebase, so these rules are explicit. Each is a review blocker:

- **Over-commenting.** Comments that restate the code (`// increment counter`), banner comments on every block, or
  docstrings that just repeat the name.
- **Defensive noise.** Checking conditions the type system already guarantees, `guard` chains for impossible
  states, or catch-all `do/catch` that hides real failures.
- **Speculative generality.** Protocols, generics, factories, config options or parameters that nothing uses yet.
- **Duplicate helpers.** Writing a new utility when one exists. Search the codebase first, and extend or reuse.
- **Dead code.** Unused functions, parameters, imports, files or "legacy" shims left behind after a refactor.
  Delete them.
- **Fake completeness.** Placeholder implementations, hard-coded results that pass a test, or stubbed TODOs
  presented as working features. If something isn't done, say so in [HANDOFF.md](HANDOFF.md).
- **Silent behavior changes.** Changing defaults, thresholds or public API without updating tests and docs.
- **Weakening tests to pass.** Loosening an assertion only to get green. If the expectation was wrong, the commit
  says why.
- **Inconsistent style.** Code that doesn't look like the surrounding code (naming, structure, idiom).
- **Unverified claims.** Saying "tested" or "works" without having run it. State exactly what was run.

## Pre-commit checklist

- [ ] `make format` and `make lint` are clean.
- [ ] `make test` passes (engine + app).
- [ ] New behavior has tests; any bug fix has a regression test.
- [ ] No force unwraps, `print`, secrets, dead code or commented-out code.
- [ ] Public API and non-obvious decisions are documented (`///`, [ARCHITECTURE.md](ARCHITECTURE.md),
  [DECISIONS.md](DECISIONS.md)).
- [ ] [HANDOFF.md](HANDOFF.md) and [ROADMAP.md](ROADMAP.md) reflect the new state.
