import SwiftUI

/// The role brief inputs — title, field, company, coding preference, job description.
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
        TextField("Job title", text: Binding(
            get: { role.title },
            set: { value in store.update { $0.roleProfile.title = value } }
        ), prompt: Text("e.g. Senior Product Manager"))

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

        TextField("Company (optional)", text: Binding(
            get: { role.company },
            set: { value in store.update { $0.roleProfile.company = value } }
        ))

        Picker("Code in answers", selection: Binding(
            get: { role.codingPreference },
            set: { value in store.update { $0.roleProfile.codingPreference = value } }
        )) {
            ForEach(CodingPreference.allCases) { preference in
                Text(preference.displayName).tag(preference)
            }
        }
        Text(codingHint)
            .font(.caption)
            .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 4) {
            Text("Job description")
            TextEditor(text: Binding(
                get: { role.notes },
                set: { value in store.update { $0.roleProfile.notes = value } }
            ))
            .font(.system(.body, design: .default))
            .frame(minHeight: 110)
            .overlay(alignment: .topLeading) {
                if role.notes.isEmpty {
                    Text("Paste the posting here — responsibilities, seniority, tools, domain.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            Text("Background only — answers still never invent employers, metrics, or projects.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var codingHint: String {
        switch role.codingPreference {
        case .auto:
            return role.field.expectsCoding
                ? "\(role.field.displayName) is technical — code, complexity, and your preferred language stay on."
                : "\(role.field.displayName) is non-technical — answers skip code, algorithms, and Big-O."
        case .include:
            return "Forced on, whatever the field. Use this for annotation or generalist roles with a coding component."
        case .exclude:
            return "Forced off, whatever the field."
        }
    }
}
