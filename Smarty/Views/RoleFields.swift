import SwiftUI

/// Field picker plus an optional extra prompt.
///
/// Returns bare rows rather than its own `Form` so the same controls can sit inside the
/// Settings form and inside the overlay's role popover without nesting forms.
/// Every edit writes straight through to `SettingsStore`, so there is no Save button.
struct RoleFields: View {
    /// Passed in rather than read from `@Environment`: the floating overlay is hosted in an
    /// `NSHostingView` with no environment injected, so a lookup there would crash.
    let store: SettingsStore

    private var role: RoleProfile { store.settings.roleProfile }

    var body: some View {
        Picker("Field", selection: Binding(
            get: { role.field },
            set: { value in store.update { $0.roleProfile.field = value } }
        )) {
            ForEach(InterviewRoleCategory.allCases) { category in
                Section(category.displayName) {
                    ForEach(category.fields) { field in
                        Text(field.displayName).tag(field)
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Prompt (optional)")
            TextEditor(text: Binding(
                get: { role.notes },
                set: { value in store.update { $0.roleProfile.notes = value } }
            ))
            .font(.system(.body, design: .default))
            .frame(minHeight: 110)
            .overlay(alignment: .topLeading) {
                if role.notes.isEmpty {
                    Text("Extra instructions for this interview — tone, what to emphasize, guidelines to follow.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
