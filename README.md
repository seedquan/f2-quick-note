# F2 Quick Note

Press **F2** anywhere on macOS → a new Apple Notes note opens. If the current
clipboard content was copied within the last **60 seconds**, it is put into
the note (text becomes the body, first line becomes the title; images and
files become attachments). If the clipboard is older than 60 seconds, you
just get a fresh empty note.

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

No Accessibility or Input Monitoring permission is needed.

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
- Menu bar menu: capture manually, toggle **Start at Login**, quit.

## Development

- `Sources/F2QuickNoteCore` — pure, unit-tested logic (body HTML, AppleScript
  generation, freshness rule).
- `Sources/F2QuickNote` — AppKit menu bar app: Carbon F2 hotkey (no
  Accessibility permission needed), clipboard tracker, capture flow.
- Design doc: `docs/superpowers/specs/2026-07-15-f2-quick-note-design.md`.
