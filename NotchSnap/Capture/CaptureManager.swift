import Foundation
import AppKit
import ScreenCaptureKit

// MARK: - Capture Errors

enum CaptureError: LocalizedError {
    case noDisplay
    case captureFailed
    case permissionDenied
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found"
        case .captureFailed: return "Screenshot capture failed"
        case .permissionDenied: return "Screen recording permission not granted"
        case .cancelled: return "Capture cancelled"
        }
    }
}

// MARK: - Notification Names for Caps Lock Hotkeys

extension Notification.Name {
    static let captureAreaSilent = Notification.Name("notchsnap.captureAreaSilent")
    static let captureAreaWithEditor = Notification.Name("notchsnap.captureAreaWithEditor")
    static let openSettingsRequest = Notification.Name("notchsnap.openSettings")
    static let settingsWindowClosed = Notification.Name("notchsnap.settingsClosed")
    /// Posted whenever the global quick-entry hotkey actually fires. Onboarding
    /// listens for this so its practice step advances on the REAL keypress
    /// rather than a "Next" button — the user performs the app's core action
    /// for real before onboarding ends.
    static let quickEntryFired = Notification.Name("otto.quickEntryFired")
}

// MARK: - CaptureManager

@MainActor
class CaptureManager: ObservableObject {
    static let shared = CaptureManager()

    @Published var isCapturing: Bool = false
    private var areaSelectorWindow: AreaSelectorWindow?

    // MARK: - Pre-cached shareable content (eliminates 1-3s startup delay)
    private var cachedContent: SCShareableContent?
    private var contentCacheTime: Date = .distantPast
    private let contentCacheTTL: TimeInterval = 5  // refresh every 5 seconds
    private var prefetchTask: Task<Void, Never>?

    /// Whether we've confirmed screen recording permission at least once
    private var permissionConfirmed = false

    /// Call on app launch to warm the cache — only starts refreshing if permission is granted
    func warmContentCache() {
        // On a fresh install, calling ScreenCaptureKit without permission makes
        // macOS throw its own permission dialog at launch — stepping on the
        // onboarding flow. Check passively first; onboarding owns the ask.
        guard CGPreflightScreenCaptureAccess() else {
            print("[CaptureManager] No screen recording permission yet — skipping cache warm")
            return
        }
        prefetchTask = Task.detached(priority: .userInitiated) {
            // Single attempt — if it fails, permission isn't granted yet
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            await MainActor.run {
                if content != nil && !(content?.displays.isEmpty ?? true) {
                    self.cachedContent = content
                    self.contentCacheTime = Date()
                    self.permissionConfirmed = true
                    // Only start periodic refresh AFTER confirming permission
                    self.startPeriodicRefresh()
                }
            }
        }
    }

    private func startPeriodicRefresh() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(contentCacheTTL) * 1_000_000_000)
                guard permissionConfirmed else { continue }
                let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                self.cachedContent = content
                self.contentCacheTime = Date()
            }
        }
    }

    /// Get cached content or fetch fresh if stale
    private func getCachedContent() async throws -> SCShareableContent {
        if Date().timeIntervalSince(contentCacheTime) < contentCacheTTL, let cached = cachedContent {
            return cached
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            cachedContent = content
            contentCacheTime = Date()
            permissionConfirmed = true
            return content
        } catch {
            print("[CaptureManager] Screen Recording permission not granted — cannot fetch content")
            throw CaptureError.permissionDenied
        }
    }

    /// PF-3/PF-4: downscale captures whose longest edge exceeds ~2500px.
    /// Set the hidden default `keepLosslessCaptures` to true to keep
    /// pixel-perfect originals (at the documented memory/storage cost).
    static func downscaledIfNeeded(_ image: CGImage, maxEdge: CGFloat = 2500) -> CGImage {
        guard !UserDefaults.standard.bool(forKey: "keepLosslessCaptures") else { return image }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let longest = max(w, h)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let tw = Int(w * scale), th = Int(h * scale)
        guard let ctx = CGContext(
            data: nil, width: tw, height: th,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage() ?? image
    }

    /// Radius for the rounded-corner output option: proportional to the
    /// capture (in pixels, so Retina scale is handled), clamped so tiny
    /// crops don't become pills and huge grabs don't look barely-rounded.
    static func roundedCornerRadius(for image: CGImage) -> CGFloat {
        let minDim = CGFloat(min(image.width, image.height))
        return min(48, max(16, minDim * 0.035))
    }

    func setupHotkeyObservers() {
        NotificationCenter.default.addObserver(
            forName: .captureAreaSilent,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.startCapture(mode: .area, openEditorAfter: false, silentCopy: true)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .captureAreaWithEditor,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.startInlineCapture()
            }
        }
    }

    func startCapture(mode: CaptureMode) async {
        await startCapture(mode: mode, openEditorAfter: false, silentCopy: false)
    }

    func startCapture(mode: CaptureMode, openEditorAfter: Bool, silentCopy: Bool) async {
        guard !isCapturing else {
            print("[CaptureManager] Already capturing — skipping")
            return
        }

        isCapturing = true
        AppState.shared.lastCaptureMode = mode
        print("[CaptureManager] Starting capture mode=\(mode)")

        defer { isCapturing = false }

        do {
            var image: CGImage
            switch mode {
            case .area:
                image = try await captureArea()
            case .window:
                image = try await captureWindow()
            case .fullscreen:
                image = try await captureFullscreen()
            }

            // PF-3: cap stored resolution. Nobody views a 6000px capture
            // inside a notch panel; full-res costs ~150MB RAM each and
            // multi-MB files. Hidden escape hatch: `keepLosslessCaptures`.
            image = Self.downscaledIfNeeded(image)

            // Optional rounded corners for area captures (toolbar toggle).
            if mode == .area, UserDefaults.standard.bool(forKey: "captureRoundedCorners") {
                let radius = Self.roundedCornerRadius(for: image)
                image = ImageRoundedCornerMask.apply(to: image, cornerRadius: radius) ?? image
            }

            print("[CaptureManager] Capture succeeded: \(image.width)x\(image.height)")
            let item = ScreenshotItem(originalImage: image)
            AppState.shared.addScreenshot(item)

            // Silent copy: copy immediately to clipboard without opening editor
            if silentCopy {
                AppState.shared.copyToClipboard(item)
            }

            // Open editor immediately after capture
            if openEditorAfter {
                // Editor flow: the editor IS the preview — no corner thumbnail.
                EditorWindowController.shared.open(item: item)
            } else {
                // Quick-capture flow: Dynamic Island pill confirms the shot;
                // the screenshot lives in the notch's Shots section for
                // drag-out and management. (The in-notch tray is reserved
                // for files the user drags in.)
                NotchController.shared.showNewScreenshot()
            }

        } catch CaptureError.cancelled {
            print("[CaptureManager] Capture cancelled by user")
        } catch CaptureError.permissionDenied {
            print("[CaptureManager] Permission denied — showing grant dialog")
            showPermissionAlert()
        } catch {
            print("[CaptureManager] Error: \(error.localizedDescription)")
        }
    }

    /// Permission missing at capture time: don't fail silently — explain and
    /// route into the grant flow (register with TCC + open the exact pane).
    private func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "Otto can't take screenshots until you allow Screen Recording in System Settings. If you just granted it, relaunch Otto for it to take effect."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Relaunch Otto")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Registers the app in the Screen Recording list (first time)
            // and lands the user on the right pane.
            CGRequestScreenCaptureAccess()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            PermissionManager.relaunchApp()
        default:
            break
        }
    }

    // MARK: - Area Capture

    private func captureArea() async throws -> CGImage {
        let rect = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGRect, Error>) in
            let selector = AreaSelectorWindow { selectedRect in
                if let rect = selectedRect {
                    continuation.resume(returning: rect)
                } else {
                    continuation.resume(throwing: CaptureError.cancelled)
                }
            }
            self.areaSelectorWindow = selector
            selector.show()
        }
        areaSelectorWindow = nil

        // Wait for the selector overlay to fully disappear before capturing
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        return try await captureRect(rect)
    }

    // MARK: - Inline Area Capture (edit-before-capture flow)

    func startInlineCapture() async {
        guard !isCapturing else {
            print("[CaptureManager] Already capturing — skipping")
            return
        }

        isCapturing = true
        AppState.shared.lastCaptureMode = .area
        print("[CaptureManager] Starting inline capture (edit-before-capture)")

        defer { isCapturing = false }

        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(CGRect, [AnnotationModel], CaptureAction, Bool), Error>) in
                let selector = AreaSelectorWindow { rect, annotations, action, isWindowSnap in
                    if let rect = rect, action != .cancel {
                        continuation.resume(returning: (rect, annotations, action, isWindowSnap))
                    } else {
                        continuation.resume(throwing: CaptureError.cancelled)
                    }
                }
                self.areaSelectorWindow = selector
                selector.show()
            }
            areaSelectorWindow = nil

            let (rect, annotations, action, isWindowSnap) = result

            // Wait for overlay to disappear
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Capture the selected rect
            var rawImage = try await captureRect(rect)
            print("[CaptureManager] Inline capture succeeded: \(rawImage.width)x\(rawImage.height)")

            // Window-snap: mask the image to match the window's rounded corners
            // (standard macOS window radius is ~10pt).
            if isWindowSnap {
                let scale = CGFloat(rawImage.width) / max(rect.width, 1)
                rawImage = ImageRoundedCornerMask.apply(to: rawImage, cornerRadius: 10 * scale) ?? rawImage
            }

            // PF-3: same resolution ceiling as the quick-capture path.
            rawImage = Self.downscaledIfNeeded(rawImage)

            // Optional rounded corners (toolbar toggle) — window snaps already
            // carry the window's own radius, so don't double-round those.
            if !isWindowSnap, UserDefaults.standard.bool(forKey: "captureRoundedCorners") {
                let radius = Self.roundedCornerRadius(for: rawImage)
                rawImage = ImageRoundedCornerMask.apply(to: rawImage, cornerRadius: radius) ?? rawImage
            }

            // Composite annotations onto the captured image
            let finalImage: CGImage
            if annotations.isEmpty {
                finalImage = rawImage
            } else {
                // Convert screen-space annotations to image-space
                let canvas = InlineAnnotationCanvas(frame: .zero)
                canvas.annotations = annotations
                canvas.clipRect = CGRect(origin: .zero, size: CGSize(width: rect.width, height: rect.height))
                let imageAnnotations = canvas.convertToImageSpace(
                    imageWidth: rawImage.width, imageHeight: rawImage.height
                )
                finalImage = compositeAnnotations(imageAnnotations, onto: rawImage)
            }

            let item = ScreenshotItem(originalImage: finalImage, annotations: [])
            AppState.shared.addScreenshot(item)

            switch action {
            case .copy:
                AppState.shared.copyToClipboard(item)
            case .save:
                try? AppState.shared.saveToFile(item)
            case .cancel:
                break
            }

            // Inline-edit flow: the user already copied/saved via the action
            // bar — no corner preview or notch announcement needed. The item
            // is in the notch gallery for later management.

        } catch CaptureError.cancelled {
            print("[CaptureManager] Inline capture cancelled by user")
        } catch {
            print("[CaptureManager] Inline capture error: \(error.localizedDescription)")
        }
    }

    /// Composite annotations onto a CGImage, returning a new CGImage
    private func compositeAnnotations(_ annotations: [AnnotationModel], onto image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        let size = NSSize(width: width, height: height)

        let nsImage = NSImage(size: size)
        nsImage.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            nsImage.unlockFocus()
            return image
        }

        // Draw original image
        ctx.draw(image, in: CGRect(origin: .zero, size: size))

        // Draw each annotation (reuse ScreenshotItem rendering logic)
        for annotation in annotations {
            renderAnnotationOnContext(annotation, in: ctx, size: size)
        }

        nsImage.unlockFocus()

        // Convert back to CGImage
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else {
            return image
        }
        return cgImage
    }

    /// Render a single annotation onto a CGContext (same logic as ScreenshotItem)
    private func renderAnnotationOnContext(_ annotation: AnnotationModel, in ctx: CGContext, size: NSSize) {
        switch annotation.tool {
        case .pen(let color, let width, let points):
            guard points.count >= 2 else { return }
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(DrawingEngine.smoothedPath(from: points))
            ctx.strokePath()

        case .text(let content, let color, let fontSize, let origin):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: color
            ]
            let str = NSAttributedString(string: content, attributes: attrs)
            let textSize = str.size()
            let pillRect = CGRect(x: origin.x - 4, y: origin.y - 2,
                                  width: textSize.width + 8, height: textSize.height + 4)
            ctx.setFillColor(color.withAlphaComponent(0.2).cgColor)
            ctx.addPath(CGPath(roundedRect: pillRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.fillPath()
            str.draw(at: origin)

        case .blur(let rect):
            guard let cropped = ctx.makeImage()?.cropping(to: rect) else { return }
            let ciImage = CIImage(cgImage: cropped)
            let filter = CIFilter(name: "CIPixellate")!
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(20.0, forKey: kCIInputScaleKey)
            guard let output = filter.outputImage else { return }
            let ciCtx = CIContext()
            guard let blurred = ciCtx.createCGImage(output, from: output.extent) else { return }
            ctx.draw(blurred, in: rect)

        case .arrow(let from, let to, let color, let width):
            ctx.setStrokeColor(color.cgColor)
            ctx.setFillColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()

            let angle = atan2(to.y - from.y, to.x - from.x)
            let headLength = width * 4
            let headAngle: CGFloat = .pi / 6
            let p1 = CGPoint(x: to.x - headLength * cos(angle - headAngle),
                             y: to.y - headLength * sin(angle - headAngle))
            let p2 = CGPoint(x: to.x - headLength * cos(angle + headAngle),
                             y: to.y - headLength * sin(angle + headAngle))
            ctx.move(to: to)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.closePath()
            ctx.fillPath()

        case .rectangle(let rect, let color, let width):
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.stroke(rect)
        }
    }

    // MARK: - Window Capture

    private func captureWindow() async throws -> CGImage {
        let content = try await getCachedContent()

        guard let window = content.windows.first(where: {
            $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier &&
            $0.isOnScreen && $0.frame.width > 100 && $0.frame.height > 100
        }) else {
            throw CaptureError.noDisplay
        }

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, including: [window])
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * (NSScreen.main?.backingScaleFactor ?? 2))
        config.height = Int(window.frame.height * (NSScreen.main?.backingScaleFactor ?? 2))
        config.capturesAudio = false
        config.showsCursor = false

        return try await captureWithFilter(filter, configuration: config)
    }

    // MARK: - Fullscreen Capture

    private func captureFullscreen() async throws -> CGImage {
        let content = try await getCachedContent()
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.capturesAudio = false
        config.showsCursor = false

        return try await captureWithFilter(filter, configuration: config)
    }

    // MARK: - Helper: capture specific rect

    private func captureRect(_ rect: CGRect) async throws -> CGImage {
        let content = try await getCachedContent()
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        config.sourceRect = rect
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.capturesAudio = false
        config.showsCursor = false

        return try await captureWithFilter(filter, configuration: config)
    }

    // MARK: - Capture Implementation

    private func captureWithFilter(_ filter: sending SCContentFilter, configuration: sending SCStreamConfiguration) async throws -> CGImage {
        // Hide cursor before capture — showsCursor=false may not work on all macOS versions
        NSCursor.hide()
        defer { NSCursor.unhide() }

        // Brief pause to ensure cursor is hidden before the frame is grabbed
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        if #available(macOS 14.0, *) {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } else {
            return try await captureViaStream(filter: filter, configuration: configuration)
        }
    }

    /// Fallback for macOS 13: use SCStream to capture a single frame
    private func captureViaStream(filter: sending SCContentFilter, configuration: sending SCStreamConfiguration) async throws -> CGImage {
        return try await withCheckedThrowingContinuation { continuation in
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

            let handler = StreamOutputHandler(continuation: continuation, stream: stream)

            do {
                try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: .global())
                stream.startCapture { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Stream Output Handler (for macOS 13 fallback)

private final class StreamOutputHandler: NSObject, SCStreamOutput, @unchecked Sendable {
    private var continuation: CheckedContinuation<CGImage, Error>?
    private let stream: SCStream

    init(continuation: CheckedContinuation<CGImage, Error>, stream: SCStream) {
        self.continuation = continuation
        self.stream = stream
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = sampleBuffer.imageBuffer
        else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            continuation?.resume(throwing: CaptureError.captureFailed)
            continuation = nil
            return
        }

        continuation?.resume(returning: cgImage)
        continuation = nil

        stream.stopCapture { _ in }
    }
}

// MARK: - Rounded-corner mask for window-snap captures

enum ImageRoundedCornerMask {
    /// Returns a new CGImage where pixels outside a rounded-rect path (radius in pixels)
    /// are transparent. Used so window-snap screenshots preserve the window's corner radius
    /// instead of showing the desktop behind the corners.
    static func apply(to image: CGImage, cornerRadius: CGFloat) -> CGImage? {
        let w = image.width
        let h = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}
