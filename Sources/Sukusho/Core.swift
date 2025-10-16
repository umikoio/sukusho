/*
    Author: Umiko (https://github.com/umikoio)
    Project: Sukusho (https://github.com/umikoio/sukusho)
*/

import SwiftUI
import AppKit
import Combine
import CoreGraphics
import UniformTypeIdentifiers
import Carbon
import ScreenCaptureKit

// This struct is configured and managed for each image
/// The information collected when taking a screenshot
struct ScreenshotItem: Identifiable, Equatable {
    let id = UUID() // Do not provide this, it's automatically generated
    let image: NSImage
    let capturedAt: Date
}

/// Attempt to resolve CoreGraphics permission dynamically (/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics)
private func dlsymUnsafe<T>(_ name: String) -> T? {
    guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
          let sym = dlsym(handle, name) else { return nil }

    return unsafeBitCast(sym, to: T.self)
}

/// Manage the entire screenshot logic here
final class ScreenshotManager: ObservableObject {
    // We should always show the most recent screenshot at the top
    @Published var history: [ScreenshotItem] = []

    // Allow the user to specify a directory to save the screenshot
    // Mac defaults thit to Desktop, but I usually choose my own directory, so it's here
    @Published var preferredSaveDirectory: URL?

    // We can easily increase the max number of screenshots saved in the future, but keeping at 10 for now
    private let maxItems = 10

    init() {}

    // Need to make sure we have the proper permissions to screen capture
    var isScreenRecordingPermitted: Bool {
        if let fn = dlsymUnsafe("CGPreflightScreenCaptureAccess") as Optional<@convention(c) () -> Bool> {
            return fn()
        }

        return true
    }

    /// Open the MacOS privacy panel for the user
    func openScreenRecordingPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // Moving forward, we only support MacOS 14+ (this way we can use ScreenCaptureKit and some of the benefits that come with it)
    @available(macOS 14.0, *)
    /// The core function for capturing full screen screenshots
    private func captureFullDisplayCGImage(excludingSelfWindows: Bool = true, sourceRect: CGRect? = nil) async throws -> CGImage {
        let content = try await SCShareableContent.current

        // I would be surprised if this ever happens, but if we can't find a display, we have an edge case for it
        guard let display = content.displays.first else {
            throw NSError(domain: "Sukusho", code: 1, userInfo: [NSLocalizedDescriptionKey: "No displays found"])
        }

        // We'll use the bundle identity to hide the modal window
        let myBundleID = Bundle.main.bundleIdentifier

        // Exclude our modal window (but make sure the content behind it still shows in the screenshot)
        let myWindows: [SCWindow] =
            excludingSelfWindows
            ? content.windows.filter { $0.owningApplication?.bundleIdentifier == myBundleID }
            : []

        let filter = SCContentFilter(display: display, excludingWindows: myWindows)
        let config = SCStreamConfiguration()

        // Trying to improve the image quality, but it's been varying recently
        // I'll come back to this later
        if let r = sourceRect {
            // We use a full-screen rectangle to capture the entire screen's region
            config.sourceRect = r
            // The values below designate the full screen window
            config.width  = Int(r.width.rounded(.down))
            config.height = Int(r.height.rounded(.down))
        } else {
            // Fallback
            config.width  = display.width
            config.height = display.height
        }

        config.pixelFormat = kCVPixelFormatType_32BGRA

        // Don't capture cursor
        // Maybe we add a settings window for users?
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        // Build a capture queue, with a similar label to our bundle identity
        let outputQueue = DispatchQueue(label: "com.sukusho.capture.output")

        /// Only capture a single frame from the stream output
        final class OneFrameReceiver: NSObject, SCStreamOutput {
            let finish: (Result<CGImage, Error>) -> Void
            let context: CIContext

            init(context: CIContext, finish: @escaping (Result<CGImage, Error>) -> Void) {
                self.context = context
                self.finish  = finish
            }

            /// Construct a stream buffer to read (this will only capture a single frame and stop immediately after)
            func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
                guard outputType == .screen, let pixelBuffer = sampleBuffer.imageBuffer else { return }
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

                if let cg = context.createCGImage(ciImage, from: ciImage.extent) {
                    _ = try? stream.removeStreamOutput(self, type: .screen)
                    finish(.success(cg))
                }
            }

            /// Verify stream errors
            func stream(_ stream: SCStream, didStopWithError error: Error) {
                finish(.failure(error))
            }
        }

        let ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: false,
            .cacheIntermediates: false,
            .outputColorSpace: CGColorSpaceCreateDeviceRGB(),
            .workingColorSpace: CGColorSpaceCreateDeviceRGB()
        ])

        // Running concurrency based validation
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            var receiverRef: OneFrameReceiver?

            /// Verify the stream is finished and a result was produced
            func finish(_ result: Result<CGImage, Error>) {
                guard !finished else { return }
                finished = true

                // Capture finished, stop capture and share result
                Task {
                    try? await stream.stopCapture()
                    receiverRef = nil
                    continuation.resume(with: result)
                }
            }

            let receiver = OneFrameReceiver(context: ciContext, finish: finish)
            receiverRef = receiver

            // If any issues are found during capture, we need to handle those
            do {
                try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: outputQueue)
                try stream.startCapture()
            } catch {
                finish(.failure(error))
                return
            }

            // If unable to capture the first frame, throw an error
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                if !finished {
                    finish(.failure(NSError(domain: "Sukusho", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Timed out waiting for the first captured frame"
                    ])))
                }
            }
        }
    }

    /// Perform the screenshot capture
    func captureScreen() {
        // Main task runner and history manager for the screen capture
        if #available(macOS 14.0, *) {
            Task { @MainActor in
                do {
                    let cg = try await captureFullDisplayCGImage()
                    self.pushToHistory(self.nsImage(from: cg))
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    /// Slightly improved nsImage function to manage the data being pushed to the history manager
    private func nsImage(from cg: CGImage) -> NSImage {
        let size = NSSize(width: cg.width, height: cg.height)
        return NSImage(cgImage: cg, size: size)
    }

    /// Intake all of the screenshot data for the history array
    @MainActor
    private func pushToHistory(_ nsImage: NSImage) {
        let item = ScreenshotItem(image: nsImage, capturedAt: Date())

        // New screenshot item appended
        history.insert(item, at: 0)

        // Don't go over the max number of screenshots allowed
        if history.count > maxItems {
            history.removeLast(history.count - maxItems)
        }
    }

    /// Allow the user to save the screenshot (and choose the directory to save in)
    func save(_ item: ScreenshotItem) {
        // This just configures the GUI panel for the save popup
        let panel = NSSavePanel()
        panel.title = "Save Screenshot"
        panel.allowedContentTypes = [.png] // Not sure if we can support more than PNG, may look into this later
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        // We keep a similar naming scheme to the default MacOS screenshots
        panel.nameFieldStringValue = defaultFileName(for: item)
        panel.directoryURL = preferredSaveDirectory ?? defaultPicturesDirectory()

        // Opens the the save modal when the user interacts with the `Save...` button
        presentAppModal(panel: panel) { resp in
            if resp == .OK, let url = panel.url {
                self.writePNG(item.image, to: url)
            }
        }
    }

    /// Same as the `save` function, but it doesn't have a modal popup
    func quickSave(_ item: ScreenshotItem) {
        // You can set the quick save directory within the GUI as well
        let directory = preferredSaveDirectory ?? defaultPicturesDirectory()

        // We use a directory called "Sukusho" to contain all images created by the app
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(defaultFileName(for: item))
        writePNG(item.image, to: url)
    }

    /// Set the folder where screenshots are saved when quick saved
    func chooseQuickSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        // Similar to the normal `save` modal, but a little more tailored to `quickSave`
        presentAppModal(panel: panel) { resp in
            if resp == .OK, let url = panel.url {
                self.preferredSaveDirectory = url
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    /// Remove all screenshots from the array
    func clearHistory() {
        history.removeAll()
    }

    /// Presents an NSApplication dialog panel for user interaction
    private func presentAppModal(panel: NSSavePanel, completion: (NSApplication.ModalResponse) -> Void) {
        // Capture current activation policy
        let _ = NSApp.activationPolicy()

        // Temporarily set activation policy to ".regular" so the panel is interactive
        // This way it becomes a foreground app while active
        _ = NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // The app panel should be on top of all other applications (it's only a menu bar app after all)
        panel.level = .modalPanel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        let resp = panel.runModal()

        // Restores back to ".accessory" after dismissal
        _ = NSApp.setActivationPolicy(.accessory)

        completion(resp)
    }

    /// Handles the actual file writing process (PNG, lossless, simple)
    private func writePNG(_ image: NSImage, to url: URL) {
        // CGImage seems to offer the best solution for physical images (no scaling)
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cg)
            // Should stop any DPI weirdness
            rep.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)

            // Handles the actual PNG creation
            if let png = rep.representation(using: .png, properties: [:]) {
                do {
                    try png.write(to: url)
                } catch {
                    NSAlert(error: error).runModal()
                }

                return
            }
        }

        // A quick fallback (TIFF)
        // This still forces the same aspect ratio, but may be slightly worse quality
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }

        // Force to match the exact pixel dimensions
        rep.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)

        if let png = rep.representation(using: .png, properties: [:]) {
            do {
                try png.write(to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// If no directory is specified, we'll just use Desktop like other screenshot utilities
    private func defaultPicturesDirectory() -> URL {
        let base = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Sukusho", isDirectory: true)
    }

    /// The default filename for screenshots
    private func defaultFileName(for item: ScreenshotItem) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Sukusho_Screenshot_\(fmt.string(from: item.capturedAt)).png"
    }
}

/// Handles the logic for the about window
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private override init(window: NSWindow?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "About Sukusho"
        window.isReleasedWhenClosed = false
        window.center()

        let hosting = NSHostingView(rootView: AboutView())
        hosting.frame = window.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/*
    Sukusho Views
*/

/// A separate window to show "About" information for the developer and app
struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .cornerRadius(12)

            Text("Sukusho").font(.title2).bold()
            Text("Lightweight MacOS menu bar screenshot manager. Stores the last 10 screenshots in memory; save only what you want!")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text("Version 0.1.0").font(.footnote)
                Spacer()
                Button("Close") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

/// Handles the visual values for the app
struct HistoryRow: View {
    let item: ScreenshotItem
    let onSave: (ScreenshotItem) -> Void
    let onQuickSave: (ScreenshotItem) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: item.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 90, height: 60)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(dateString(item.capturedAt)).font(.subheadline)
                HStack(spacing: 8) {
                    Button("Save") { onSave(item) }
                    Button("Quick Save") { onQuickSave(item) }
                }
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// Generate a time string next to the image (how long did it take to take the screenshot)
    private func dateString(_ date: Date) -> String {
        // Not a big fan of this, but it helps me it feel less empty
        // Need to find a better value to put here
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
