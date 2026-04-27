//
//  ClipBoxTag.swift
//  ClipBox
//

import SwiftUI

struct ClipBoxTag: Identifiable, Codable {
    let id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    var color: Color { Color(hex: colorHex) ?? .accentColor }

    static let palette: [String] = [
        "#FF6B6B",
        "#FF9F43",
        "#FECA57",
        "#1DD1A1",
        "#48DBFB",
        "#54A0FF",
        "#5F27CD",
        "#FF9FF3",
    ]
}

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >>  8) & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}
