# App Privacy answers (App Store Connect)

What to enter under App Store Connect → FitForMe → App Privacy. Keep this in sync with
[`FitMe/PrivacyInfo.xcprivacy`](../FitMe/PrivacyInfo.xcprivacy) and [`site/privacy.html`](../site/privacy.html).

**Privacy policy URL:** https://nadavkrashin.github.io/fitme/privacy.html
**Support URL:** https://nadavkrashin.github.io/fitme/support.html

**Do you or your third-party partners collect data from this app?** Yes. "Collect" means it leaves the device and
is kept longer than needed to answer the request. Anthropic (Claude) and the proxy's usage counts qualify.

| Data type (Apple's name) | Collected because | Linked to the user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Photos or Videos | clothing photos sent to Anthropic for tagging (only after the user allows Claude) | No | No | App Functionality |
| Other User Content | descriptions of clothes, occasions and shop pages sent to Anthropic | No | No | App Functionality |
| Coarse Location | location rounded to ~1 km, sent to Open-Meteo for the weather | No | No | App Functionality |
| Device ID | the App Attest key ID (or install ID) the proxy counts monthly AI use against | No | No | App Functionality |

**Not collected:** contact info, health, financial info, precise location, contacts, browsing history (Find online's
browser doesn't report pages to FitMe), search history, identifiers linked to an account, purchases, usage data,
diagnostics (crash reports reach the developer only through Apple, if the user shares them with developers), and
calendar data (read on the device only).

**Tracking:** none. No third-party SDKs, no ads, no data brokers.

## Related settings

- **Encryption:** `ITSAppUsesNonExemptEncryption = NO` (HTTPS only), already in `FitMe/Info.plist`.
- **AI consent (guideline 5.1.2(i)):** a "Before you start" sheet on first launch asks before anything goes to Claude
  (`AIConsentView`); every Claude request is refused until the user allows it (`ConsentGatedAccess`); Settings → AI
  turns it on and off.
- **Age rating:** answer the questionnaire with no objectionable content; FitMe has no chat, no user-to-user
  content and no web content beyond Find online's browser (answer "unrestricted web access: yes" for that browser).
