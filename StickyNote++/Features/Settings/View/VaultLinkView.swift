import SwiftData
import SwiftUI
import UIKit

/// The app's vault link, handed down from the app root. nil in previews: the Vault link row is
/// then left out.
private struct VaultSyncKey: EnvironmentKey {
    static let defaultValue: VaultSync? = nil
}

extension EnvironmentValues {
    var vaultSync: VaultSync? {
        get { self[VaultSyncKey.self] }
        set { self[VaultSyncKey.self] = newValue }
    }
}

/// Settings → Vault (DECISIONS.md, "6: vault link"): one row, "Vault link", with the status line's
/// symbol and text, opening `VaultLinkView`. The labels match the setup note on Liam's Desktop.
struct VaultLinkSettingsSection: View {
    @Environment(\.vaultSync) private var vault

    var body: some View {
        if let vault {
            VaultLinkRow(vault: vault)
        }
    }
}

private struct VaultLinkRow: View {
    @ObservedObject var vault: VaultSync

    var body: some View {
        Section {
            NavigationLink {
                VaultLinkView(vault: vault)
            } label: {
                LabeledContent {
                    Text(vault.status.text())
                        .lineLimit(1)
                } label: {
                    Label("Vault link", systemImage: "link")
                }
            }
        } header: {
            Text("Vault")
        } footer: {
            Text("Tasks from Now.md come in as one-offs; your habit results go back to the vault once a day.")
        }
    }
}

extension View {
    /// Screenshot harness only: opens the Vault link screen on appear when the harness asks for it.
    /// Elsewhere it does nothing.
    func vaultLinkHarnessDestination() -> some View {
        modifier(VaultLinkHarnessDestination())
    }
}

private struct VaultLinkHarnessDestination: ViewModifier {
    @Environment(\.vaultSync) private var vault
    @State private var isPresented = false

    func body(content: Content) -> some View {
#if DEBUG
        content
            .navigationDestination(isPresented: $isPresented) {
                if let vault {
                    VaultLinkView(vault: vault)
                }
            }
            .task {
                guard let vault, vault.opensLinkScreenOnAppear else { return }
                vault.opensLinkScreenOnAppear = false
                try? await Task.sleep(for: .milliseconds(300))
                isPresented = true
            }
#else
        content
#endif
    }
}

/// Settings → Vault link: the status line, the GitHub token (paste, save, remove) and what the
/// link does. The token is never shown again once saved: the field stays empty.
struct VaultLinkView: View {
    @ObservedObject var vault: VaultSync
    @Environment(\.modelContext) private var modelContext
    @State private var draft = ""
    @State private var isConfirmingRemoval = false
    @State private var saveError: String?

    var body: some View {
        Form {
            statusSection
            tokenSection
            aboutSection
        }
        .navigationTitle("Vault link")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("Remove the token?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove token", role: .destructive) {
                vault.removeToken()
                TaskWidgetReloader.reloadTopTasksWidget()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tasks already imported stay on your lists. Nothing more is fetched or sent until you paste a token again.")
        }
        .onAppear {
            vault.reloadFromDefaults()
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: vault.status.symbolName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(vault.status.isProblem ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(vault.status.text())
                    .font(.body.weight(vault.status.isProblem ? .semibold : .regular))
                Spacer(minLength: 0)
                if vault.isChecking {
                    ProgressView()
                        .accessibilityLabel("Checking")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status: \(vault.status.text())")

            if let habits = vault.habitsStatus {
                LabeledContent("Habits", value: habitsText(habits))
            }
            if vault.hasToken, let expiry = vault.tokenExpiry {
                LabeledContent("Token expires", value: expiry.formatted(date: .abbreviated, time: .omitted))
            }
            if vault.hasToken {
                Button {
                    Task { await vault.refreshTasks(context: modelContext) }
                } label: {
                    Label("Check now", systemImage: "arrow.clockwise")
                }
                .disabled(vault.isChecking)
            }
        } header: {
            Text("Status")
        } footer: {
            Text(statusFooter)
        }
    }

    private var tokenSection: some View {
        Section {
            SecureField("GitHub token", text: $draft, prompt: Text(vault.hasToken ? "GitHub token (saved)" : "GitHub token"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .accessibilityHint(vault.hasToken ? "A token is saved. Paste a new one to replace it." : "Paste the token from GitHub.")

            HStack {
                PasteButton(payloadType: String.self) { strings in
                    draft = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)

                Spacer()

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(trimmedDraft.isEmpty)
            }

            if vault.hasToken {
                // A trash shape as well as the red, so it reads as destructive in greyscale.
                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    Label("Remove token", systemImage: "trash")
                }
            }
        } header: {
            Text("GitHub token")
        } footer: {
            Text(saveError ?? "A fine-grained token for lratcliffe1/Obsidian only, with Contents read and write. It’s kept in this iPhone’s Keychain and never shown again.")
        }
    }

    private var aboutSection: some View {
        Section {
            Text("""
            The app reads 7 Projects/StickyNotes/tasks.json (written from Now.md) when it opens, when you come back to it, \
            in the background and from the widget. New tasks appear as one-offs on their day. Ticks and bumps made here \
            are never overwritten. Once a day, after the morning, it sends each day’s results to habits/ in the same folder.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("How it works")
        }
    }

    // MARK: - Helpers

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var statusFooter: String {
        switch vault.status.kind {
        case .tokenNotAccepted:
            return "The token was mistyped, has been revoked, or doesn’t include lratcliffe1/Obsidian with Contents read and write. Make a new one and paste it here."
        case .tokenExpired:
            return "Make a new token on GitHub and paste it here. Nothing is lost meanwhile."
        case .noTasksFile:
            return "The routine hasn’t written tasks.json yet. It runs when Now.md changes, and with the 07:00 brief."
        case .offline:
            return "The app tries again when you next open it."
        case .newerVersion:
            return "Update the app to read it. Your lists are unchanged."
        case .badFile:
            return "Nothing was changed. The next routine run should fix the file."
        default:
            if vault.tokenLocation == .appOnly {
                return "The widget shows what the app last imported; it doesn’t fetch on its own."
            }
            return ""
        }
    }

    private func habitsText(_ habits: VaultHabitsStatus) -> String {
        let when = VaultStatus.relativeTime(habits.date, now: Date(), calendar: .current)
        switch habits.outcome {
        case .sent: return "Sent \(when)"
        case .gaveUp: return "Not sent today (changed elsewhere)"
        case .failed: return "Not sent yet (\(when))"
        }
    }

    private func save() {
        do {
            try vault.saveToken(trimmedDraft)
            draft = ""
            saveError = nil
            Task {
                await vault.refreshTasks(context: modelContext)
                TaskWidgetReloader.reloadTopTasksWidget()
            }
        } catch {
            saveError = "The token couldn’t be saved to the Keychain. Try again."
        }
    }
}
