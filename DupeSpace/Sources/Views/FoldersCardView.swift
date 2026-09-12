import SwiftUI
import DupeCore

/// Folders the user has handed over, and the way to hand over more.
///
/// iOS gives no app a view of the file system, so this list *is* the app's reach outside the
/// photo library. Saying that plainly is better than leaving people to wonder why their
/// Downloads folder is not being checked.
struct FoldersCardView: View {

    let folders: [GrantedFolder]
    let message: String?
    let onAdd: () -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        Card("Folders you have shared", symbolName: "folder", identifier: "folders.title") {
            if folders.isEmpty {
                Text("Nothing yet. Add a folder from Files — iCloud Drive, On My iPhone, or an external drive — and it gets scanned alongside your photo library.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("folders.empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                        if index > 0 {
                            Divider().overlay(DS.hairline)
                        }
                        row(folder)
                    }
                }
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(DS.tier(.burstLeftover))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("folders.message")
            }

            Button {
                onAdd()
            } label: {
                Label("Add a folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.keyQuiet)
            .accessibilityIdentifier("folders.add")
        }
    }

    @ViewBuilder
    private func row(_ folder: GrantedFolder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.footnote)
                .foregroundStyle(DS.deep)
                .frame(width: 22)

            Text(folder.displayName)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button {
                onRemove(folder.id)
            } label: {
                // Removing a grant is destructive and was drawn as decoration: a grey glyph in
                // a 22pt box. Red, and a finger wide.
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(DS.deep)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("folders.remove.\(folder.id.uuidString)")
        }
        .padding(.vertical, 9)
    }
}
