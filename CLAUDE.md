# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native macOS menu-bar app (Swift/SwiftUI, **no third-party dependencies, no Xcode project**) that turns a screenshot on the clipboard into an annotated screenshot on the clipboard. It runs as an `LSUIElement` accessory app living in the menu bar; the editor is a plain `NSWindow` hosting a SwiftUI view.

## Build / run / test

Requires macOS 15+ and the Xcode **Command Line Tools only** — full Xcode / `xcodebuild` is never used and there is no `.xcodeproj`. SwiftPM drives everything, wrapped by the Makefile and `scripts/`.

```sh
make run        # build debug, bundle dist/Screenshot Editor.app, launch
make run-fg     # same, but run in the foreground so logs stream to the terminal (dev loop)
make release    # optimized build + bundle
make app        # bundle only, no launch
make test       # unit tests — USE THIS, not `swift test` (see below)
make clean      # rm -rf .build dist
swift build -c debug        # compile only, no bundle
scripts/verify-render.sh    # end-to-end pixel-fidelity check through the real export pipeline
```

**Always run tests with `make test`, never bare `swift test`.** The Command Line Tools ship `Testing.framework` outside the default search paths, so `make test` injects framework/rpath flags (`TEST_FLAGS` in the [Makefile](Makefile)); plain `swift test` fails with `no such module 'Testing'`. To run a single test, reuse those same `TEST_FLAGS` and append a Swift Testing filter, e.g. `swift test <TEST_FLAGS…> --filter cropRebasesAnnotationsAndBumpsGeneration`.

There is no linter or formatter configured.

## Non-negotiable architecture invariants

These are the load-bearing design decisions — most bugs in an annotation app come from violating one. Preserve them.

**1. One coordinate space below the view layer: base-image pixels.** All geometry in [Model/](Sources/ScreenshotEditor/Model/), [ViewModel/](Sources/ScreenshotEditor/ViewModel/), and [Rendering/](Sources/ScreenshotEditor/Rendering/) is in base-image pixels, top-left origin, y-down. Nothing below the view layer knows about points, screen scale, or zoom. [CanvasTransform.swift](Sources/ScreenshotEditor/Model/CanvasTransform.swift) is the ONLY place pixel↔view conversion happens; gestures, hit tolerance, overlay positions, and canvas drawing all route through it. No other code multiplies by a scale factor. Conversion happens exactly at the event boundary in [EditorCanvasView.swift](Sources/ScreenshotEditor/Views/EditorCanvasView.swift) (`transform.toImage(...)` inbound, `transform.toView(...)` for chrome).

**2. One renderer for screen and export — they cannot diverge.** [AnnotationRenderer](Sources/ScreenshotEditor/Rendering/AnnotationRenderer.swift)`.draw` is the single draw routine. The on-screen `Canvas` calls it inside `GraphicsContext.withCGContext`; full-resolution export ([ExportService](Sources/ScreenshotEditor/Rendering/ExportService.swift)) calls it into a bitmap context at exact pixel dimensions. Same code → what you see is what you copy. Never add a screen-only or export-only draw path; change the shared renderer instead.

**3. Exactly three y-flip sites.** The renderer's contract is y-down, but CoreGraphics/CoreImage are y-up, so images/blur would render mirrored. Flipping is deliberately isolated to three places and nowhere else: `CGContext.drawImageYDown` (every base-image / blur-patch blit, in the renderer), the export context's initial flip in `ExportService.renderFullResolution`, and the CoreImage rect conversion in [BlurPatchCache](Sources/ScreenshotEditor/Rendering/BlurPatchCache.swift). Do not add ad-hoc flips; funnel through these.

**4. Undo = whole-`Document` snapshots.** [Document](Sources/ScreenshotEditor/Model/Document.swift) is a value type; the undo/redo stacks in [EditorViewModel](Sources/ScreenshotEditor/ViewModel/EditorViewModel.swift) are just `[Document]`, one entry per user-visible operation, bracketed by `beginGesture()` / `endGesture()` (pushes only if the document actually changed). Consequently a pointer gesture in flight holds a `preGestureSnapshot`, and history-mutating actions (delete, nudge, style change) are refused unless `interaction == .idle`. `⌘Z` mid-gesture *aborts the gesture* (restores the snapshot) rather than popping history — the next `⌘Z` pops. Keep this ordering when touching undo.

**5. Redaction is destructive and samples only the base image.** Blur/pixelate (`AnnotationKind.blur` + `RedactionMode`) genuinely destroy covered pixels in the export — not peelable overlays, and the test suite asserts this. Patches sample the BASE image only (never other annotations) and always render below vector annotations. `BlurPatchCache` memoizes each patch keyed on `(rect, mode, cropGeneration)`; `Document.cropGeneration` is bumped by crop so patches recompute against the rebased image. Keep blur sampling the base and keep the cache key honest.

## Other structural notes

- **Editing is an explicit state machine.** The `Interaction` enum in `EditorViewModel` (`idle` / `drawing` / `draggingAnnotation` / `resizing` / `editingText` / `croppingDrag` / `croppingDraft`) is the single source of truth; pointer and keyboard handlers are its transitions. The class is `@MainActor @Observable`; the SwiftUI view reads observable state in its body so the `Canvas` re-renders.
- **Units convert at the UI boundary.** Style presets are point-denominated in the UI (`strokeWidthPt`, `fontSizePt`) and multiplied by `pixelsPerPoint` when written into the model. `pixelsPerPoint` comes from the source image (2.0 for Retina screenshots) and is also used to stamp PNG DPI on export.
- **Color space is preserved, not normalized.** Screenshots are often Display P3; export and blur keep the source RGB color space rather than forcing sRGB (avoids a visible shift and patch-edge seams). See `ExportService.exportColorSpace` and `BlurPatchCache`.
- **Crop rebases in place.** `Document.applyCrop` crops the `CGImage`, translates every annotation into the new origin, and bumps `cropGeneration`.
- **Swift 6, strict.** `swift-tools-version: 6.2`, language mode v6, `defaultIsolation(MainActor.self)` on both targets — expect full concurrency checking.

## Headless render pipeline (verifying pixels)

`ScreenshotEditor --test-render <in.png> <annotations.json> <out.png>` runs the EXACT export pipeline with no AppKit — [main.swift](Sources/ScreenshotEditor/main.swift) early-exits into [TestRenderMode](Sources/ScreenshotEditor/TestRenderMode.swift) before `NSApplication` starts. This is the backbone of `scripts/verify-render.sh`, which renders one of every annotation and asserts dimensions, positions, blend math, true redaction, and crop rebasing at the pixel level ([scripts/verify-render.swift](scripts/verify-render.swift)). The annotation JSON schema is documented at the top of `TestRenderMode.swift`. Use this to verify any rendering change end-to-end — the unit tests alone don't exercise the pixels.

## Platform / permissions

- **No special permissions by design**: no Accessibility, no Screen Recording. The global hotkey (⌘⇧E) uses Carbon `RegisterEventHotKey` ([HotkeyManager](Sources/ScreenshotEditor/HotkeyManager.swift)) — the one hotkey API that needs no Input-Monitoring grant. The clipboard is read only on explicit user action or the opt-in auto-pop ([ClipboardMonitor](Sources/ScreenshotEditor/ClipboardMonitor.swift)).
- **Activation-policy dance** ([WindowRegistry](Sources/ScreenshotEditor/Windows/WindowRegistry.swift)): the app is `.accessory` (menu-bar only) when idle and flips to `.regular` (Dock + ⌘-Tab) while any editor or settings window is open.
- [docs/verified-behavior.md](docs/verified-behavior.md) records machine-verified platform behavior (pasteboard types, the SwiftUI `Canvas` y-down origin, the CLT test-framework quirk). Re-verify after OS updates; a few items still need a human eyeball (listed there).
- The hotkey has no in-app recorder yet; override via `defaults write com.phamqm.ScreenshotEditor hotkeyKeyCode/-hotkeyModifiers` and relaunch.
