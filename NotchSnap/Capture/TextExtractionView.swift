import SwiftUI
import AppKit

// MARK: - OCR Notification Names

extension Notification.Name {
    static let ocrCopySelected = Notification.Name("notchsnap.ocrCopySelected")
    static let ocrSelectAll = Notification.Name("notchsnap.ocrSelectAll")
}

// MARK: - TextExtractionView — Overlay for OCR text selection
//
// Reusable by both the inline capture (AreaSelector Phase 2) and the editor.
// Displays recognized text blocks as selectable blue rectangles over the image.
// Includes its own toolbar pill (Select All / Copy / Exit).

struct TextExtractionView: View {
    let image: CGImage
    let imageSize: CGSize
    let onExit: () -> Void

    @State private var state: TextExtractionState = .analyzing
    @State private var blocks: [RecognizedTextBlock] = []
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        ZStack {
            // Text block overlays
            if state == .ready {
                ForEach(blocks) { block in
                    TextBlockOverlay(
                        block: block,
                        imageSize: imageSize,
                        isSelected: selectedIDs.contains(block.id),
                        onTap: { toggleSelection(block.id) }
                    )
                }
                .transition(.opacity)
            }

            // Centered status overlays
            if state == .analyzing {
                analyzerOverlay
            }
            if state == .noText {
                noTextOverlay
            }

            // OCR toolbar at bottom of the overlay
            if state == .ready {
                VStack {
                    Spacer()
                    ocrToolbar
                        .padding(.bottom, 12)
                }
            }
        }
        .frame(width: imageSize.width, height: imageSize.height)
        // Chrome over media, like the toolbars: it lies on top of a captured
        // image of any brightness, so it supplies its own dark ground rather
        // than following the system appearance.
        .darkGroundSurface()
        .task { await runOCR() }
        .onReceive(NotificationCenter.default.publisher(for: .ocrCopySelected)) { _ in
            if state == .ready { copySelected() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ocrSelectAll)) { _ in
            if state == .ready { toggleSelectAll() }
        }
    }

    // MARK: - OCR Toolbar

    private var ocrToolbar: some View {
        HStack(spacing: 12) {
            Button(action: toggleSelectAll) {
                Text(allSelected ? "Deselect" : "Select All")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.9))

            divider

            Button(action: copySelected) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Copy")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(selectedIDs.isEmpty ? .white.opacity(0.3) : .white.opacity(0.9))
            .disabled(selectedIDs.isEmpty)

            divider

            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 1, height: 20)
    }

    private var allSelected: Bool {
        !blocks.isEmpty && selectedIDs.count == blocks.count
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(blocks.map(\.id))
        }
    }

    private func copySelected() {
        let text = blocks
            .filter { selectedIDs.contains($0.id) }
            .sorted { a, b in
                // Sort top to bottom (Vision Y is bottom-up, higher Y = higher on screen)
                if abs(a.boundingBox.origin.y - b.boundingBox.origin.y) > 0.01 {
                    return a.boundingBox.origin.y > b.boundingBox.origin.y
                }
                return a.boundingBox.origin.x < b.boundingBox.origin.x
            }
            .map(\.text)
            .joined(separator: "\n")

        guard !text.isEmpty else { return }

        // NOTE: do NOT call ClipboardMonitor.skipNextChange() here. The user
        // explicitly chose to copy this OCR text — we want it to flow through
        // the monitor and land in the clipboard history (the notch panel)
        // exactly like any other Cmd+C from another app.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        HapticManager.shared.copyConfirmed()
        onExit()
    }

    // MARK: - Status Overlays

    private var analyzerOverlay: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .progressViewStyle(.circular)
            Text("Analyzing text...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .floatingGlass(in: Capsule())
    }

    private var noTextOverlay: some View {
        Text("No text recognized")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .floatingGlass(in: Capsule())
            .task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                onExit()
            }
    }

    // MARK: - OCR

    private func runOCR() async {
        print("[OCR] Starting analysis on \(image.width)×\(image.height) image")
        do {
            let results = try await TextRecognizer.shared.analyze(image)
            print("[OCR] Found \(results.count) text blocks")
            if results.isEmpty {
                withAnimation(.easeOut(duration: 0.2)) { state = .noText }
            } else {
                blocks = results
                withAnimation(.easeOut(duration: 0.2)) { state = .ready }
            }
        } catch {
            print("[OCR] Error: \(error)")
            withAnimation(.easeOut(duration: 0.2)) { state = .error(error.localizedDescription) }
        }
    }
}
