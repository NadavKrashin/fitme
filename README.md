# FitMe

A personal iOS app that knows your closet, suggests outfits that actually look good (color, formality, weather,
occasion), and packs the **smallest set of items that covers a whole trip**.

## Quick start

Requires Xcode 26 or later and Homebrew.

```bash
make bootstrap   # install tools and generate FitMe.xcodeproj
```
```bash
make open        # open in Xcode; run the "FitMe" scheme (Debug = staging app with demo closet)
```
```bash
make lint test   # everything CI checks
```

In the app, go to **Settings → Load demo closet**, then open **Today**.

## How it ships

- Every push to `main` builds **FitMe β** (staging) to TestFlight.
- `make release VERSION=x.y.z` tags a production release of **FitMe** after you approve it in GitHub Actions.
- Details: [docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md).

## Docs

| Doc | For |
|---|---|
| [docs/HANDOFF.md](docs/HANDOFF.md) | Where things stand and what to do next. **Start here.** |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phases and progress |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the app and the engine fit together |
| [docs/ENGINEERING_STANDARDS.md](docs/ENGINEERING_STANDARDS.md) | Code rules, including AI-code anti-patterns |
| [docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md) | Branching, environments, CI/CD, one-time setup |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Why things are the way they are |
| [CHANGELOG.md](CHANGELOG.md) | User-visible changes per release |
