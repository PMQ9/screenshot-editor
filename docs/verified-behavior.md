# Empirically verified behavior on this machine

Machine: macOS 26.5.1 (arm64), Swift 6.3.2, Command Line Tools only (no Xcode).
Date: 2026-07-09. Re-verify after OS updates.

## Toolchain

- `xcodebuild` is unavailable — build is SwiftPM + `scripts/bundle.sh`, never an .xcodeproj.
- Swift Testing works with CLT but needs explicit framework/rpath flags
  (see `TEST_FLAGS` in the Makefile). Plain `swift test` fails with
  "no such module 'Testing'"; always use `make test`.

## Pasteboard

- An image placed on the general pasteboard exposes types:
  `public.png`, `public.tiff` (plus legacy aliases). `availableType(from: [.png, .tiff])`
  is the right detection check.
- Clipboard image round-trip: NSImage size 800x600 pt / 1600x1200 px for a 2x
  fixture — `pixelsPerPoint` = pixelWidth / size.width = 2.0 as designed.
- Pasteboard privacy (macOS 15.4+ "Paste from Other Apps"): a background,
  non-user-initiated `data(forType:)` read completed in ~5 ms with NO system
  prompt; `accessBehavior` rawValue 2 before and after. Enforcement is not
  active by default on this machine → direct-open auto-pop is viable.
  Contingency (notification chip) documented in the plan if a future OS
  update enables prompting.

## SwiftUI Canvas

- `GraphicsContext.withCGContext` inside `Canvas` hands over a CGContext with
  TOP-LEFT origin, y-down (verified by pixel probe: fill at (0,0) landed at
  the top-left of the rendered raster). Matches the model's coordinate
  convention. Note: because the context is y-down, `CGContext.draw(image:)`
  must locally flip or images render upside down — centralized in
  `CGContext.drawImageYDown` in the renderer.
- `ImageRenderer` produces a `cgImage` headlessly (no run loop needed);
  its `scale` defaults to 1.0 — never use it for export.

## Still needs a human eyeball (end of build)

- Carbon hotkey fires while the app is in the background (⌘⇧E).
- Hotkey-summoned editor window becomes key and accepts typing immediately.
- Pasteboard privacy behavior for the *bundled, ad-hoc-signed* app identity
  (probe above ran under the `swift` interpreter's identity).
