# FitMe: agent instructions

A personal iOS app: a closet catalog, outfit suggestions that actually look good, and a trip packer that picks the
fewest items covering every day.

## Start every session here

1. Read [docs/HANDOFF.md](docs/HANDOFF.md): current state, what's unverified, next steps.
2. Read [docs/ENGINEERING_STANDARDS.md](docs/ENGINEERING_STANDARDS.md) before writing code. It includes the list of
   AI-code anti-patterns that are review blockers.
3. Check CI on `main`: `gh run list --limit 3`.

## Commands

```bash
make bootstrap      # tools (Brewfile) + generate FitMe.xcodeproj
```
```bash
make lint test      # what CI runs; must pass before every commit
```
```bash
make test-engine    # fast engine-only tests (no simulator)
```
```bash
make verify-release # Release build must contain no demo data
```

`make help` lists everything.

## Rules

- **Git:**
  - Commit to `main` and push right away; the owner pre-authorized pushing to `origin`.
  - No long-lived branches. Production releases are tags via `make release VERSION=x.y.z` (see
    [docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md)). Only cut a release when the owner asks.
- **Project file:** never edit `FitMe.xcodeproj`. Change `project.yml`, then run `make project`.
- **Engine vs. app:**
  - Styling logic goes in `Packages/FitEngine` (pure, deterministic, tested).
  - The app maps SwiftData `ItemRecord` ⇄ engine `Item` and stays thin.
- **Environments:**
  - `STAGING` is read only in `AppEnvironment`, `DemoData/`, and the one demo-settings call site.
  - Demo data must never reach Release.
- **Tests:** use Swift Testing. Bug fixes start with a failing test. Don't loosen assertions just to get green.
- **Honesty:** report exactly what you ran. Anything unverified goes in HANDOFF.md under "Not verified yet".
- **End of session:** update docs/HANDOFF.md, tick docs/ROADMAP.md, add user-visible changes to CHANGELOG.md
  (`Unreleased`), and log decisions in docs/DECISIONS.md.

## Map

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Engine: `Packages/FitEngine/Sources/FitEngine/`. App:
`FitMe/{App,Features,Models,Services,UI,DemoData}`. Pipeline: `.github/workflows/pipeline.yml` and `scripts/`.
