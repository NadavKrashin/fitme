import SwiftUI

struct SettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(AIConsentModel.self) private var consent
    @State private var model: SettingsModel?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    AIConsentSection(consent: consent)
                    switch dependencies.claudeAccess {
                    case .ownKey:
                        if let model {
                            APIKeySection(model: model)
                        }
                    case .proxy:
                        Section("Claude") {
                            Text("Tagging and the stylist are included. There's nothing to set up.")
                                .foregroundStyle(Theme.inkMuted)
                        }
                    case .unavailable:
                        Section("Claude") {
                            Text("Claude isn't set up in this version. You can still tag clothes by hand.")
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                    #if STAGING
                    DemoClosetSection()
                    #endif
                    Section("About") {
                        LabeledContent("Environment", value: AppEnvironment.current.displayName)
                        LabeledContent("Version", value: AppEnvironment.versionDescription)
                        Link("Privacy policy", destination: PrivacyLinks.policy)
                        Link("Help and contact", destination: PrivacyLinks.support)
                    }
                }
                .editorialRow()
            }
            .editorialCanvas()
            .tint(Theme.terracotta)
            .navigationTitle("Settings")
        }
        .task {
            if model == nil {
                model = SettingsModel(secrets: dependencies.secrets)
            }
        }
    }
}

/// The Claude permission asked at first launch, changeable here.
private struct AIConsentSection: View {
    let consent: AIConsentModel

    var body: some View {
        Section {
            Toggle("Use Claude", isOn: Binding(get: { consent.isAllowed }, set: { consent.answer(allowed: $0) }))
        } header: {
            Text("AI")
        } footer: {
            Text("Claude, Anthropic's AI, tags the photos you add and powers the stylist. It receives your clothing "
                + "photos and descriptions. Off, you tag clothes yourself; outfit suggestions still work.")
        }
    }
}

private struct APIKeySection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section {
            if let hint = model.savedKeyHint {
                LabeledContent("Saved key", value: hint)
                Button("Remove key", role: .destructive, action: model.removeKey)
            }
            SecureField(model.savedKeyHint == nil ? "Paste API key" : "Replace API key", text: $model.apiKeyDraft)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Save key", action: model.saveKey)
                .disabled(!model.canSave)
            if let error = model.errorMessage {
                Text(error).foregroundStyle(Theme.terracotta)
            }
        } header: {
            Text("Claude API key")
        } footer: {
            Text("Used for tagging items and styling advice. Stored only in this device's Keychain.")
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environment(\.dependencies, .preview())
        .environment(PreviewData.captureModel)
        .environment(AIConsentModel(store: PreviewConsent()))
        .modelContainer(PreviewData.container)
}
#endif
