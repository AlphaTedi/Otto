import SwiftUI
import AppKit

// MARK: - Editor State

@MainActor
class EditorState: ObservableObject {
    let item: ScreenshotItem

    @Published var currentTool: AnnotationToolType = .pen
    @Published var currentColor: NSColor = NSColor(red: 1, green: 0.23, blue: 0.19, alpha: 1) // Red
    @Published var brushWidth: CGFloat = 6
    @Published var fontSize: CGFloat = 18
    @Published var annotations: [AnnotationModel] = []
    @Published var redoStack: [AnnotationModel] = []
    @Published var showCopyFeedback: Bool = false
    @Published var hasBeenCopiedOrSaved: Bool = false
    @Published var isOCRMode: Bool = false

    let maxUndoLevels = 30

    init(item: ScreenshotItem) {
        self.item = item
        self.annotations = item.annotations
    }

    func addAnnotation(_ annotation: AnnotationModel) {
        annotations.append(annotation)
        redoStack.removeAll()

        // Trim undo stack
        if annotations.count > maxUndoLevels {
            annotations.removeFirst(annotations.count - maxUndoLevels)
        }

        // Update the item in AppState
        updateItem()
    }

    func undo() {
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
        updateItem()
    }

    func redo() {
        guard let last = redoStack.popLast() else { return }
        annotations.append(last)
        updateItem()
    }

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func updateItem() {
        if let index = AppState.shared.screenshots.firstIndex(where: { $0.id == item.id }) {
            AppState.shared.screenshots[index].annotations = annotations
        }
    }

    func copyToClipboard() {
        if let index = AppState.shared.screenshots.firstIndex(where: { $0.id == item.id }) {
            AppState.shared.copyToClipboard(AppState.shared.screenshots[index])
            hasBeenCopiedOrSaved = true
            showCopyFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showCopyFeedback = false
            }
        }
    }

    func saveToFile() {
        if let index = AppState.shared.screenshots.firstIndex(where: { $0.id == item.id }) {
            try? AppState.shared.saveToFile(AppState.shared.screenshots[index])
            hasBeenCopiedOrSaved = true
        }
    }
}

// MARK: - Editor View — Canvas + floating toolbar + action bar

struct EditorView: View {
    @ObservedObject var editorState: EditorState
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Canvas — fills available space
            GeometryReader { geo in
                ZStack {
                    AnnotationCanvasView(editorState: editorState)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    // OCR overlay — positioned over the image area (includes its own toolbar)
                    if editorState.isOCRMode {
                        let imgSize = fittedImageSize(in: geo.size)
                        TextExtractionView(
                            image: editorState.item.originalImage,
                            imageSize: imgSize,
                            onExit: { editorState.isOCRMode = false }
                        )
                        .frame(width: imgSize.width, height: imgSize.height)
                        .allowsHitTesting(true)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 80) // space for the unified toolbar

            // Unified floating toolbar — same pill used by inline capture.
            // Hidden during OCR mode (TextExtractionView has its own toolbar).
            if !editorState.isOCRMode {
                AnnotationToolbar(
                    activeTool: $editorState.currentTool,
                    activeColor: $editorState.currentColor,
                    brushSize: $editorState.brushWidth,
                    canUndo: editorState.canUndo,
                    canRedo: editorState.canRedo,
                    onUndo: { editorState.undo() },
                    onRedo: { editorState.redo() },
                    onOCR:  { editorState.isOCRMode = true },
                    onCancel: { handleClose() },
                    onCopy:   { editorState.copyToClipboard() },
                    onSave:   { editorState.saveToFile() }
                )
                .padding(.bottom, 16)
            }

            // Copy feedback flash
            if editorState.showCopyFeedback {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green.opacity(0.2))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        // Fast in, gentle out — the flash appears instantly but dissolves
        // softly instead of cutting off.
        .animation(
            editorState.showCopyFeedback
                ? .spring(duration: 0.15, bounce: 0.0)
                : .spring(duration: 0.4, bounce: 0.0),
            value: editorState.showCopyFeedback
        )
        .background(KeyEventHandler(editorState: editorState, onClose: { handleClose() }))
    }

    /// Compute the displayed image size within the canvas area (matching AnnotationCanvasNSView.imageRectInView)
    private func fittedImageSize(in canvasSize: CGSize) -> CGSize {
        let imgW = CGFloat(editorState.item.originalImage.width)
        let imgH = CGFloat(editorState.item.originalImage.height)
        let scale = min(canvasSize.width / imgW, canvasSize.height / imgH)
        return CGSize(width: imgW * scale, height: imgH * scale)
    }

    private func handleClose() {
        guard !editorState.annotations.isEmpty && !editorState.hasBeenCopiedOrSaved else {
            onClose()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Copy the screenshot before closing?"
        alert.addButton(withTitle: "Copy and Close")
        alert.addButton(withTitle: "Close Without Copying")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            editorState.copyToClipboard()
            onClose()
        case .alertSecondButtonReturn:
            onClose()
        default:
            break
        }
    }
}

// EditorActionBar removed — actions are now embedded in the unified AnnotationToolbar.

// MARK: - Key Event Handler (for keyboard shortcuts in editor)

struct KeyEventHandler: NSViewRepresentable {
    let editorState: EditorState
    let onClose: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyDown = { event in
            handleKeyDown(event)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {}

    private func handleKeyDown(_ event: NSEvent) {
        let hasCmd = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case 35: // P
            if !hasCmd { editorState.currentTool = .pen }
        case 17: // T
            if !hasCmd { editorState.currentTool = .text }
        case 11: // B
            if !hasCmd { editorState.currentTool = .blur }
        case 0: // A
            if hasCmd && editorState.isOCRMode {
                NotificationCenter.default.post(name: .ocrSelectAll, object: nil)
            } else if !hasCmd {
                editorState.currentTool = .arrow
            }
        case 15: // R
            if !hasCmd { editorState.currentTool = .rectangle }
        case 7: // X
            if !hasCmd { editorState.isOCRMode.toggle() }
        case 6: // Z
            if hasCmd && hasShift { editorState.redo() }
            else if hasCmd { editorState.undo() }
        case 8: // C
            if hasCmd {
                if editorState.isOCRMode {
                    NotificationCenter.default.post(name: .ocrCopySelected, object: nil)
                } else {
                    editorState.copyToClipboard()
                }
            }
        case 1: // S
            if hasCmd && hasShift {
                // Share
            } else if hasCmd {
                editorState.saveToFile()
            }
        case 33: // [
            editorState.brushWidth = max(2, editorState.brushWidth - 2)
        case 30: // ]
            editorState.brushWidth = min(20, editorState.brushWidth + 2)
        case 18...23: // 1-6 for color shortcuts (matching AnnotationToolbar palette)
            let index = Int(event.keyCode) - 18
            if index >= 0 && index < AnnotationToolbar.paletteColors.count {
                editorState.currentColor = AnnotationToolbar.paletteColors[index]
            }
        default:
            break
        }
    }
}

class KeyCaptureView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}
