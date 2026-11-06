import SwiftUI

struct SettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var model: SettingsModel?

    var body: some View {
        NavigationStack {
            Form {
                if let model {
                    APIKeySection(model: model)
                }
                #if STAGING
                DemoClosetSection()
                #endif
                Section("About") {
                    LabeledContent("Environment", value: AppEnvironment.current.displayName)
                    LabeledContent("Version", value: AppEnvironment.versionDescription)
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            if model == nil {
                model = SettingsModel(secrets: dependencies.secrets)
            }
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
                Text(error).foregroundStyle(.red)
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
        .modelContainer(PreviewData.container)
}
#endif
