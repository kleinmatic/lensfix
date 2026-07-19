import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = PhotoStore()
    @State private var keepBackup = true

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if store.items.isEmpty {
                    emptyState
                } else {
                    PhotoGridView(store: store)
                }
                Divider()
                statusBar
            }
            .frame(minWidth: 480)

            LensFormView(store: store, keepBackup: $keepBackup)
        }
        .frame(minWidth: 820, minHeight: 560)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .overlay(alignment: .top) {
            if store.exiftoolMissing { exiftoolBanner }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                openPanel()
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .fixedSize()

            Divider().frame(height: 18)

            Text("Select:")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            Button("Untagged") { store.selectUntagged() }
                .fixedSize()
                .disabled(store.untaggedCount == 0)
            Button("All") { store.selectAll() }
                .fixedSize()
                .disabled(store.items.isEmpty)
            Button("None") { store.clearSelection() }
                .fixedSize()
                .disabled(store.selection.isEmpty)

            Spacer(minLength: 8)

            if !store.items.isEmpty {
                Button { store.clearTagged() } label: {
                    Label("Clear tagged", systemImage: "checkmark.circle")
                }
                .fixedSize()
                .disabled(store.taggedCount == 0)
                .help("Remove already-tagged photos from this work area, keeping the ones that still need a lens (does not delete files)")

                Button { store.clear() } label: {
                    Label("Clear list", systemImage: "xmark.circle")
                }
                .fixedSize()
                .help("Remove all photos from this work area (does not delete files)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusBar: some View {
        HStack {
            Text(store.status)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if !store.items.isEmpty {
                Text("\(store.selection.count) selected · \(store.untaggedCount) need lens")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop photos here, or click Open…")
                .foregroundStyle(.secondary)
            Text("Photos missing a focal length get a red badge.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var exiftoolBanner: some View {
        Text("exiftool not found — install with `brew install exiftool`, then reopen the app.")
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.9))
            .foregroundStyle(.white)
    }

    // MARK: - Open / drop

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Open"
        if panel.runModal() == .OK {
            store.open(urls: panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { store.open(urls: urls) }
        }
        return true
    }
}
