# F2 Quick Note — Design

Date: 2026-07-15
Status: Approved by user in brainstorming session

## Goal

Press **F2** anywhere on macOS → Apple Notes opens a new note. If the clipboard
content was copied within the last **60 seconds**, it is attached to the note;
otherwise an empty new note is created and shown.

## Decisions (from brainstorming)

- **Implementation**: native Swift menu bar app (no Dock icon, `LSUIElement`).
- **Clipboard semantics**: only the *current* clipboard item. If it changed
  within 60s → attach; otherwise (or unknown, e.g. copied before app launch)
  → empty note.
- **Content types**: text, images, and files.
- **Note title**: first line of the content (Apple Notes native behavior —
  first line of body becomes the title). If there is no text (image-only),
  fall back to `Quick Capture yyyy-MM-dd HH:mm` as the first line.
- **Hotkey**: standard F2 (user already has "Use F1, F2… as standard function
  keys" enabled; `com.apple.keyboard.fnState = 1`).

## Architecture

Single Swift Package executable, three units:

1. **HotKeyManager** — Carbon `RegisterEventHotKey(kVK_F2, 0, …)`.
   No Accessibility permission needed.
2. **ClipboardTracker** — 1s timer polling `NSPasteboard.changeCount`,
   records the timestamp of the last change. `isFresh(within: 60)` answers
   the staleness question. Baseline at launch = unknown = stale.
3. **NoteBuilder (pure, unit-tested)** — builds the note body HTML
   (HTML-escaped text, one `<div>` per line) and the AppleScript source
   (string-escaped) that drives Notes:
   - `make new note with properties {body: …}` (default folder)
   - `make new attachment … with data (POSIX file …)` per attachment
   - `show theNote` + `activate`

### Capture flow on F2

```
fresh? ──no──▶ create empty note, show it
   │yes
   ├─ file URLs on pasteboard → attach each file; body text = pasteboard string (filenames)
   ├─ else image (png/tiff)   → write temp PNG, attach; body = fallback title
   └─ else text               → body = escaped text
```

## Permissions

- One-time **Automation (Apple Events → Notes)** prompt on first F2 press.
  `NSAppleEventsUsageDescription` in Info.plist.
- No Accessibility / Input Monitoring needed.

## Error handling

- AppleScript failure (e.g. automation permission denied) → NSAlert with
  instructions to enable in System Settings → Privacy & Security → Automation.
- Empty clipboard or stale → empty note (never an error).

## Build & distribution

- SwiftPM executable; `make app` assembles `dist/F2QuickNote.app`
  (Info.plist with `LSUIElement`, ad-hoc codesign). Local use only.
- Optional autostart: user adds the app to Login Items.

## Testing

- Unit tests (swift test) for NoteBuilder: HTML escaping, line→div
  conversion, fallback title, AppleScript string escaping, attachment
  statement generation.
- Manual end-to-end: copy text / screenshot / file, press F2, verify note.
