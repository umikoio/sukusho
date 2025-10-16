/*
    Author: Umiko (https://github.com/umikoio)
    Project: Sukusho (https://github.com/umikoio/sukusho)
*/

import SwiftUI
import AppKit

/// Double-check that we have screen recording permissions before launching
final class AppDelegate: NSObject, NSApplicationDelegate {
    var manager: ScreenshotManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let manager = self.manager else { return }
            if !manager.isScreenRecordingPermitted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    manager.openScreenRecordingPrefs()
                }
            }
        }
    }
}

@main
struct SukushoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager: ScreenshotManager

    init() {
        let m = ScreenshotManager()
        _manager = StateObject(wrappedValue: m)
        appDelegate.manager = m
    }

    var body: some Scene {
        MenuBarExtra("Sukusho", systemImage: manager.isScreenRecordingPermitted ? "camera" : "camera.slash") {
            VStack(alignment: .leading, spacing: 10) {

                HStack {
                    // Capture screenshot button
                    Button {
                        manager.captureScreen()
                    } label: {
                        Label("Capture Screen", systemImage: "camera.circle")
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    // Right under the "Capture Screen" button is a nice spot:
                    Button {
                        manager.quickLookLatest()
                    } label: {
                        Label("Quick Look Last", systemImage: "eye")
                    }
                }


                // This shouldn't happen, but if permissions still aren't granted, we have a fallback
                if !manager.isScreenRecordingPermitted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Screen Recording permission required").font(.callout)
                        HStack {
                            Button("Open Settings") { manager.openScreenRecordingPrefs() }
                            Button("Retry") { manager.captureScreen() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .cornerRadius(10)
                }

                Divider()

                // Set the "Quick Save" folder
                HStack {
                    Text("Quick Save Folder:")
                    Spacer()
                    Button(manager.preferredSaveDirectory?.lastPathComponent ?? "Set…") {
                        manager.chooseQuickSaveFolder()
                    }
                }

                Divider()

                // Handles the content to preview depending on if any screenshots exist or not
                if manager.history.isEmpty {
                    ContentUnavailableView(
                        "No screenshots yet",
                        systemImage: "rectangle.dashed",
                        description: Text("Click \"Capture Screen\" to start")
                    )
                    .frame(width: 300)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(manager.history) { item in
                                HistoryRow(
                                    item: item,
                                    onSave: manager.save,
                                    onQuickSave: manager.quickSave,
                                    onQuickLook: manager.quickLook
                                )
                                Divider()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(width: 300, height: 200)

                    // Callback to clear all screenshots from memory
                    HStack {
                        Spacer()
                        Button("Clear History") {
                            manager.clearHistory()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                HStack {
                    // Learn more about this wonderful program
                    Button("About Sukusho") {
                        AboutWindowController.shared.show()
                    }
                    .buttonStyle(.bordered)

                    // Quit application
                    Button("Quit Sukusho") {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Capture Screen") {
                    manager.captureScreen()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .appTermination) {
                Button("Quit Sukusho") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
