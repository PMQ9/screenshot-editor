import AppKit
import SwiftUI

/// SwiftUI <-> model color bridging, kept out of the model layer so
/// `Annotation.swift` stays free of AppKit/SwiftUI. sRGB throughout to match
/// the `cgColor` the renderer uses.
extension RGBAColor {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent),
                  b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
