import AppKit

// `--capture` runs one capture synchronously and exits. It creates an empty
// note by default. Clipboard content and attachments require separate,
// explicit flags so launchers cannot silently broaden the privacy boundary.
if CommandLine.arguments.contains("--capture") {
    func runCommandLineCapture() -> Int32 {
        var payload = NoteCapture.Payload()
        do {
            let allowContent = CommandLine.arguments.contains("--allow-content")
            let allowAttachments = CommandLine.arguments.contains("--allow-attachments")
            payload = try NoteCapture.prepare(fresh: allowContent)
            defer { payload.cleanUpTemporaryFiles() }
            guard payload.attachmentURLs.isEmpty || (allowContent && allowAttachments) else {
                FileHandle.standardError.write("capture blocked: attachments require --allow-content and --allow-attachments\n".data(using: .utf8)!)
                return 1
            }
            try NoteCapture.capture(payload)
            return 0
        } catch {
            payload.cleanUpTemporaryFiles()
            FileHandle.standardError.write("capture failed safely; clipboard content and local paths were not logged\n".data(using: .utf8)!)
            return 1
        }
    }

    let status = runCommandLineCapture()
    if status == 0 {
        print("capture: ok")
    }
    exit(status)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
