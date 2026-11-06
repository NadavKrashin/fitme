import os
import SwiftData
import SwiftUI

/// Every trip: on the road now, coming up, and past.
struct TripsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TripRecord.startDate) private var trips: [TripRecord]
    @State private var isPlanning = false
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if trips.isEmpty {
                        emptyState
                    } else {
                        section("On the road", trips.filter { $0.details.phase() == .ongoing })
                        section("Coming up", trips.filter { $0.details.phase() == .upcoming })
                        section("Past trips", trips.filter { $0.details.phase() == .finished }.reversed())
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 80)
            }
            .navigationTitle("Trips")
            .editorialCanvas()
            .toolbar {
                if !trips.isEmpty {
                    Button("Plan a trip", systemImage: "plus") { isPlanning = true }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let trip = trips.first(where: { $0.tripID == id }) {
                    TripDetailView(trip: trip)
                }
            }
            .sheet(isPresented: $isPlanning) {
                TripWizardView(editing: nil) { path = [$0.tripID] }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "suitcase.rolling")
                .font(.largeTitle)
                .foregroundStyle(Theme.terracotta)
            Text("Pack less, wear everything")
                .font(Theme.title(24))
                .foregroundStyle(Theme.ink)
            Text(
                "Tell FitMe where you're going and what each day holds. It picks the fewest pieces from your "
                    + "closet that dress every day, and plans the outfits."
            )
            .font(.callout)
            .foregroundStyle(Theme.inkMuted)
            Button("Plan a trip") { isPlanning = true }
                .buttonStyle(.pill(.accent))
                .padding(.top, 4)
        }
        .card(padding: 22)
    }

    @ViewBuilder
    private func section(_ title: String, _ trips: some Collection<TripRecord>) -> some View {
        if !trips.isEmpty {
            SectionTitle(text: title)
            ForEach(Array(trips)) { trip in
                NavigationLink(value: trip.tripID) {
                    TripRow(details: trip.details)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete trip", systemImage: "trash", role: .destructive) { delete(trip) }
                }
            }
        }
    }

    private func delete(_ trip: TripRecord) {
        modelContext.delete(trip)
        do {
            try modelContext.save()
        } catch {
            Logger.trips.error("Couldn't delete the trip: \(String(describing: error))")
        }
    }
}

private struct TripRow: View {
    let details: TripDetails

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: details.phase() == .ongoing ? "airplane" : "suitcase")
                .font(.title3)
                .foregroundStyle(Theme.sageInk)
                .frame(width: 46, height: 46)
                .background(Theme.sage, in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(details.name)
                    .font(Theme.title(19))
                    .foregroundStyle(Theme.ink)
                Text("\(details.dateRange) · \(details.dayCountText)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                HStack(spacing: 6) {
                    Badge(text: "\(details.packedItemIDs.count) pieces · \(details.outfitCount) outfits")
                    if details.phase() == .finished, details.debrief == nil {
                        Badge(text: "How did it go?", tint: (Theme.butter, Theme.butterInk))
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 14)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    TripsView()
        .environment(\.dependencies, .preview())
        .modelContainer(PreviewData.container)
}
#endif
