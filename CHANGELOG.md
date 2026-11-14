# Changelog

User-visible changes per production release. Add entries under **Unreleased** as you go;
`make release` moves them under the new version.

## [Unreleased]

- First app build: Today (outfit suggestions by occasion and weather), Closet, and Settings (Claude API key).
- Staging builds can load a demo closet.
- Add clothes from your photo library. Each photo is cut out, color-matched and tagged by Claude, then waits in an
  Inbox for you to review.
- Edit or delete any closet item. Filter the closet by category, or search by name.
- Closet and outfit suggestions show your real item photos.
- Photos of clothes you're wearing are cropped to the item, so your face and legs no longer end up in the cutout.
- The Inbox shows photos while they import, and skips photos you already added.
- Today shows outfits as flat-lay collages and fills in the weather where you are.
- Like, dislike or "wear" any suggestion; FitMe learns your taste and rotates what you wore recently.
- "Ask the stylist" has Claude pick the best few outfits and explain why each works.
- Find outfits built around any item from its detail screen.
- New warm editorial look: cream paper, serif headlines, terracotta and sage, a color per occasion.
- ♥ saves an outfit to the new Saved tab; ✕ hides it with Undo; every reaction confirms with a toast.
- Liking an outfit no longer resets "Wear this".
- The demo closet is now menswear, with real product photos.
- New Trips tab: add cities and nights, laundry and luggage, then what each day holds. FitMe packs the fewest pieces
  that dress every plan, with a day-by-day outfit plan and the real forecast (or typical weather for later trips).
- Packing list with tick-off, counted essentials, "Leave at home", and "Add from closet". The plan updates after
  every change, with Undo.
- Swap any planned outfit for another from the bag, and see when a plan repeats a top before the next wash.
- "Check my bag": Claude reviews the whole bag against your days and suggests changes you apply with one tap.
- **Find online:** when reviewing a new item, tell FitMe the brand and what it is (or paste a product link), open the
  product page in the app, and pick the shop's photo. FitMe cuts it out and re-tags it from the shop's description,
  and remembers the brand and product page. Your own photo is kept.
- Matching a new item online can be undone, keeps your edits if Claude can't re-tag it, and skips photos the shop
  won't serve. Links that open in a new tab now work in the in-app browser.
- Buttons that can't be used yet now look dimmed.
- Find online works on items already in your closet too, with Undo. Each item says whether it's matched to a
  product page, with buttons to view the page or change the match.
- Trip mode: Today links to the trip in progress, and "Wear this" logs the outfit.
- After a trip, tell FitMe what you wore. Pieces that came home unworn are less likely to be packed next time.
- Reactions now visibly change suggestions: one ✕ keeps an outfit out of the next day's picks, one ♥ brings a look
  back, and liked color pairings carry over to other pieces.
- New Insights screen (Closet → Insights): how many looks your closet makes, the best next buy, hard-to-style
  pieces, workhorses, pieces resting in the closet, and the color pairings FitMe learned. You can make FitMe forget
  what it learned.
- Today can read your calendar (when you allow it) and offer to dress for today's events, like a dinner or the gym.
- "Dress for it" marks only the event you tapped, even when several call for the same occasion.
- Tapping a piece in Insights opens it straight away (it used to bounce back first).
- No more jacket over a cardigan over a shirt on a mild day: a second layer is only suggested below about 14°.
- "Wear this" now keeps a history. Today shows what you're wearing, tapping "Wearing today" again (or Undo) takes
  it back, and Saved → Worn lists what you wore, day by day.
- Tap any outfit (or "See every piece") to see each piece in the order you'd put it on, with its colors, dress code,
  warmth and fit.
- Filter the closet by color, dress code and brand, and search by brand.
- Swap one piece of a suggestion on Today (or leave off a layer) from the outfit's pieces.
- Planning a trip fills in occasions from your calendar, like a wedding on day 3, when you've allowed calendar access.
- Dark mode: dark clothes now stand out on lighter photo tiles.
- Photograph your closet in one go: Closet → + → Take photos, shoot item after item, then Done sends them all to the
  inbox.
- On a mild, dry day outfits no longer add a jacket or mid layer you don't need, like a rain shell over a hoodie.
- Shoes now suit the outfit: brown with navy and earth tones, black for charcoal and formal wear, sneakers kept
  casual. Outfits that tie take turns day to day instead of always picking the same pair.
- Colors are matched the way stylists pair them: navy with burgundy or rust, grey with pink, olive with burgundy,
  and no navy with black. A new Color choice on Today (Neutral, Mixed, Colorful) sets the mood for the day.
- Trip packing no longer plans the same trousers more than three times between washes.
- Outfits dress your whole body for the weather: shorts and sandals on hot days, no jeans or boots at 30°, boots and
  a proper base layer in the cold, and no sweater with shorts.
- Rain matters: suggestions bring a jacket that keeps water out, and boots in cold rain. Trips in the rain pack rain
  gear when you have it.
- A ♥ counts for more, so liked outfits come back sooner.
- Dress codes are respected: formal means a dress shirt, tailored trousers, a jacket and dress shoes (a suit jacket
  only with its own trousers); work stays business casual, with no shorts, light-wash jeans or gym gear.
- New Hike occasion with boots and outdoor gear; Sport is now running and gym kit, and the beach leads with shorts
  and sandals. Calendar events like "hike" or "trail" pick Hike.
- Pieces in an outfit share a style: no technical fleece over a floral shirt, no gym wear with tailoring.
