import Foundation

/// Pure helpers that build the Apple Notes note body and the AppleScript
/// source used to create it. No AppKit dependencies so it stays unit-testable.
public enum NoteBuilder {

    public static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Notes renders each `<div>` as a line and uses the first line as the
    /// note title. Empty lines need `<br>` to survive. No text → one blank
    /// line: the title spot stays empty. (A fully empty body makes Notes
    /// write the literal default name "New Note" into the note.)
    public static func bodyHTML(text: String?) -> String {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "<div><br></div>" }
        return trimmed
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                line.isEmpty ? "<div><br></div>" : "<div>\(escapeHTML(line))</div>"
            }
            .joined()
    }

    public static func appleScriptStringLiteral(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// AppleScript that creates a note in the default folder, attaches the
    /// given files, then shows it and brings Notes to the front.
    ///
    /// Notes (observed on macOS 26) duplicates every attachment created via
    /// `make new attachment`: one call yields two attachment objects and the
    /// image renders twice in the note. Each attach is therefore guarded by
    /// a count check that deletes the surplus object — conditionally, so a
    /// fixed Notes version won't lose the real attachment.
    public static func script(bodyHTML: String, attachmentPaths: [String]) -> String {
        var lines: [String] = []
        lines.append("tell application \"Notes\"")
        lines.append("set theNote to make new note with properties {body:\(appleScriptStringLiteral(bodyHTML))}")
        for path in attachmentPaths {
            lines.append("set beforeCount to count of attachments of theNote")
            lines.append("make new attachment at end of attachments of theNote with data (POSIX file \(appleScriptStringLiteral(path)))")
            lines.append("if (count of attachments of theNote) - beforeCount is greater than or equal to 2 then")
            lines.append("delete last attachment of theNote")
            lines.append("end if")
        }
        lines.append("show theNote")
        lines.append("activate")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }
}

/// Answers "was the clipboard copied recently enough to attach?"
public enum ClipboardFreshness {
    /// `lastChange == nil` means we never saw the pasteboard change (content
    /// predates app launch) — treat as stale.
    public static func isFresh(lastChange: Date?, now: Date = Date(), window: TimeInterval) -> Bool {
        guard let lastChange else { return false }
        return now.timeIntervalSince(lastChange) <= window
    }
}
