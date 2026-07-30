import AppKit
import F2QuickNoteCore
import UniformTypeIdentifiers

/// Reads the pasteboard, builds the note, and drives Apple Notes.
enum NoteCapture {
    static let freshnessWindow: TimeInterval = 60
    private static let temporaryBaseDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("F2QuickNote", isDirectory: true)

    struct Payload {
        var text: String?
        var attachmentURLs: [URL] = []
        var securityScopedURLs: [URL] = []
        var temporaryDirectories: [URL] = []

        var hasContent: Bool {
            !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                || !attachmentURLs.isEmpty
        }

        mutating func cleanUpTemporaryFiles() {
            for directory in temporaryDirectories {
                try? FileManager.default.removeItem(at: directory)
            }
            for url in securityScopedURLs {
                url.stopAccessingSecurityScopedResource()
            }
            temporaryDirectories.removeAll()
            securityScopedURLs.removeAll()
        }
    }

    /// Decides what to put in the note from the current pasteboard state.
    /// Priority: files → image → text (Finder copies also carry an icon
    /// image and a filename string, so files must win over image).
    static func readPasteboard(_ pb: NSPasteboard = .general) throws -> Payload {
        var payload = Payload()

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            let validated = try validateFileAttachments(urls)
            payload.attachmentURLs = validated.files
            payload.securityScopedURLs = validated.securityScoped
            payload.text = payload.attachmentURLs.map(\.lastPathComponent).joined(separator: "\n")
            return payload
        }

        if let image = try savePasteboardImage(pb) {
            payload.attachmentURLs = [image.file]
            payload.temporaryDirectories = [image.directory]
            payload.text = pb.string(forType: .string)
            guard ClipboardPolicy.acceptsText(payload.text) else {
                payload.cleanUpTemporaryFiles()
                throw CaptureError.contentTooLarge
            }
            return payload
        }

        payload.text = pb.string(forType: .string)
        guard ClipboardPolicy.acceptsText(payload.text) else {
            throw CaptureError.contentTooLarge
        }
        return payload
    }

    private static func validateFileAttachments(_ urls: [URL]) throws -> (files: [URL], securityScoped: [URL]) {
        guard urls.count <= ClipboardPolicy.maximumAttachmentCount else {
            throw CaptureError.contentTooLarge
        }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ]
        var accepted: [URL] = []
        var securityScoped: [URL] = []
        var sizes: [Int] = []
        do {
            for original in urls {
                let url = original.standardizedFileURL
                guard url.isFileURL, url.path.lengthOfBytes(using: .utf8) <= 4096 else {
                    throw CaptureError.unsafeAttachment
                }
                if url.startAccessingSecurityScopedResource() {
                    securityScoped.append(url)
                }
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      let size = values.fileSize else {
                    throw CaptureError.unsafeAttachment
                }
                accepted.append(url)
                sizes.append(size)
            }
            guard ClipboardPolicy.acceptsAttachments(sizes: sizes) else {
                throw CaptureError.contentTooLarge
            }
            return (accepted, securityScoped)
        } catch {
            for url in securityScoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// Writes a pasteboard image (screenshot etc.) to a temp PNG for
    /// attaching. Returns nil when there is no image.
    private static func savePasteboardImage(_ pb: NSPasteboard) throws -> (file: URL, directory: URL)? {
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
        guard pngData.count <= ClipboardPolicy.maximumImageBytes else {
            throw CaptureError.contentTooLarge
        }

        let dir: URL
        do {
            dir = try PrivateTemporaryStorage.makeCaptureDirectory(in: temporaryBaseDirectory)
        } catch {
            throw CaptureError.temporaryFileFailure
        }
        let url = dir.appendingPathComponent("clipboard.png", isDirectory: false)
        do {
            try pngData.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return (url, dir)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw CaptureError.temporaryFileFailure
        }
    }

    /// Removes only UUID-named directories previously owned by this app.
    /// File contents and names below those private directories are never read.
    static func cleanUpStaleTemporaryFiles() {
        PrivateTemporaryStorage.cleanOwnedDirectories(in: temporaryBaseDirectory)
    }

    enum CaptureError: Error {
        case appleScript(code: Int)
        case contentTooLarge
        case unsafeAttachment
        case temporaryFileFailure
    }

    static func prepare(fresh: Bool) throws -> Payload {
        fresh ? try readPasteboard() : Payload()
    }

    /// Creates the note and shows it. The caller owns temporary-file cleanup.
    static func capture(_ payload: Payload) throws {
        let body = NoteBuilder.bodyHTML(text: payload.text)
        let source = NoteBuilder.script(bodyHTML: body,
                                        attachmentPaths: payload.attachmentURLs.map(\.path))
        try runAppleScript(source)
    }

    private static func runAppleScript(_ source: String) throws {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw CaptureError.appleScript(code: -1)
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            throw CaptureError.appleScript(code: code)
        }
    }
}
