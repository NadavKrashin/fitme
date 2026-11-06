import SwiftUI

// MARK: Surfaces

extension View {
    /// The warm paper canvas behind a whole screen, including lists and forms.
    func editorialCanvas() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
    }

    /// A raised card on the canvas.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: Theme.shadow, radius: 14, y: 6)
    }

    /// Rows of a `Form` or `List` drawn as cards on the canvas.
    func editorialRow() -> some View {
        listRowBackground(Theme.card)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.title())
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: Buttons

struct PillButtonStyle: ButtonStyle {
    enum Kind {
        /// Ink on paper: the one main action in a view.
        case primary
        /// Terracotta: Claude-powered or celebratory actions.
        case accent
        /// Sage: secondary actions.
        case quiet
    }

    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .foregroundStyle(foreground)
            .background(background, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.canvas
        case .accent: Theme.onTerracotta
        case .quiet: Theme.sageInk
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.ink
        case .accent: Theme.terracotta
        case .quiet: Theme.sage
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ kind: PillButtonStyle.Kind = .primary) -> PillButtonStyle {
        PillButtonStyle(kind: kind)
    }
}

/// A round icon button, e.g. save and dismiss on an outfit card.
struct CircleIconButton: View {
    let symbol: String
    let label: String
    var isOn = false
    var onColor: Color = Theme.terracotta
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "\(symbol).fill" : symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isOn ? onColor : Theme.inkMuted)
                .frame(width: 44, height: 44)
                .background(Theme.canvas, in: .circle)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: Toast

/// A short confirmation that something happened, with an optional undo.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let message: String
    var undo: (@MainActor () -> Void)?

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.symbol)
                .foregroundStyle(Theme.terracotta)
            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(Theme.canvas)
            Spacer(minLength: 8)
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    onDismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.butter)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.ink, in: .capsule)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Shows `toast` just above the tab bar for a few seconds; tapping Undo or waiting dismisses it.
    /// A bottom safe-area inset (not an overlay) keeps it clear of the floating tab bar.
    func toast(_ toast: Toast?, onDismiss: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom) {
            if let toast {
                ToastView(toast: toast, onDismiss: onDismiss)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        // A replaced toast cancels this task; only dismiss when the full time has passed.
                        do {
                            try await Task.sleep(for: .seconds(4))
                            onDismiss()
                        } catch {}
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: toast)
    }
}
