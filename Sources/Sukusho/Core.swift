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

// This struct is configured and managed for each image
/// The information collected when taking a screenshot
struct ScreenshotItem: Identifiable, Equatable {
    let id = UUID() // Do not provide this, it's automatically generated
    let image: NSImage
    let capturedAt: Date
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

    /// If permissions aren't met, we need to request them
    func requestScreenRecordingPermission() {
        if let fn = dlsymUnsafe("CGRequestScreenCaptureAccess") as Optional<@convention(c) () -> Bool> {
            _ = fn()
        }
    }

    /// Open the MacOS privacy panel for the user
    func openScreenRecordingPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Perform the screenshot capture
    func captureScreen() {
        // A guard to protect from capturing a screenshot without proper permissions
        guard isScreenRecordingPermitted else {
            requestScreenRecordingPermission()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.openScreenRecordingPrefs()
            }

            return
        }

        let rect = CGRect.infinite

        // TODO: Replace with ScreenCaptureKit on macOS 14+
        let imageRef = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution, .boundsIgnoreFraming])

        // Handles the image reference, size, and assigns the appropiate data type for ScreenshotItem
        guard let cg = imageRef else { return }
        let size = NSSize(width: cg.width, height: cg.height)
        let nsImage = NSImage(cgImage: cg, size: size)

        // Intake all of the screenshot data for the history array
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

        // We use a directory called "Sekusho" to contain all images created by the app
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

    /// Handles the actual file writing process (since it's only PNG, it's pretty simple)
    private func writePNG(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: url)
        } catch {
            NSAlert(error: error).runModal()
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

/// Attempt to resolve CoreGraphics permission dynamically (/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics)
private func dlsymUnsafe<T>(_ name: String) -> T? {
    guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
          let sym = dlsym(handle, name) else { return nil }

    return unsafeBitCast(sym, to: T.self)
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
                .frame(width: 90, height: 56)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(dateString(item.capturedAt)).font(.subheadline)
                HStack(spacing: 8) {
                    Button("Save…") { onSave(item) }
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
