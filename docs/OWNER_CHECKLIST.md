# What's left for Nadav (launch)

Steps only Nadav can do: they need his accounts, his name, or his approval. In order; each says what to send back
to the agent. Details per milestone are in [LAUNCH_PLAN.md](LAUNCH_PLAN.md).

## 1. Housekeeping (5 minutes)

1. **Quit Xcode** (⌘Q). It holds a lock on `FitMe.xcodeproj` that makes command-line builds and tests hang.
2. **Try the latest FitMe β** from TestFlight: the outfit changes, the "Before you start" screen and onboarding.
3. **Read the privacy policy** at https://nadavkrashin.github.io/fitme/privacy.html. It's in your name.
   → Tell the agent anything to change, and whether contact should stay "open a GitHub issue" or be an email address.

## 2. Anthropic production key (5 minutes)

1. Open https://console.anthropic.com → **API keys** → **Create key**, named "FitMe production".
2. Copy the key (it's shown once). Don't send it to anyone; you'll paste it into Cloudflare in step 3.
3. Under **Limits** (or Billing → spend limits), set a **monthly spend limit** you're comfortable with. This is the
   hard backstop if the proxy's own limits are ever wrong.

## 3. Cloudflare account and the Claude proxy (15 minutes)

1. Sign up at https://dash.cloudflare.com/sign-up (the free plan is enough), then open **Workers & Pages** in the
   dashboard once. That creates your `workers.dev` subdomain; without it, deploys fail with error 10063.
2. In Terminal:
   ```bash
   cd ~/Code/Personal/FitMe/server/claude-proxy && npm ci
   ```
   ```bash
   npx wrangler login
   ```
   A browser opens; allow access.
3. Staging:
   ```bash
   npx wrangler secret put ANTHROPIC_API_KEY --env staging
   ```
   Paste the key from step 2 when asked.
   ```bash
   openssl rand -hex 32 | npx wrangler secret put CHALLENGE_SECRET --env staging
   ```
   ```bash
   npm run deploy:staging
   ```
4. Production, the same three with `production`:
   ```bash
   npx wrangler secret put ANTHROPIC_API_KEY --env production
   ```
   ```bash
   openssl rand -hex 32 | npx wrangler secret put CHALLENGE_SECRET --env production
   ```
   ```bash
   npm run deploy:production
   ```
5. Each deploy prints a URL like `https://fitme-claude-proxy-staging.<your-subdomain>.workers.dev`.
   → Send the agent both URLs. It sets them in the app and adds the App Attest entitlement.
6. If the next CI deploy then fails on signing: developer.apple.com → Certificates, IDs & Profiles → Identifiers →
   `io.github.nadavkrashin.fitme` (and `.staging`) → tick **App Attest** → Save, then re-run the failed job.

## 4. App Store Connect: app information (20 minutes)

At https://appstoreconnect.apple.com → **FitForMe**. All texts are in
[store/APP_STORE_LISTING.md](store/APP_STORE_LISTING.md).

1. **App Information:** subtitle, primary category Lifestyle, secondary Travel, content rights ("doesn't contain
   third-party content").
2. **Age Rating → Edit:** "None" for every content question; **Unrestricted Web Access: Yes** (Find online's
   browser). If the resulting rating is too high for you, tell the agent to limit Find online to shop sites first.
3. **App Privacy:** privacy policy URL, then the data types exactly as in [APP_PRIVACY.md](APP_PRIVACY.md) (Photos,
   Other User Content, Coarse Location, Device ID; none linked to the user, none for tracking; purpose App
   Functionality). Publish.
4. **Pricing and Availability:** Free; all countries you want.
5. **Business → Trader status** (EU Digital Services Act): declare whether you're a trader; it's required to be
   listed in the EU.

## 5. App Store Connect: the 1.0 version page (15 minutes)

1. **iOS App → 1.0 Prepare for Submission:** upload the five PNGs from `docs/store/screenshots/6.3-inch/` to the
   6.3-inch iPhone slot (and, if it's shown, `6.9-inch/` to the 6.9-inch slot), in order 1–5.
2. Paste promotional text, description, keywords, support URL and marketing URL from the listing file.
3. **App Review Information:** no sign-in required; paste the review notes; add your contact details.
4. Leave **Build** empty for now; it comes in step 7.

## 6. Friends beta, about 2 weeks (after step 3 and the agent's wiring)

1. Ask the agent to cut the beta release (`make release VERSION=0.9.0`), then approve the **production** deploy on
   GitHub (Actions → the run → Review deployments → Approve).
2. App Store Connect → **TestFlight** → **External Testing → +** → group "Friends".
3. **Test Information:** beta description ("Try FitMe: photograph some clothes, plan a trip"), a feedback email,
   and the privacy policy URL.
4. Add the build to the group; the first external build goes through **Beta App Review** (usually about a day).
5. Add testers by email or turn on a **public link** and share it.
6. After two weeks, tell the agent; it checks cost per user and suggestion quality and tunes allowances and models.

## 7. Release 1.0

1. Ask the agent to cut 1.0 (`make release VERSION=1.0.0`); approve the production deploy on GitHub.
2. App Store Connect → 1.0 version → **Build → +** → pick the new build.
3. **Add for Review → Submit.** Review usually takes one to three days.
4. When approved, release it (or let it release automatically if you chose that).
