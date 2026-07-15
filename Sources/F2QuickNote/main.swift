import AppKit

// `--capture` runs one capture synchronously and exits — used for testing
// and scripting (e.g. binding from other launchers).
if CommandLine.arguments.contains("--capture") {
    do {
        try NoteCapture.capture(fresh: true)
        print("capture: ok")
        exit(0)
    } catch {
        FileHandle.standardError.write("capture failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
