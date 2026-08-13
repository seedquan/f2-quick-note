# F2 Quick Note

Press **F2** anywhere on macOS → a new Apple Notes note opens. If the current
clipboard content was copied within the last **60 seconds**, it is put into
the note (text becomes the body, first line becomes the title; images and
files become attachments). If the clipboard is older than 60 seconds, you
just get a fresh empty note.

Press **Command-F2** → Apple Notes opens and keyboard focus moves directly to
its search field.

## Install

```sh
make test      # run unit tests
make app       # build dist/F2QuickNote.app
make install   # copy to /Applications
open /Applications/F2QuickNote.app
```

A menu bar icon (note with a plus badge) appears. Press F2 to capture.

## Requirements

- macOS 13+
- **System Settings → Keyboard → "Use F1, F2, etc. keys as standard function
  keys"** must be ON (otherwise F2 is the brightness key; you can still press
  fn+F2).
- On first capture, macOS asks to allow the app to control **Notes** —
  click Allow. If you accidentally deny it: System Settings → Privacy &
  Security → Automation → F2 Quick Note → enable Notes.
- On first Command-F2 search, macOS asks for **Accessibility** permission.
  Enable F2 Quick Note in System Settings → Privacy & Security →
  Accessibility, then press Command-F2 again. This permission is used only to
  locate and focus Apple Notes' search field.

F2 itself needs neither Accessibility nor Input Monitoring permission.

## Behavior details

- Clipboard freshness is tracked by polling `NSPasteboard.changeCount` once
  per second. Content copied *before* the app launched has unknown age and
  is treated as stale.
- Content priority: **files** (copied in Finder, attached; body lists the
  filenames) → **image** (screenshot etc., attached as PNG) → **text**.
- Image-only and stale captures create a native untitled note (no fabricated
  title line).
- Notes duplicates AppleScript-created attachments (macOS 26 bug: one
  `make new attachment` renders the image twice). The generated script
  detects this per attachment and deletes the surplus object.
- Notes are created in the default account's default folder.
- Menu bar menu: capture manually, focus Apple Notes search, toggle
  **Start at Login**, quit.

## Privacy and security

- Clipboard contents are read only after an explicit F2 press or menu action,
  and only when the clipboard changed within the last 60 seconds.
- Apple Notes may sync captured content through the account configured in
  Notes. File and image attachments are created directly when you press F2.
- Symbolic links, directories, excessive attachment counts, and oversized
  text/images/files are rejected before Apple Notes receives anything.
- Clipboard images use a random private temporary directory (`0700`) and file
  (`0600`), then are deleted after success, failure, or cancellation.
- Clipboard text, file names, full paths, generated AppleScript, and raw
  AppleScript errors are never logged. The app contains no network client;
  the only external side effect is the explicitly requested Apple Notes event.
- The app bundle is signed with Hardened Runtime and has no network
  client/server entitlement. App Sandbox is intentionally disabled because
  macOS blocks the Accessibility API in sandboxed apps; Command-F2 uses that
  API only after explicit permission and only to focus Notes' search field.
- The implementation sends Apple Events only to Notes and reads selected
  attachment files without modifying them.
- The scripting entry point `--capture` creates an empty note by default.
  Clipboard text requires `--allow-content`; attachments additionally require
  `--allow-attachments`, preventing launchers from silently widening access.

## Development

- `Sources/F2QuickNoteCore` — pure, unit-tested logic (body HTML, AppleScript
  generation, freshness rule).
- `Sources/F2QuickNote` — AppKit menu bar app: Carbon F2/Command-F2 hotkeys,
  Apple Notes search focusing, clipboard tracker, capture flow.
- Design doc: `docs/superpowers/specs/2026-07-15-f2-quick-note-design.md`.
