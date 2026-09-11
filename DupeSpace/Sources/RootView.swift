import SwiftUI
import DupeCore

struct RootView: View {

    @State private var snapshot: StorageSnapshot?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let snapshot {
                        capacityRow(snapshot)
                    } else {
                        Text("Storage unavailable")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("storage.unavailable")
                    }
                } header: {
                    Text("This device")
                }

                Section {
                    Text("Photo library scanning arrives next.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Duplicates")
                } footer: {
                    Text("Only this device's photo library and folders you pick are ever read. iOS does not let any app see what other apps store, so that space is not broken down here.")
                }
            }
            .navigationTitle("DupeSpace")
        }
        .task {
            snapshot = StorageProbe.current()
        }
    }

    @ViewBuilder
    private func capacityRow(_ snapshot: StorageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(ByteFormatting.string(snapshot.usedCapacity)) of \(ByteFormatting.string(snapshot.totalCapacity)) used")
                .font(.headline)
                .accessibilityIdentifier("storage.headline")

            ProgressView(value: snapshot.usedFraction)
                .accessibilityIdentifier("storage.bar")

            Text("\(ByteFormatting.string(snapshot.availableCapacity)) free — estimated, iOS counts space it can purge as free.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("storage.caveat")
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RootView()
}
