import AppKit
import Foundation

enum ScreenshotEditorFileIO {
    static func saveImageToDownloads(_ image: NSImage) throws -> URL {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"

        let baseName = "SnapX \(formatter.string(from: Date()))"
        var destinationURL = downloadsURL.appendingPathComponent(baseName).appendingPathExtension("png")
        var attempt = 1
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            destinationURL = downloadsURL
                .appendingPathComponent("\(baseName) \(attempt)")
                .appendingPathExtension("png")
            attempt += 1
        }

        guard let pngData = image.pngRepresentation else {
            throw CocoaError(.fileWriteUnknown)
        }

        try pngData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    static func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

enum RecognizedTextPresenter {
    @MainActor
    private static var windowController: RecognizedTextWindowController?

    @MainActor
    static func present(text: String, parentWindow: NSWindow?) {
        windowController?.close()

        let controller = RecognizedTextWindowController(text: text) {
            windowController = nil
        }
        windowController = controller
        controller.show(relativeTo: parentWindow)
    }
}