import FitEngine
import SwiftData
import SwiftUI

/// New photos waiting to become closet items: shows processing progress, failures, and leads into review.
struct InboxView: View {
    static let photoTip = "For the cleanest cutouts, lay each item flat or hang it against a plain background."

    @Environment(CaptureModel.self) private var capture
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CaptureDraft.createdAt) private var drafts: [CaptureDraft]
    @State private var path: [String] = []
    @State private var isConfirmingAcceptAll = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if capture.importing > 0 {
                    HStack(spacing: 12) {
                        ProgressView().frame(width: 56, height: 56)
                        Text("Importing \(capture.importing) photo\(capture.importing == 1 ? "" : "s")…")
                    }
                }
                if let note = capture.lastImportNote {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(drafts) { draft in
                    if draft.status == .processing {
                        DraftRow(draft: draft)
                    } else {
                        NavigationLink(value: draft.draftID) { DraftRow(draft: draft) }
                    }
                }
                .onDelete { offsets in offsets.map { drafts[$0] }.forEach(capture.discard) }
                .editorialRow()

                Section {} footer: { Text(Self.photoTip) }
            }
            .overlay {
                if drafts.isEmpty, capture.importing == 0 {
                    ContentUnavailableView(
                        "All caught up",
                        systemImage: "tray",
                        description: Text("New photos show up here.")
                    )
                }
            }
            .editorialCanvas()
            .navigationTitle("Inbox")
            .navigationDestination(for: String.self) { id in
                if let draft = drafts.first(where: { $0.draftID == id }) {
                    DraftReviewView(draft: draft) { showNext(after: id) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Accept all") { isConfirmingAcceptAll = true }
                        .disabled(readyDrafts.isEmpty)
                }
            }
            .confirmationDialog(
                "Add \(readyDrafts.count) items with their suggested tags?",
                isPresented: $isConfirmingAcceptAll,
                titleVisibility: .visible
            ) {
                Button("Add all to closet") {
                    readyDrafts.forEach { capture.confirm($0, as: $0.proposedItem) }
                }
            } message: {
                Text("You can still edit any item from the closet later.")
            }
        }
    }

    private var readyDrafts: [CaptureDraft] {
        drafts.filter { $0.status == .ready }
    }

    /// After reviewing one draft, go straight to the next reviewable one.
    private func showNext(after id: String) {
        let next = drafts.first { $0.draftID != id && $0.status != .processing }
        path = next.map { [$0.draftID] } ?? []
    }
}

private struct DraftRow: View {
    @Environment(CaptureModel.self) private var capture
    let draft: CaptureDraft

    var body: some View {
        HStack(spacing: 12) {
            if draft.status == .processing {
                ProgressView()
                    .frame(width: 56, height: 56)
            } else {
                ItemThumbnail(item: draft.proposedItem, image: draft.cutout)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(draft.status == .failed ? .red : .secondary)
            }
            Spacer(minLength: 0)
            if draft.status == .failed {
                Button("Retry") { Task { await capture.retry(draft) } }
                    .buttonStyle(.pill(.quiet))
            }
        }
    }

    private var title: String {
        switch draft.status {
        case .processing: "Processing…"
        case .ready: draft.proposedItem.name
        case .failed: "Needs tags"
        }
    }

    private var subtitle: String {
        switch draft.status {
        case .processing: "Cutting out and tagging"
        case .ready: "Ready to review"
        case .failed: draft.errorMessage ?? "Something went wrong."
        }
    }
}

/// Review one new item: check the suggested tags, fix anything wrong, add it to the closet.
struct DraftReviewView: View {
    @Environment(CaptureModel.self) private var capture
    let draft: CaptureDraft
    let onFinished: () -> Void
    @State private var item: Item

    init(draft: CaptureDraft, onFinished: @escaping () -> Void) {
        self.draft = draft
        self.onFinished = onFinished
        _item = State(initialValue: draft.proposedItem)
    }

    var body: some View {
        Form {
            Section {
                ItemThumbnail(item: item, image: draft.cutout, size: 220)
                    .frame(maxWidth: .infinity)
                if let error = draft.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .listRowBackground(Color.clear)

            ItemEditorSections(item: $item)
        }
        .editorialCanvas()
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Discard", role: .destructive) {
                    capture.discard(draft)
                    onFinished()
                }
                .buttonStyle(.pill(.quiet))
                Button("Add to closet") {
                    capture.confirm(draft, as: item)
                    onFinished()
                }
                .buttonStyle(.pill(.primary))
                .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
            .background(Theme.canvas)
        }
    }
}
