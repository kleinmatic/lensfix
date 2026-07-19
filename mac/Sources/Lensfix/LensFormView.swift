import SwiftUI
import UniformTypeIdentifiers

/// Right-hand panel: load a lens from the CSV (optional), review the selection's
/// existing values, edit fields, and apply to the whole selection.
struct LensFormView: View {
    @ObservedObject var store: PhotoStore
    @Binding var keepBackup: Bool

    @State private var showOverwriteConfirm = false

    private let primaryFields: [LensField] = [.lens, .focalLength, .maxApertureValue, .focalLengthIn35mm]
    private let secondaryFields: [LensField] = [.lensMake, .lensModel, .lensSerialNumber]

    private var selectedCount: Int { store.selection.count }
    private var hasSelection: Bool { selectedCount > 0 }
    private var canApply: Bool {
        hasSelection && store.form.hasAnyValue && !store.isBusy && !store.exiftoolMissing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if hasSelection { cameraHeader }
                    lensPicker

                    Text(hasSelection
                         ? "Editing \(selectedCount) photo\(selectedCount == 1 ? "" : "s")"
                         : "Select photos to see their lens metadata")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(primaryFields, id: \.self) { field(for: $0) }
                    Divider().padding(.vertical, 2)
                    ForEach(secondaryFields, id: \.self) { field(for: $0) }
                }
                .padding(16)
            }

            Divider()
            applyBar
        }
        .frame(minWidth: 300, idealWidth: 340)
    }

    // MARK: - Camera (read-only)

    private var cameraHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Camera")
                .font(.caption)
                .foregroundStyle(.secondary)
            cameraValue
                .font(.headline)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor)))
    }

    @ViewBuilder
    private var cameraValue: some View {
        switch store.cameraSummary() {
        case .blank:
            Text("Unknown").foregroundStyle(.tertiary)
        case .multiple:
            Text("(multiple)").foregroundStyle(.orange)
        case .value(let v):
            Text(v)
        }
    }

    // MARK: - Lens pull-down

    private var lensPicker: some View {
        HStack {
            Menu {
                if store.lensPresets.isEmpty {
                    Text("No lenses in database").foregroundStyle(.secondary)
                } else {
                    ForEach(store.lensPresets) { preset in
                        Button(preset.displayName) { store.loadPreset(preset.metadata) }
                    }
                }
                Divider()
                Button("Clear fields") { store.clearForm() }
                Button("Choose lens CSV…") { chooseCSV() }
            } label: {
                Label(pickerLabel, systemImage: "camera.aperture")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
    }

    private var pickerLabel: String {
        if store.lensPresets.isEmpty { return "Load lens…" }
        return "Load lens (\(store.lensPresets.count))"
    }

    // MARK: - One field: current value + editable input

    private func field(for field: LensField) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasSelection { currentBadge(for: field) }
            }
            TextField(field.label, text: binding(for: field), prompt: Text(prompt(for: field)))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
    }

    // The field itself now shows the selection's shared value; only flag the
    // case where selected photos disagree (field is intentionally left blank).
    @ViewBuilder
    private func currentBadge(for field: LensField) -> some View {
        if case .multiple = store.summary(for: field) {
            Text("(multiple)").font(.caption2).foregroundStyle(.orange)
        }
    }

    // MARK: - Apply

    private var applyBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Keep original as backup (_original)", isOn: $keepBackup)
                .font(.callout)

            Button {
                attemptApply()
            } label: {
                HStack {
                    if store.isBusy { ProgressView().controlSize(.small) }
                    Text(applyLabel)
                }
                .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!canApply)
            .confirmationDialog(
                "Overwrite existing lens metadata?",
                isPresented: $showOverwriteConfirm,
                titleVisibility: .visible
            ) {
                Button("Overwrite", role: .destructive) {
                    store.apply(keepBackup: keepBackup)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Some of the selected photos already have values in the fields you're writing. Applying will replace them.")
            }
        }
        .padding(16)
    }

    private func attemptApply() {
        if store.wouldOverwrite() {
            showOverwriteConfirm = true
        } else {
            store.apply(keepBackup: keepBackup)
        }
    }

    private var applyLabel: String {
        if selectedCount == 0 { return "Select photos to tag" }
        return "Apply to \(selectedCount) photo\(selectedCount == 1 ? "" : "s")"
    }

    // MARK: - Helpers

    private func binding(for field: LensField) -> Binding<String> {
        Binding(
            get: { store.form.value(for: field) },
            set: { store.setFormField(field, $0) }
        )
    }

    private func prompt(for field: LensField) -> String {
        switch field {
        case .lens: return "e.g. Super-Takumar 55mm f/1.8"
        case .focalLength: return "e.g. 55mm"
        case .maxApertureValue: return "e.g. 1.8"
        case .focalLengthIn35mm: return "e.g. 55mm"
        case .lensMake: return "e.g. Asahi"
        case .lensModel: return "e.g. Super-Takumar 55mm f/1.8"
        case .lensSerialNumber: return "optional"
        }
    }

    private func chooseCSV() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            store.setLensCSV(url)
        }
    }
}
