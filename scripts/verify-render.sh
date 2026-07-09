#!/bin/sh
# End-to-end export fidelity check: renders one of every annotation through the
# REAL pipeline (--test-render) and asserts pixel-level correctness.
set -eu
cd "$(dirname "$0")/.."

swift build -c debug
BIN=.build/debug/ScreenshotEditor
WORK=.build/verify
mkdir -p "$WORK"

[ -f fixtures/fixture.png ] || swift scripts/make-fixture.swift fixtures/fixture.png

cat > "$WORK/annotations-full.json" <<'EOF'
{
  "annotations": [
    {"type": "rectangle",   "rect": [100, 100, 300, 200], "color": [1, 1, 1, 1], "width": 6},
    {"type": "ellipse",     "rect": [1000, 150, 300, 200], "color": [1, 1, 1, 1], "width": 6},
    {"type": "arrow",       "start": [1150, 700], "end": [1350, 850], "color": [1, 1, 1, 1], "width": 8},
    {"type": "pen",         "points": [[150, 650], [350, 650]], "color": [1, 1, 1, 1], "width": 8},
    {"type": "highlighter", "points": [[150, 750], [450, 750]], "color": [1, 0.85, 0.16, 1], "width": 14},
    {"type": "text",        "text": "TEST", "origin": [800, 950], "fontSize": 70, "color": [1, 1, 1, 1]},
    {"type": "badge",       "center": [300, 950], "number": 7, "radius": 45, "color": [0.93, 0.19, 0.14, 1]},
    {"type": "blur",        "rect": [700, 100, 200, 150], "radius": 14},
    {"type": "pixelate",    "rect": [850, 820, 180, 120], "block": 24}
  ]
}
EOF

cat > "$WORK/annotations-crop.json" <<'EOF'
{
  "annotations": [
    {"type": "rectangle", "rect": [300, 200, 100, 100], "color": [1, 1, 1, 1], "width": 6}
  ],
  "crop": [200, 100, 1000, 800]
}
EOF

"$BIN" --test-render fixtures/fixture.png "$WORK/annotations-full.json" "$WORK/out-full.png"
"$BIN" --test-render fixtures/fixture.png "$WORK/annotations-crop.json" "$WORK/out-crop.png"

swift scripts/verify-render.swift fixtures/fixture.png "$WORK/out-full.png" "$WORK/out-crop.png"
