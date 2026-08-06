import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Export Manager

@MainActor
class ExportManager {
    static let shared = ExportManager()

    // MARK: - Copy to Clipboard

    func copyToClipboard(_ item: ScreenshotItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        // Write as PNG data
        if let data = item.flattenedPNGData {
            pb.setData(data, forType: .png)
        }

        // Also write as NSImage
        pb.writeObjects([item.flattenedImage])
    }

    // MARK: - Save to File

    func saveToFile(_ item: ScreenshotItem, askLocation: Bool = false) throws -> URL {
        let settings = AppState.shared.settings

        if askLocation {
            return try saveWithDialog(item)
        } else {
            return try saveToDefaultLocation(item)
        }
    }

    private func saveToDefaultLocation(_ item: ScreenshotItem) throws -> URL {
        let settings = AppState.shared.settings
        let dir = settings.saveDirectory

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        let timestamp = formatter.string(from: item.capturedAt)
        let ext = settings.fileFormat == .png ? "png" : "jpg"
        let filename = "Otto-\(timestamp).\(ext)"
        let fileURL = dir.appendingPathComponent(filename)

        let data = try imageData(for: item, format: settings.fileFormat, quality: settings.jpegQuality)
        try data.write(to: fileURL)

        return fileURL
    }

    private func saveWithDialog(_ item: ScreenshotItem) throws -> URL {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = defaultFilename(for: item)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            throw CaptureError.cancelled
        }

        let format: FileFormat = url.pathExtension.lowercased() == "jpg" ? .jpeg : .png
        let data = try imageData(for: item, format: format, quality: AppState.shared.settings.jpegQuality)
        try data.write(to: url)

        return url
    }

    // MARK: - Share

    func share(_ item: ScreenshotItem, from view: NSView) {
        let image = item.flattenedImage
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    // MARK: - Helpers

    private func imageData(for item: ScreenshotItem, format: FileFormat, quality: Double) throws -> Data {
        let image = item.flattenedImage
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else {
            throw NSError(domain: "NotchSnap", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image data"])
        }

        let data: Data?
        switch format {
        case .png:
            data = bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }

        guard let result = data else {
            throw NSError(domain: "NotchSnap", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }
        return result
    }

    private func defaultFilename(for item: ScreenshotItem) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        let timestamp = formatter.string(from: item.capturedAt)
        return "Otto-\(timestamp).png"
    }
}
