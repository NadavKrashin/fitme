# Launch plan: FitMe on the App Store

Goal: FitMe (App Store name **FitForMe**) is free on the App Store. Nadav pays for Claude, with a monthly allowance
per user. Written 2026-11-14; tick items off as they land and log choices in [DECISIONS.md](DECISIONS.md).

## Where we start

- A production pipeline already exists: `make release VERSION=x.y.z` tags `main`, CI builds Release (no demo data,
  checked), waits for Nadav's approval, and uploads to TestFlight "FitMe". See [RELEASE_PROCESS.md](RELEASE_PROCESS.md).
- Everything is on the device (SwiftData). There are no accounts and no server.
- Claude is called straight from the app with **the user's own API key** from Settings. That's fine for Nadav and
  impossible for the public: nobody has a key, and shipping Nadav's key inside the app would leak it.
- Every Claude call (tagging, stylist, bag review) uses `claude-opus-5-5`.

## The shape of v1.0 (proposed)

| Question | Proposal | Why |
|---|---|---|
| Accounts | **None in v1.** The closet stays on the device and in its iCloud backup. | No sign-up wall, no passwords, and no account-deletion requirement. Sync across devices can come later with CloudKit (the user's own iCloud, free for us). |
| Who calls Claude | **A small proxy** holds Nadav's Anthropic key; the app never sees it. | The only way to pay for users' Claude use without leaking the key. |
| Proxy host | **Cloudflare Workers**, with Durable Objects counting each device's usage. | Cheap at this scale, keeps secrets server-side, and Durable Objects count exactly (Cloudflare's built-in rate limiter is approximate by design). |
| Who may call the proxy | **App Attest**: Apple vouches that the request comes from a genuine FitMe install. | Stops scripts from spending the budget, with no account. |
| Limits | Per-device monthly allowance (photos tagged, stylist asks, bag reviews), a global daily spend cap, and a kill switch. Over the limit, the app still works without AI (tags by hand). | Caps what Nadav can be charged. |
| AI consent | A clear screen before the first photo goes to Claude, with an explicit "Allow" (not pre-checked); revocable in Settings. | Required by App Review guideline 5.1.2(i) since Nov 2025: apps must disclose and get permission before sending personal data to a third-party AI. |
| Models | Measure cost in the beta; move tagging (and maybe the stylist) to a cheaper model only if a quality check shows it's as good. | Opus on every photo is the biggest cost driver. |

## Milestones

### M1: Claude through a proxy (engineering)
- [x] Cloudflare Worker: one Messages endpoint, the feature named in a header (tag, stylist, bag review; finding
      online is tagging), model and `max_tokens` allowlisted, no tools. Anthropic key in Worker secrets.
- [x] App Attest: attest a key on first launch, assert on each request; the Worker verifies and records the key.
- [x] Durable Object per device: monthly allowance, reset on the 1st; global daily spend cap; kill switch.
- [x] App: `ClaudeClient` talks to the proxy in Release and Staging; the API-key field stays only in Debug.
- [x] Friendly states for "allowance used up", "AI paused" and offline; manual tagging always available.
- [x] Tests: fake proxy in app tests; Worker unit tests; staging Worker separate from production.
- [x] Deployed (2026-11-20): Staging https://fitme-claude-proxy-staging.krashin23.workers.dev, Production
      https://fitme-claude-proxy.krashin23.workers.dev; `FITME_PROXY_URL` set per configuration and the App Attest
      entitlement added. Both secrets are set in both environments.

### M2: Privacy and consent
- [x] AI consent screen (what's sent: the photo and the item's tags; to whom: Anthropic; why), stored choice,
      withdraw in Settings. Asked on first launch; every Claude request is refused until allowed.
- [x] Privacy policy and support page (`site/`), published by `.github/workflows/pages.yml` to
      https://nadavkrashin.github.io/fitme/.
- [x] `PrivacyInfo.xcprivacy`: UserDefaults (CA92.1), no tracking, four collected data types.
- [x] App Privacy answers for App Store Connect, written up in [APP_PRIVACY.md](APP_PRIVACY.md): photos and closet data sent to Anthropic for processing; coarse
      location to Open-Meteo; calendar read on the device only; no tracking, no ads.
- [x] `ITSAppUsesNonExemptEncryption = NO` (HTTPS only), already set.

### M3: A first run for strangers
- [x] Onboarding: what FitMe does, consent, location (asked only on a tap), then straight into "photograph your
      closet" (camera or library). People with clothes or an AI answer skip it.
- [x] Empty states for a new user: Today and Closet offer Take photos / Choose from library; Trips already had one.
- [x] Accessibility pass: serif titles scale with Dynamic Type (they were fixed sizes), icon columns scale,
      decorative icons hidden from VoiceOver; checked at the largest text size and in dark mode on the new screens.
- [x] Crash and hang reports: Xcode Organizer and TestFlight feedback, no code and no third-party SDK.

### M4: Store presence
- [x] Listing: subtitle, description, keywords, categories (Lifestyle, Travel), URLs, in
      [store/APP_STORE_LISTING.md](store/APP_STORE_LISTING.md); lengths checked by `scripts/check-listing.py`.
- [x] Screenshots (6.3" 1206 × 2622 and 6.9" 1320 × 2868) from the demo closet via `make screenshots`; age rating answers noted
      (Find online's browser means "unrestricted web access").
- [x] Review notes: how to try it with any clothing photo, consent, the proxy's allowance, optional permissions.

### M5: External TestFlight beta
- [ ] 10–20 people via a public TestFlight link, for two weeks.
- [ ] Measure: Claude cost per user per month, suggestions rated "I'd wear that", crashes.
- [ ] Set the allowance and model choices from those numbers.

### M6: Release 1.0
- [ ] `make release VERSION=1.0.0`, approve, submit for review, release.

## Only Nadav can do these

Step by step: [OWNER_CHECKLIST.md](OWNER_CHECKLIST.md).
- Enter the listing, screenshots, App Privacy answers and age rating in App Store Connect (texts ready in
  `docs/store/` and `docs/APP_PRIVACY.md`).
- Create the Cloudflare account and give the agent a scoped API token (or deploy with `wrangler` yourself).
- Create a production Anthropic API key with a monthly spend limit set in the Anthropic Console.
- In App Store Connect: App Privacy answers, age rating, EU trader status (Digital Services Act), listing text approval,
  and the final "Submit for Review".
- Read the privacy policy before it goes live (it's a legal statement in your name).

## Risks
- **Cost:** a heavy user photographing 150 items is the expensive case; the allowance and a cheaper tagging model
  are the levers.
- **App Review:** AI consent (5.1.2(i)) is the most likely rejection; the consent screen must come before any upload.
- **App Attest:** fails on the Simulator and occasionally in production (Apple outages); the app needs a graceful
  "try again" path, and Staging can allow unattested calls under a tight limit.
