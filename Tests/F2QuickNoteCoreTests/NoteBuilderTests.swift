import XCTest
@testable import F2QuickNoteCore

final class NoteBuilderTests: XCTestCase {

    // MARK: - HTML escaping

    func testEscapeHTMLEscapesSpecialCharacters() {
        XCTAssertEqual(NoteBuilder.escapeHTML("a < b & c > \"d\""),
                       "a &lt; b &amp; c &gt; &quot;d&quot;")
    }

    func testEscapeHTMLLeavesPlainTextAlone() {
        XCTAssertEqual(NoteBuilder.escapeHTML("你好 world 123"), "你好 world 123")
    }

    // MARK: - Body HTML

    func testBodyHTMLFirstLineBecomesFirstDiv() {
        let html = NoteBuilder.bodyHTML(text: "Title line\nsecond line")
        XCTAssertEqual(html, "<div>Title line</div><div>second line</div>")
    }

    func testBodyHTMLEmptyLinesBecomeBreaks() {
        let html = NoteBuilder.bodyHTML(text: "a\n\nb")
        XCTAssertEqual(html, "<div>a</div><div><br></div><div>b</div>")
    }

    func testBodyHTMLEscapesContent() {
        let html = NoteBuilder.bodyHTML(text: "<script>")
        XCTAssertEqual(html, "<div>&lt;script&gt;</div>")
    }

    func testBodyHTMLNilTextIsEmpty() {
        // No fabricated title: image-only and stale captures get a native
        // untitled note.
        XCTAssertEqual(NoteBuilder.bodyHTML(text: nil), "")
    }

    func testBodyHTMLWhitespaceOnlyTextIsEmpty() {
        XCTAssertEqual(NoteBuilder.bodyHTML(text: "  \n "), "")
    }

    func testBodyHTMLHandlesCRLF() {
        let html = NoteBuilder.bodyHTML(text: "a\r\nb")
        XCTAssertEqual(html, "<div>a</div><div>b</div>")
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
