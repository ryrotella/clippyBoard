import SwiftUI
import AppKit

struct ImagePreviewView: View {
    let imageData: Data
    let onClose: () -> Void
    let onCopy: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var saveError: String?
    @State private var showingSaveError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Image Preview")
                    .font(.headline)

                Spacer()

                if let nsImage = NSImage(data: imageData) {
                    Text("\(Int(nsImage.size.width)) × \(Int(nsImage.size.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
                .accessibilityLabel("Copy image")

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close preview")
            }
            .padding()

            Divider()

            // Image
            if let nsImage = NSImage(data: imageData) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Unable to load image")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Footer with zoom controls
            HStack {
                Button(action: { scale = max(0.25, scale - 0.25) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom out")
                .accessibilityHint("Current zoom: \(Int(scale * 100))%")

                Text("\(Int(scale * 100))%")
                    .font(.caption)
                    .frame(width: 50)
                    .accessibilityHidden(true)

                Button(action: { scale = min(4.0, scale + 0.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom in")
                .accessibilityHint("Current zoom: \(Int(scale * 100))%")

                Spacer()

                Button(action: { scale = 1.0 }) {
                    Text("Reset")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset zoom")

                Button(action: saveImage) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .help("Save image")
                .accessibilityLabel("Save image")
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .alert("Save Failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "An unknown error occurred while saving the image.")
        }
    }

    private func saveImage() {
        guard let nsImage = NSImage(data: imageData) else {
            saveError = "Could not decode the image data."
            showingSaveError = true
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "clipboard-image.png"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                guard let tiffData = nsImage.tiffRepresentation else {
                    throw ImageSaveError.conversionFailed("Could not create TIFF representation.")
                }
                guard let bitmap = NSBitmapImageRep(data: tiffData) else {
                    throw ImageSaveError.conversionFailed("Could not create bitmap representation.")
                }
                guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    throw ImageSaveError.conversionFailed("Could not convert to PNG format.")
                }
                try pngData.write(to: url)
            } catch {
                saveError = error.localizedDescription
                showingSaveError = true
            }
        }
    }
}

private enum ImageSaveError: LocalizedError {
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let message):
            return message
        }
    }
}
