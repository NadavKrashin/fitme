import FitEngine
import Foundation
import Testing
@testable import FitMe

struct CapsuleReviewerTests {
    let closet = try! DemoCloset.items()

    private func packedTrip() async -> TripDetails {
        await TripPlanner().pack(TripFixtures.trip(), closet: closet, profile: StyleProfile())
    }

    @Test func labelsPackedPiecesAndTheRestOfTheCloset() async {
        let details = await packedTrip()
        let labels = ClaudeCapsuleReviewer.Labels(details: details, closet: closet)

        #expect(labels.packed.count == details.packedItemIDs.count)
        #expect(labels.packed.first?.label == "P1")
        #expect(labels.others.allSatisfy { !details.packedItemIDs.contains($0.item.id) && $0.item.category.isCore })
        let brief = ClaudeCapsuleReviewer.brief(details, labels: labels)
        #expect(brief.contains("Trip: Lisbon (4 nights)."))
        #expect(brief.contains("Day 1, Lisbon"))
        #expect(brief.contains("P1: "))
        #expect(brief.contains("C1: "))
    }

    @Test func decodesChangesIntoItemIDs() async throws {
        let details = await packedTrip()
        let labels = ClaudeCapsuleReviewer.Labels(details: details, closet: closet)
        let json = """
        {"verdict":"Lean and versatile.","changes":[
          {"leave_out":"P1","bring":"C2","why":"More outfits."},
          {"leave_out":"P2","bring":"none","why":"Barely used."},
          {"leave_out":"none","bring":"none","why":"Nothing."},
          {"leave_out":"P1","bring":"C2","why":"Duplicate."},
          {"leave_out":"C3","bring":"P3","why":"Backwards."}
        ]}
        """

        let review = try ClaudeCapsuleReviewer.decode(json, labels: labels)

        #expect(review.verdict == "Lean and versatile.")
        #expect(review.changes == [
            CapsuleReview.Change(
                leaveOut: labels.packed[0].item.id,
                bring: labels.others[1].item.id,
                why: "More outfits."
            ),
            CapsuleReview.Change(leaveOut: labels.packed[1].item.id, bring: nil, why: "Barely used."),
        ])
    }

    @Test func schemaOnlyAllowsKnownLabels() async throws {
        let details = await packedTrip()
        let labels = ClaudeCapsuleReviewer.Labels(details: details, closet: closet)
        let schema = try String(
            data: JSONEncoder().encode(ClaudeCapsuleReviewer.schema(labels: labels)),
            encoding: .utf8
        )
        let text = try #require(schema)
        #expect(text.contains("\"P1\""))
        #expect(text.contains("\"C1\""))
        #expect(text.contains("\"none\""))
    }

    @Test func sendsOneStructuredRequest() async throws {
        let details = await packedTrip()
        let reply = #"{"verdict":"Good.","changes":[]}"#
        let transport = RecordingTransport(body: messagesResponse(text: reply))
        let reviewer = ClaudeCapsuleReviewer(client: ClaudeClient(apiKey: { "key" }, transport: transport))

        let review = try await reviewer.review(details, closet: closet)

        #expect(review == CapsuleReview(verdict: "Good.", changes: []))
        let body = try #require(await transport.requests.first?.httpBody)
        let json = try #require(String(bytes: body, encoding: .utf8))
        #expect(json.contains("\"json_schema\""))
        #expect(json.contains(ClaudeStylist.model))
    }
}
