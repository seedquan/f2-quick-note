import XCTest
@testable import F2QuickNoteCore

final class NoteBuilderTests: XCTestCase {

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("F2QuickNoteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    // MARK: - HTML escaping

    func testEscapeHTMLEscapesSpecialCharacters() {
        XCTAssertEqual(NoteBuilder.escapeHTML("a < b & c > \"d\""),
                       "a &lt; b &amp; c &gt; &quot;d&quot;")
    }

    func testEscapeHTMLLeavesPlainTextAlone() {
        XCTAssertEqual(NoteBuilder.escapeHTML("你好 world 123"), "你好 world 123")
    }

    // MARK: - Body HTML

    func testBodyHTMLLeavesBlankTitleLineBeforeText() {
        // The title spot stays empty; copied text starts on the second line.
        let html = NoteBuilder.bodyHTML(text: "first line\nsecond line")
        XCTAssertEqual(html, "<div><br></div><div>first line</div><div>second line</div>")
    }

    func testBodyHTMLEmptyLinesBecomeBreaks() {
        let html = NoteBuilder.bodyHTML(text: "a\n\nb")
        XCTAssertEqual(html, "<div><br></div><div>a</div><div><br></div><div>b</div>")
    }

    func testBodyHTMLEscapesContent() {
        let html = NoteBuilder.bodyHTML(text: "<script>")
        XCTAssertEqual(html, "<div><br></div><div>&lt;script&gt;</div>")
    }

    func testBodyHTMLNilTextLeavesBlankTitleLine() {
        // No text → one empty line, keeping the title spot blank. A fully
        // empty body would make Notes materialize "New Note" as literal
        // first-line text.
        XCTAssertEqual(NoteBuilder.bodyHTML(text: nil), "<div><br></div>")
    }

    func testBodyHTMLWhitespaceOnlyTextLeavesBlankTitleLine() {
        XCTAssertEqual(NoteBuilder.bodyHTML(text: "  \n "), "<div><br></div>")
    }

    func testBodyHTMLHandlesCRLF() {
        let html = NoteBuilder.bodyHTML(text: "a\r\nb")
        XCTAssertEqual(html, "<div><br></div><div>a</div><div>b</div>")
    }

    // MARK: - AppleScript string escaping

    func testAppleScriptStringEscapesQuotesAndBackslashes() {
        XCTAssertEqual(NoteBuilder.appleScriptStringLiteral(#"say "hi" \ bye"#),
                       #""say \"hi\" \\ bye""#)
    }

    // MARK: - Script generation

    func testScriptCreatesNoteShowsAndActivates() {
        let script = NoteBuilder.script(bodyHTML: "<div>t</div>", attachmentPaths: [])
        XCTAssertTrue(script.contains(#"make new note with properties {body:"<div>t</div>"}"#))
        XCTAssertTrue(script.contains("show theNote"))
        XCTAssertTrue(script.contains("activate"))
        XCTAssertTrue(script.hasPrefix("tell application \"Notes\""))
        XCTAssertTrue(script.hasSuffix("end tell"))
        XCTAssertFalse(script.contains("attachment"))
    }

    func testScriptAddsOneAttachmentStatementPerPath() {
        let script = NoteBuilder.script(bodyHTML: "<div>t</div>",
                                        attachmentPaths: ["/tmp/a.png", "/tmp/b pic.pdf"])
        let expectedA = #"make new attachment at end of attachments of theNote with data (POSIX file "/tmp/a.png")"#
        let expectedB = #"make new attachment at end of attachments of theNote with data (POSIX file "/tmp/b pic.pdf")"#
        XCTAssertTrue(script.contains(expectedA))
        XCTAssertTrue(script.contains(expectedB))
        // attachments must be added before the note is shown
        XCTAssertLessThan(script.range(of: expectedA)!.lowerBound,
                          script.range(of: "show theNote")!.lowerBound)
    }

    func testScriptDeletesDuplicateAttachmentObjects() {
        // Notes (macOS 26) visibly duplicates attachments created via
        // AppleScript: one `make new attachment` yields two attachment
        // objects and two rendered images. The script must guard each
        // attach with a count check and delete the surplus object.
        let script = NoteBuilder.script(bodyHTML: "", attachmentPaths: ["/tmp/a.png"])
        XCTAssertTrue(script.contains("set beforeCount to count of attachments of theNote"))
        XCTAssertTrue(script.contains("if (count of attachments of theNote) - beforeCount is greater than or equal to 2 then"))
        XCTAssertTrue(script.contains("delete last attachment of theNote"))
        // guard must appear once per attachment
        let script2 = NoteBuilder.script(bodyHTML: "", attachmentPaths: ["/a.png", "/b.png"])
        XCTAssertEqual(script2.components(separatedBy: "delete last attachment of theNote").count - 1, 2)
    }

    func testScriptEscapesQuotesInBodyAndPaths() {
        let script = NoteBuilder.script(bodyHTML: #"<div>a "quote"</div>"#,
                                        attachmentPaths: [#"/tmp/we"ird.png"#])
        XCTAssertTrue(script.contains(#"{body:"<div>a \"quote\"</div>"}"#))
        XCTAssertTrue(script.contains(#"POSIX file "/tmp/we\"ird.png""#))
    }

    // MARK: - Clipboard privacy limits

    func testClipboardPolicyAcceptsContentWithinLimits() {
        XCTAssertTrue(ClipboardPolicy.acceptsText("hello"))
        XCTAssertTrue(ClipboardPolicy.acceptsAttachments(sizes: [1024, 2048]))
    }

    func testClipboardPolicyRejectsOversizedText() {
        let text = String(repeating: "x", count: ClipboardPolicy.maximumTextBytes + 1)
        XCTAssertFalse(ClipboardPolicy.acceptsText(text))
    }

    func testClipboardPolicyRejectsTooManyOrOversizedAttachments() {
        XCTAssertFalse(ClipboardPolicy.acceptsAttachments(
            sizes: Array(repeating: 1, count: ClipboardPolicy.maximumAttachmentCount + 1)
        ))
        XCTAssertFalse(ClipboardPolicy.acceptsAttachments(
            sizes: [ClipboardPolicy.maximumAttachmentBytes + 1]
        ))
        XCTAssertFalse(ClipboardPolicy.acceptsAttachments(
            sizes: [ClipboardPolicy.maximumAttachmentBytes, ClipboardPolicy.maximumAttachmentBytes, 1]
        ))
    }

    func testPrivateTemporaryStorageUsesPrivatePermissions() throws {
        try withTemporaryDirectory { root in
            let base = root.appendingPathComponent("private", isDirectory: true)
            let capture = try PrivateTemporaryStorage.makeCaptureDirectory(in: base)
            let baseMode = try FileManager.default.attributesOfItem(atPath: base.path)[.posixPermissions] as? NSNumber
            let captureMode = try FileManager.default.attributesOfItem(atPath: capture.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual((baseMode?.intValue ?? -1) & 0o777, 0o700)
            XCTAssertEqual((captureMode?.intValue ?? -1) & 0o777, 0o700)
        }
    }

    func testPrivateTemporaryStorageRefusesSymbolicLinkBase() throws {
        try withTemporaryDirectory { root in
            let destination = root.appendingPathComponent("destination", isDirectory: true)
            let link = root.appendingPathComponent("private", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
            XCTAssertThrowsError(try PrivateTemporaryStorage.makeCaptureDirectory(in: link))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
        }
    }

    func testPrivateTemporaryStorageCleansOnlyOwnedUUIDDirectories() throws {
        try withTemporaryDirectory { root in
            let base = root.appendingPathComponent("private", isDirectory: true)
            let owned = try PrivateTemporaryStorage.makeCaptureDirectory(in: base)
            let custom = base.appendingPathComponent("keep-me", isDirectory: true)
            try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: false)
            PrivateTemporaryStorage.cleanOwnedDirectories(in: base)
            XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: custom.path))
        }
    }

    // MARK: - Clipboard freshness

    func testFreshnessUnknownChangeDateIsStale() {
        XCTAssertFalse(ClipboardFreshness.isFresh(lastChange: nil, now: Date(), window: 60))
    }

    func testFreshnessWithinWindowIsFresh() {
        let now = Date()
        XCTAssertTrue(ClipboardFreshness.isFresh(lastChange: now.addingTimeInterval(-59), now: now, window: 60))
    }

    func testFreshnessOutsideWindowIsStale() {
        let now = Date()
        XCTAssertFalse(ClipboardFreshness.isFresh(lastChange: now.addingTimeInterval(-61), now: now, window: 60))
    }

    func testFreshnessBoundaryIsFresh() {
        let now = Date()
        XCTAssertTrue(ClipboardFreshness.isFresh(lastChange: now.addingTimeInterval(-60), now: now, window: 60))
    }
}
