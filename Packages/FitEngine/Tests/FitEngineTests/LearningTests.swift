import Foundation
import Testing
@testable import FitEngine

struct LearningTests {
    let generator = OutfitGenerator()

    /// One ✕ should be enough: the rejected outfit doesn't come back in the next day's suggestions.
    @Test func dislikedSuggestionDropsOutOfTheTopFive() throws {
        var context = Fixtures.context(.casual)
        let before = generator.suggest(from: Fixtures.closet, context: context, limit: 5)
        let rejected = try #require(before.first)

        var profile = StyleProfile()
        profile.record(.disliked, for: rejected.outfit)
        context.profile = profile
        let after = generator.suggest(from: Fixtures.closet, context: context, limit: 5)

        #expect(!after.contains(rejected))
    }

    /// One ♥ on an outfit just outside the suggestions brings that look in (possibly with a layer over it, since
    /// suggestions keep one outfit per top).
    @Test func likedOutfitMovesIntoTheTopFive() throws {
        var context = Fixtures.context(.casual)
        let ranked = generator.suggest(from: Fixtures.closet, context: context, limit: 10)
        let liked = try #require(ranked.last)

        var profile = StyleProfile()
        profile.record(.liked, for: liked.outfit)
        context.profile = profile
        let after = generator.suggest(from: Fixtures.closet, context: context, limit: 5)

        let likedItems = Set(liked.outfit.items)
        #expect(after.contains { likedItems.isSubset(of: $0.outfit.items) })
    }

    /// Liking navy with white lifts other navy-and-white outfits a little, even with none of the same pieces.
    @Test func colorPairingsGeneralizeToOtherPieces() {
        let liked = [makeItem("navy chinos", .bottom, ["#27324A"]), makeItem("white shirt", .top, ["#F7F7F5"])]
        let other = [makeItem("navy jeans", .bottom, ["#1F2A44"]), makeItem("white tee", .top, ["#F5F5F2"])]
        let unrelated = [makeItem("olive cargo", .bottom, ["#5A6140"]), makeItem("rust polo", .top, ["#B5562F"])]

        var profile = StyleProfile()
        profile.record(.liked, for: Outfit(items: liked))

        #expect(profile.affinityScore(other) > 0.5)
        #expect(profile.affinityScore(other) < profile.affinityScore(liked))
        #expect(profile.affinityScore(unrelated) == 0.5)
    }

    @Test func learningMovesTheScoreByAtMostItsPoints() {
        let outfit = Fixtures.outfit("t05", "b04", "s01")
        var context = Fixtures.context(.casual)
        let neutral = OutfitScorer().score(outfit, context: context).total

        var profile = StyleProfile()
        for _ in 0 ..< 10 {
            profile.record(.disliked, for: outfit)
        }
        context.profile = profile
        let disliked = OutfitScorer().score(outfit, context: context).total

        #expect(neutral - disliked > 7)
        #expect(neutral - disliked <= ScoreWeights().learnedPoints)
    }

    @Test func anEmptyProfileChangesNothing() {
        let outfit = Fixtures.outfit("t05", "b04", "s01")
        var context = Fixtures.context(.casual)
        let withoutProfile = OutfitScorer().score(outfit, context: context).total
        context.profile = StyleProfile()
        #expect(OutfitScorer().score(outfit, context: context).total == withoutProfile)
    }

    @Test func undoingEveryReactionLeavesAnEmptyProfile() {
        let outfit = Fixtures.outfit("t05", "b04", "s01")
        var profile = StyleProfile()
        profile.record(.liked, for: outfit)
        profile.record(.wore, for: outfit)
        profile.revert(.wore, for: outfit)
        profile.revert(.liked, for: outfit)
        #expect(profile.isEmpty)
    }

    @Test func colorPairingsListWhatWasLearned() {
        let navyWhite = Outfit(items: [makeItem("b", .bottom, ["#27324A"]), makeItem("t", .top, ["#F7F7F5"])])
        let oliveRust = Outfit(items: [makeItem("c", .bottom, ["#5A6140"]), makeItem("p", .top, ["#B5562F"])])
        var profile = StyleProfile()
        for _ in 0 ..< 3 {
            profile.record(.liked, for: navyWhite)
            profile.record(.disliked, for: oliveRust)
        }

        let pairings = profile.colorPairings()

        #expect(pairings.liked.map(\.id) == ["navy|white"])
        #expect(pairings.disliked.map(\.id) == ["olive|red"])
    }

    /// Profiles stored before color learning existed must still load, or the user's history would reset.
    @Test func decodesAProfileSavedBeforeColorLearning() throws {
        let old = Data(#"{"pairAffinity":{"a|b":0.4}}"#.utf8)
        let profile = try JSONDecoder().decode(StyleProfile.self, from: old)
        #expect(profile.pairAffinity == ["a|b": 0.4])
        #expect(profile.colorAffinity.isEmpty)
    }
}

struct ColorFamilyTests {
    @Test(arguments: [
        ("#1A1A1A", ColorFamily.black), ("#F7F7F5", .white), ("#6E6E70", .charcoal), ("#9A9A9A", .grey),
        ("#27324A", .navy), ("#8FA9C7", .denim), ("#C8B48F", .khaki), ("#6B4226", .brown),
        ("#5A6140", .olive), ("#B5562F", .red), ("#2E6B4F", .green),
    ])
    func classifiesClosetColors(hex: String, expected: ColorFamily) {
        #expect(ItemColor(hex: hex).family == expected)
    }
}
