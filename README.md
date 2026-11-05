# FitMe

A personal iOS app that catalogs the clothes you own, suggests outfits that actually look good together, and packs the smallest set of items that covers a whole trip.

## Layout

- `Packages/FitEngine` — pure-Swift outfit engine (color math, rules, scoring, outfit generation, trip packing optimizer). No UI dependencies; run `swift test` inside it.
- `FitMe/` — the SwiftUI app (not created yet; needs Xcode 15+ for iOS 17 / SwiftData).
