import SwiftUI
import DupeCore

struct GroupDetailView: View {

    let group: ReviewGroup
    @ObservedObject var model: ReviewViewModel
    let loader: any ThumbnailLoading

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    ThumbnailView(item: group.keeper, side: 72, loader: loader)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.keeper.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(group.keeper.pixelWidth)x\(group.keeper.pixelHeight) · \(ByteFormatting.string(group.keeper.totalByteSize))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Staying")
            } footer: {
                Text("Every copy below was compared against this one directly. It is never offered for deletion.")
            }

            ForEach(group.items) { item in
                Section {
                    candidateRow(item)
                    ComparisonTable(keeper: group.keeper, candidate: item)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: model.selection.count)
        .navigationTitle(ScanCopy.title(for: group.tier))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func candidateRow(_ item: MediaItem) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                model.toggle(item.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: model.selection.isSelected(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(model.selection.isSelected(item.id) ? Color.accentColor : Color.secondary)
                    .symbolEffect(.bounce, value: model.selection.isSelected(item.id))
                    .scaleEffect(model.selection.isSelected(item.id) ? 1.08 : 1)

                ThumbnailView(item: item, side: 56, loader: loader)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ByteFormatting.string(item.totalByteSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("candidate.\(item.id)")
    }
}
