import SwiftUI

/// Scrollable grid of photo thumbnails with selection + "needs lens" badges.
struct PhotoGridView: View {
    @ObservedObject var store: PhotoStore

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.items) { item in
                    PhotoCell(item: item, isSelected: store.selection.contains(item.id))
                        .onTapGesture { store.toggle(item) }
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct PhotoCell: View {
    @ObservedObject var item: PhotoItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.12),
                                    lineWidth: isSelected ? 3 : 1)
                    )

                if item.needsLens {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.white, .red)
                        .font(.title3)
                        .padding(6)
                        .help("No focal length — needs a lens")
                }

                if item.wasTagged {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.white, .green)
                        .font(.title3)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .help("Lens tag written this session")
                }
            }

            Text(item.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(item.needsLens ? Color.red : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = item.thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(nsColor: .quaternaryLabelColor)
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .font(.largeTitle)
            }
        }
    }

    private var subtitle: String {
        if item.isLoadingMeta { return "reading…" }
        if item.needsLens { return "no lens" }
        return item.currentLensDescription ?? "has focal length"
    }
}
