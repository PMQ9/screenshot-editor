# Screenshot Editor

A lightweight, native macOS menu-bar app that turns *screenshot on the
clipboard* into *annotated screenshot on the clipboard* in seconds.

Take a screenshot to the clipboard (⌃⇧⌘4), press **⌘⇧E** (or let the editor
pop open automatically), annotate, press **⌘C**, paste anywhere.

Built with Swift/SwiftUI, no third-party dependencies, no Xcode project —
builds with Swift Package Manager and the Command Line Tools alone.

## Features

- **Capture entry points**: global hotkey ⌘⇧E · menu-bar icon · auto-open when
  a screenshot lands on the clipboard (toggleable) · ⌘V into an open editor
- **Tools**: select/move/resize · rectangle · ellipse · arrow · freehand pen ·
  highlighter (real multiply blend) · text · numbered step badges ·
  regional gaussian blur · pixelate · crop
- **Output**: ⌘C copies the annotated PNG to the clipboard · ⌘S saves a file ·
  drag the image out of the toolbar into Finder/Slack/browser
- Full undo/redo (⌘Z / ⇧⌘Z), color and size presets, Fit/100% zoom
- Exports at **full native pixel resolution** (Retina-correct by construction:
  one shared Core Graphics renderer for screen and export; annotations are
  stored in image-pixel coordinates)
- Blur/pixelate genuinely destroy the covered pixels in exports (verified by
  the test suite — not an overlay that can be peeled off)
- No permissions needed: no Accessibility, no Screen Recording; the clipboard
  is only read on your explicit action or the auto-open you opted into

## Build & run

Requires macOS 15+ and the Xcode Command Line Tools (full Xcode not needed).

```sh
make run       # build, bundle dist/Screenshot Editor.app, launch
make run-fg    # same, but logs stream to the terminal (dev loop)
make release   # optimized build
```

The app lives in the menu bar (photo icon). Quit from its menu.

## Keyboard

| Key | Action |
|-----|--------|
| ⌘⇧E (global) | Open editor with the clipboard image |
| V R O A P H T N B X C | Switch tool (select, rect, oval, arrow, pen, highlighter, text, badge, blur, pixelate, crop) |
| ⌘C / ⌘S | Copy annotated image / save as PNG |
| ⌘V | Replace the editor's image with the clipboard |
| ⌘Z / ⇧⌘Z | Undo / redo |
| Delete | Delete selected annotation |
| Return | Apply crop / commit text |
| Esc | Cancel drag/crop/text, then deselect |
| Arrow keys | Nudge selection |
| ⌘0 / ⌘1 | Zoom to fit / actual size |

## Verification

```sh
make test                 # unit tests (transform, hit-testing, undo, crop, badges)
scripts/verify-render.sh  # end-to-end export fidelity: renders every tool
                          # through the real pipeline and asserts pixels
                          # (exact dimensions, positions, blend math, true
                          # redaction, crop rebasing)
```

`ScreenshotEditor --test-render in.png annotations.json out.png` runs the
exact export pipeline headlessly; see [scripts/verify-render.sh](scripts/verify-render.sh)
for the annotation JSON schema and [docs/verified-behavior.md](docs/verified-behavior.md)
for machine-verified platform behavior notes.

## Project layout

```
Sources/ScreenshotEditor/
  Model/       Annotation, Document, CanvasTransform — pixel-space value types
  Rendering/   the single shared CG renderer, CoreText, CoreImage blur cache, export
  ViewModel/   tool/interaction state machine, snapshot undo stacks
  Views/       SwiftUI canvas, toolbar, text-editing overlay
  Windows/     NSWindow controllers, activation-policy dance
  Pasteboard/  clipboard read/write
  Settings/    UserDefaults-backed settings + UI
  Export/      clipboard/save/drag-out
scripts/       bundling, fixtures, pixel-assertion verification
```

## Deferred (v1.1 candidates)

Interactive hotkey recorder (currently ⌘⇧E; override with
`defaults write com.phamqm.ScreenshotEditor hotkeyKeyCode/-hotkeyModifiers`),
pinch zoom, multiline text, badge renumbering, launch-at-login, app icon.
