import Testing
@testable import FitEngine

struct ScorerTests {
    let scorer = OutfitScorer()
    let smartCasual = Fixtures.context(.smartCasual)

    @Test func classicNeutralsBeatClashingColors() {
        // White oxford + beige chinos + brown loafers vs. purple + green + red.
        let classic = Fixtures.outfit("t07", "b04", "s03")
        let clash = Outfit(items: [
            makeItem("purple", .top, ["#6B2D8C"], formality: 3),
            makeItem("green", .bottom, ["#2F7D3A"], formality: 3),
            makeItem("red", .shoes, ["#C8202F"], formality: 3, warmth: 2),
        ])
        let good = scorer.score(classic, context: smartCasual)
        let bad = scorer.score(clash, context: smartCasual)
        #expect(good.color > 0.8)
        #expect(bad.color < 0.6)
        #expect(good.total > bad.total + 10)
    }

    @Test func oneAccentColorBeatsAllNeutrals() {
        let accent = Fixtures.outfit("t13", "b05", "s01") // rust polo, navy chinos
        let allNeutral = Fixtures.outfit("t07", "b05", "s01")
        #expect(OutfitScorer.colorHarmony(accent) > OutfitScorer.colorHarmony(allNeutral))
    }

    @Test func twoBoldPatternsArePenalizedUnlessTheyShareAColor() {
        let floral = makeItem("floral", .top, ["#F1E6D2", "#C2463E"], pattern: .floral)
        let check = makeItem("check", .bottom, ["#2E6B4F", "#1F2A44"], pattern: .check)
        let creamCheck = makeItem("creamCheck", .bottom, ["#2E6B4F", "#F1E6D2"], pattern: .check)
        let plain = makeItem("plain", .bottom, ["#1C1C1C"])

        #expect(OutfitScorer.patternBalance([floral, plain]) == 1)
        #expect(OutfitScorer.patternBalance([floral, check]) < 0.5)
        #expect(OutfitScorer.patternBalance([floral, creamCheck]) > OutfitScorer.patternBalance([floral, check]))
    }

    @Test func onlyOneStatementPiece() {
        let a = makeItem("a", .top, ["#D9A21B"], statement: true)
        let b = makeItem("b", .bottom, ["#B3262E"], statement: true)
        #expect(OutfitScorer.statementBudget([a]) > OutfitScorer.statementBudget([a, b]))
    }

    @Test func doubleOversizedIsPenalized() {
        let top = makeItem("top", .top, ["#FFFFFF"], fit: .oversized)
        let baggy = makeItem("baggy", .bottom, ["#1C1C1C"], fit: .oversized)
        let slim = makeItem("slim", .bottom, ["#1C1C1C"], fit: .slim)
        #expect(OutfitScorer.fitBalance(Outfit(items: [top, baggy])) < OutfitScorer.fitBalance(Outfit(items: [
            top,
            slim,
        ])))
    }

    @Test func feedbackShiftsAffinity() {
        var profile = StyleProfile()
        let outfit = Fixtures.outfit("t05", "b04", "s01")
        var context = Fixtures.context(.casual)
        let before = scorer.score(outfit, context: context).total

        profile.record(.liked, for: outfit)
        profile.record(.wore, for: outfit)
        context.profile = profile
        #expect(scorer.score(outfit, context: context).total > before)

        profile.record(.disliked, for: outfit)
        profile.record(.disliked, for: outfit)
        #expect(profile.affinityScore(outfit.coreItems) < 0.5)
    }
}

struct StatementNeutralityTests {
    /// A lone statement piece is fine but shouldn't win on its own; otherwise one loud shirt tops every list.
    @Test func oneStatementPieceIsNeitherRewardedNorPenalized() {
        let loud = makeItem("loud", .top, ["#C2463E"], statement: true)
        let plain = makeItem("plain", .bottom, ["#1C1C1C"])
        #expect(OutfitScorer.statementBudget([plain]) == OutfitScorer.statementBudget([loud, plain]))
    }
}

struct ProfileRevertTests {
    @Test func revertUndoesAReaction() {
        var profile = StyleProfile()
        let outfit = Fixtures.outfit("t05", "b04", "s01")
        profile.record(.liked, for: outfit)
        profile.record(.disliked, for: outfit)

        profile.revert(.disliked, for: outfit)

        let likedOnly = { () -> StyleProfile in
            var p = StyleProfile()
            p.record(.liked, for: outfit)
            return p
        }()
        #expect(profile == likedOnly)
    }
}
