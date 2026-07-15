import AppKit
import F2QuickNoteCore
import UniformTypeIdentifiers

/// Reads the pasteboard, builds the note, and drives Apple Notes.
enum NoteCapture {
    static let freshnessWindow: TimeInterval = 60

    struct Payload {
        var text: String?
        var attachmentPaths: [String] = []
    }

    /// Decides what to put in the note from the current pasteboard state.
    /// Priority: files → image → text (Finder copies also carry an icon
    /// image and a filename string, so files must win over image).
    static func readPasteboard(_ pb: NSPasteboard = .general) -> Payload {
        var payload = Payload()

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            payload.attachmentPaths = urls.map(\.path)
            payload.text = urls.map(\.lastPathComponent).joined(separator: "\n")
            return payload
        }

        if let imagePath = savePasteboardImage(pb) {
            payload.attachmentPaths = [imagePath]
            payload.text = pb.string(forType: .string)
            return payload
        }

        payload.text = pb.string(forType: .string)
        return payload
    }

    /// Writes a pasteboard image (screenshot etc.) to a temp PNG for
    /// attaching. Returns nil when there is no image.
    private static func savePasteboardImage(_ pb: NSPasteboard) -> String? {
        let pngData: Data?
        if let data = pb.data(forType: .png) {
            pngData = data
        } else if let tiff = pb.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff) {
            pngData = rep.representation(using: .png, properties: [:])
        } else {
            pngData = nil
        }
        guard let pngData else { return nil }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("F2QuickNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("clipboard-\(fmt.string(from: Date())).png")
        do {
            try pngData.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }

    enum CaptureError: Error {
        case appleScript(message: String, code: Int)
    }

    /// Creates the note (empty when the clipboard is stale) and shows it.
    static func capture(fresh: Bool) throws {
        let payload = fresh ? readPasteboard() : Payload()
        let body = NoteBuilder.bodyHTML(text: payload.text)
        let source = NoteBuilder.script(bodyHTML: body,
                                        attachmentPaths: payload.attachmentPaths)
        try runAppleScript(source)
    }

    private static func runAppleScript(_ source: String) throws {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw CaptureError.appleScript(message: "Could not compile AppleScript", code: -1)
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            throw CaptureError.appleScript(message: message, code: code)
        }
    }
}
