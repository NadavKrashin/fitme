# Branching, environments and CI/CD

## In one picture

```
 work ──► commit on main ──► push ──► CI: format · lint · engine tests · app tests
                                          │ green
                                          ▼
                           Deploy STAGING ──► TestFlight: "FitMe β" (demo closet available)
                                          │ happy with it on your phone?
                                          ▼
               make release VERSION=1.2.0  (tags v1.2.0 on main, pushes the tag)
                                          │
                                          ▼
                 CI again ──► approval gate ──► Deploy PRODUCTION ──► TestFlight: "FitMe"
                                                                        (then optional App Store release)
```

## Git strategy: trunk-based, one branch

- **`main` is the only long-lived branch.** It must always build and pass tests, and every push to it ships to
  Staging.
- **Small changes** are committed straight to `main` after `make test` passes locally.
- **Bigger or risky changes** use a short-lived branch (`feat/<topic>`, `fix/<topic>`) and a pull request:
  - CI runs on the PR.
  - Squash-merge, then delete the branch.
  - Branches never live longer than the work they hold.
- **Production releases are tags, not branches.**
  - `vMAJOR.MINOR.PATCH` (e.g. `v0.3.0`) on a commit that has already been on Staging.
  - Fixing a release means a new commit on `main` and a new tag. There are no release branches.

## Environments

| | Staging | Production |
|---|---|---|
| Trigger | every push to `main` | a `v*` tag |
| Build configuration | `Staging` | `Release` |
| Bundle ID | `io.github.nadavkrashin.fitme.staging` | `io.github.nadavkrashin.fitme` |
| Home-screen name | FitMe β | FitMe |
| Demo closet | compiled in: "Load demo closet" in Settings | **not compiled in** (verified in CI) |
| Data | its own app container: separate closet, Keychain and API key | your real closet |
| Distribution | TestFlight (internal testers) | TestFlight, then App Store release when wanted |
| Approval | automatic | manual approval on the GitHub `production` environment |

Because the bundle IDs differ, **both apps install side by side** on your iPhone and never share data. Experiment
with demo fits in FitMe β while your real closet stays in FitMe.

Local runs from Xcode use the **`Debug`** configuration, which behaves like Staging (staging bundle ID, demo closet
available) and adds debug tooling.

How it's wired:
- `project.yml` defines the three configurations, each with its own bundle ID, display name and
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS` (`DEBUG STAGING`, `STAGING`, none).
- `AppEnvironment.swift` is the only place that reads those conditions.
- The demo closet resource is excluded from `Release` via `EXCLUDED_SOURCE_FILE_NAMES`.

## Versioning

- **Marketing version** (`CFBundleShortVersionString`): `MARKETING_VERSION` in `project.yml`. `make release` sets it
  to the tag's version.
- **Build number** (`CFBundleVersion`): the GitHub Actions run number, set by CI. It's unique and always
  increasing, as TestFlight requires.
- [CHANGELOG.md](../CHANGELOG.md) gets an entry per release (`make release` won't run with an empty
  `Unreleased` section).

## CI/CD pipeline (`.github/workflows/pipeline.yml`)

| Job | Runs on | What it does |
|---|---|---|
| `checks` | every PR, every push to `main`, every tag | On tags, checks the tag matches `MARKETING_VERSION`. Then runs `make lint`, `make test-engine`, `make test-app` (iOS Simulator) and `make verify-release` (a Release build must contain no demo data). |
| `deploy` | pushes to `main` and `v*` tags, after `checks` | Uses the `staging` environment for `main` and the `production` environment for tags. Production waits for **manual approval**. Runs `scripts/deploy.sh`, which archives, re-checks Release for demo data, and uploads to TestFlight. |

Signing:
- Deploy jobs use Xcode **cloud-managed signing** with an App Store Connect API key (`-allowProvisioningUpdates`
  plus `-authenticationKey*` flags).
- There are no certificates or provisioning profiles in the repo or CI secrets, and no fastlane.
- If the API key secrets aren't set yet, the deploy jobs skip with a notice instead of failing.

Public repo: GitHub-hosted macOS runners are free for public repositories.

## One-time setup (owner: Nadav)

**Status as of 2026-11-06:** everything is done except the TestFlight testers.
- Team `4ARX779852` ("Nadav Krashin", Individual).
- iPhone 16 Pro registered.
- App Store Connect records:
  - **FitForMe** (production; "FitMe" was taken as an App Store name, and the home screen still shows "FitMe")
  - **FitMe Staging**
- The `production` environment requires Nadav's approval and only accepts `v*` tags.
- API key "FitMe CI" (Admin).
- A Program License Agreement update had to be accepted first. Apple blocks all signing until the account holder
  accepts new agreements, so if signing suddenly fails, check developer.apple.com for a banner.

These steps need your Apple and GitHub accounts, so an agent can't do them. Tick them off here as they're done.

- [x] **Sign in to Xcode** with your Apple ID (Xcode → Settings → Accounts). Put your **Team ID** (10 characters,
  shown in the Apple Developer portal under Membership) into `project.yml` → `settings.base.DEVELOPMENT_TEAM`, or
  give it to the agent.
- [x] **Create two app records** in [App Store Connect](https://appstoreconnect.apple.com) → Apps → "+":
  - "FitMe" with bundle ID `io.github.nadavkrashin.fitme`.
  - "FitMe Staging" with bundle ID `io.github.nadavkrashin.fitme.staging`.
  - If the bundle IDs aren't offered, register them first under Certificates, IDs & Profiles → Identifiers.
- [x] **Create an App Store Connect API key:** Users and Access → Integrations → App Store Connect API → "+". Role:
  **Admin** (cloud signing needs it). Download the `.p8` file; you can only download it once.
- [x] **Create the GitHub environments _before_ adding secrets** (repo → Settings → Environments):
  - `production`, with yourself as **required reviewer**.
  - `staging`, with no rules.

  If you skip this, the first tag push creates `production` without the approval gate.
- [x] **Add GitHub secrets and variables** (repo → Settings → Secrets and variables → Actions), or run the commands
  below:
  ```bash
  gh secret set ASC_KEY_ID --body "<key id>"
  ```
  ```bash
  gh secret set ASC_ISSUER_ID --body "<issuer id>"
  ```
  ```bash
  gh secret set ASC_PRIVATE_KEY < AuthKey_XXXX.p8
  ```
  ```bash
  gh variable set APPLE_TEAM_ID --body "<team id>"
  ```
- [ ] **TestFlight:** in each app's TestFlight tab, add yourself to an internal testing group, then install
  TestFlight on your iPhone.

## Everyday commands

```bash
make bootstrap    # install tools (Brewfile) and generate the Xcode project
```
```bash
make test         # everything CI runs, locally
```
```bash
make release VERSION=0.2.0   # bump version, tag v0.2.0, push → production pipeline
```

Full list: `make help`.

## Rolling back

- **Staging:** push a fix or `git revert` to `main`. The next build replaces the old one.
- **Production:** TestFlight builds stay available, so you can reinstall the previous build from the TestFlight
  app right away. Then fix on `main` and release a new patch tag. Never move or delete a published tag.
