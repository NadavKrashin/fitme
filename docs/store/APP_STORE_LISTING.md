# App Store listing (FitForMe)

What to paste into App Store Connect → FitForMe → the 1.0 version and App Information. Lengths are checked by
`scripts/check-listing.py` (Apple's limits in brackets). Privacy answers are in [../APP_PRIVACY.md](../APP_PRIVACY.md).

## App Information

- **Name** [30]: FitForMe
- **Subtitle** [30]: Outfits from clothes you own
- **Primary category:** Lifestyle
- **Secondary category:** Travel
- **Content rights:** no third-party content (the demo closet's product photos are generated and only in Staging).
- **Age rating:** answer "None" to every content question. Find online opens a full web browser, so answer **Yes** to
  unrestricted web access; Apple rates that at its highest age tier. If that rating matters, Find online would need
  to be limited to shop sites first.

## Version 1.0

**Promotional text** [170]:

Photograph your closet once. Get outfits for the weather and your plans, and a bag that packs the fewest pieces
for every day of a trip.

**Description** [4000]:

FitForMe turns the clothes you already own into outfits that work: for today's weather, for the day's plans, and
for every day of a trip.

PHOTOGRAPH YOUR CLOSET
Shoot one piece after another, or pick photos you already have. Each one is cut out and tagged with its colors,
fabric, fit and dress code, ready for you to check. Already bought it online? Find the product page and use the
shop's own photo.

DRESS FOR THE DAY
Today shows outfits for the weather where you are, from a cool morning to a warm afternoon, and for the occasion:
work, a date, a run, the beach. Colors are paired the way stylists pair them, shoes suit the trousers, and
yesterday's shirt steps back for a few days. Want something calmer or bolder? Set the mood to Neutral or
Colorful. Tap any outfit to see every piece and swap one.

PACK LESS
Tell FitForMe where you're going and what each day holds. It picks the fewest pieces that dress every day, plans
each day's outfit, and checks the forecast so rainy days get a jacket that keeps water out. One bag, nothing you
won't wear.

GET TO KNOW YOUR CLOSET
See the pieces you wear most, the ones resting at the back, and whether one more staple would open up new outfits.
The more you react to suggestions, the better they fit your taste.

PRIVATE BY DESIGN
Your closet stays on your iPhone. No account, no ads, no tracking. Tagging and the stylist use Claude, an AI by
Anthropic, only after you allow it, and FitForMe works without it: you can tag clothes yourself.

**Keywords** [100]: closet,wardrobe,outfit,packing,travel,stylist,clothes,capsule,weather,menswear,ootd,style

**Support URL:** https://nadavkrashin.github.io/fitme/support.html
**Marketing URL:** https://nadavkrashin.github.io/fitme/
**Privacy policy URL:** https://nadavkrashin.github.io/fitme/privacy.html
**Copyright:** 2026 Nadav Krashin

## Screenshots (6.9-inch iPhone, 1320 × 2868)

In [screenshots/](screenshots/), regenerated with `make screenshots` (demo closet, a packed Lisbon trip, steady
weather; see `ScreenshotStage`). Upload in order:

1. `1-today.png`: an outfit for today's weather.
2. `2-outfit.png`: every piece, with Swap.
3. `3-trip.png`: 15 pieces → 114 outfits for five days in Lisbon.
4. `4-closet.png`: the closet.
5. `5-insights.png`: 50 pieces, 753 looks, and the workhorses.

## App Review notes [4000]

FitForMe needs no account and has no sign-in.

To try it: on first launch, tap Get started, then Allow (or Not now) for Claude, then Take photos or Choose from
library and add a few clothing photos (any shirt, trousers and shoes will do). With Claude allowed, each photo is
tagged automatically; with it off, you tag by hand. Suggestions appear on Today once the closet has a top, a
bottom and shoes. Trips → Plan a trip packs a bag for any city and dates.

Claude (Anthropic) is called through our own server, which holds the API key and gives each device a monthly
allowance. Nothing is sent to Anthropic until the user allows it on the "Before you start" screen; this can be
changed in Settings → AI. Location is asked for only when the user taps "Use my location", and the calendar only
when they tap "Use my calendar"; both are optional.
