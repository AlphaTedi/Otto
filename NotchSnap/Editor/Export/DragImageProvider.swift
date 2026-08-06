import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Drag Image Provider — Multi-format NSItemProvider for drag-and-drop

class DragImageProvider {

    /// Create an NSItemProvider for a screenshot item (used in drag-and-drop)
    /// Registers PNG, TIFF, generic image, and fileURL for maximum compatibility
    static func provider(for item: ScreenshotItem) -> NSItemProvider {
        let provider = NSItemProvider()

        // 1. PNG — for Figma, Sketch, graphic apps, browsers
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(item.flattenedPNGData, nil)
            return nil
        }

        // 2. TIFF — for native macOS text fields, Notes, TextEdit
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.tiff.identifier,
            visibility: .all
        ) { completion in
            completion(item.flattenedImage.tiffRepresentation, nil)
            return nil
        }

        // 3. Generic image type — fallback for apps that request UTType.image
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.image.identifier,
            visibility: .all
        ) { completion in
            completion(item.flattenedImage.tiffRepresentation, nil)
            return nil
        }

        // 4. File URL — for Finder, desktop, apps that prefer file drops
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { completion in
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("Otto-\(item.id.uuidString).png")

            if let data = item.flattenedPNGData {
                try? data.write(to: tempURL)
                completion(tempURL.dataRepresentation, nil)
            } else {
                completion(nil, NSError(domain: "NotchSnap", code: 1, userInfo: nil))
            }
            return nil
        }

        return provider
    }
}
