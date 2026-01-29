import SwiftUI
import AppKit

struct ImagePreviewView: View {
    let imageData: Data
    let onClose: () -> Void
    let onCopy: () -> Void

    @State private var scale: CGFloat = 1.0

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

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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

                Text("\(Int(scale * 100))%")
                    .font(.caption)
                    .frame(width: 50)

                Button(action: { scale = min(4.0, scale + 0.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { scale = 1.0 }) {
                    Text("Reset")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button(action: saveImage) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .help("Save image")
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private func saveImage() {
        guard let nsImage = NSImage(data: imageData) else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "clipboard-image.png"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
}
