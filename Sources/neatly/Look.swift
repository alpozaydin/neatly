import SwiftUI

/// A color with a light and a dark value, picked from the view's color scheme (so test pictures get it right too).
struct Adaptive: ShapeStyle {
    let light: Color, dark: Color
    init(_ light: UInt32, _ dark: UInt32) { self.light = Color(hex: light); self.dark = Color(hex: dark) }
    init(light: Color, dark: Color) { self.light = light; self.dark = dark }
    func resolve(in env: EnvironmentValues) -> Color { env.colorScheme == .dark ? dark : light }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// neatly's look in one place: one accent, quiet surfaces, SF Pro.
struct Look {
    enum Icons { case glyph, badge }       // plain line icons, or flat colored squares like System Settings
    let accent: Adaptive                   // the one color: Save, switches, the selected choice
    let onAccent: Adaptive                 // text on the accent
    let link: Adaptive                     // text buttons ("Choose Folder…", "History")
    let window: Adaptive                   // window background
    let surface: Adaptive                  // cards and rows
    let stroke: Adaptive                   // hairlines around cards
    let field: Adaptive                    // text boxes, unselected choices, secondary buttons
    let glyph: Adaptive                    // line icons
    let warn: Adaptive                     // "you already have this file", Apple Intelligence off
    let icons: Icons
    let radius: CGFloat                    // cards
    let control: CGFloat                   // buttons and choices
    let titleFont: Font.Design             // window titles only; everything else is SF Pro
    let titleWeight: Font.Weight
    let section: Bool                      // section titles small and grey (true) or headline (false)
    var outlined = false                   // choices drawn as outlines (selected = ink border) instead of filled
    var ink: Adaptive? = nil               // fill of the main button and the selected choice (nil = the accent)
    var onInk: Adaptive? = nil
    var fill: Adaptive { ink ?? accent }
    var onFill: Adaptive { onInk ?? onAccent }

    /// A "Graphite": quiet grey surfaces, softly colored line icons, and one forest-green accent for the main
    /// button, the selected choice, switches and links. Cards stand a little apart from the window.
    static let graphite = Look(
        accent: Adaptive(0x22634A, 0x6CC197), onAccent: Adaptive(0xFFFFFF, 0x0E1A14),
        link: Adaptive(0x22634A, 0x7FCCA3),
        window: Adaptive(0xF3F3F5, 0x161618), surface: Adaptive(0xFFFFFF, 0x222225),
        stroke: Adaptive(0xDEDEE2, 0x313136), field: Adaptive(0xECECEF, 0x2D2D32),
        glyph: Adaptive(0x6E6E73, 0x9A9AA0), warn: Adaptive(0xB25E09, 0xE8A04B),
        icons: .glyph, radius: 12, control: 8, titleFont: .default, titleWeight: .semibold, section: true)

    /// B "Paper": warm off-white, ink-navy accent, New York for titles.
    static let paper = Look(
        accent: Adaptive(0x1F3A6B, 0x9DB4E8), onAccent: Adaptive(0xFFFFFF, 0x14171F),
        link: Adaptive(0x1F3A6B, 0xA9BEEC),
        window: Adaptive(0xF6F4EF, 0x1A1917), surface: Adaptive(0xFFFEFB, 0x23221F),
        stroke: Adaptive(0xE5E0D5, 0x34322D), field: Adaptive(0xEFECE4, 0x2E2C28),
        glyph: Adaptive(0x7A746A, 0xA39D92), warn: Adaptive(0x9A5B12, 0xD9A25E),
        icons: .glyph, radius: 10, control: 7, titleFont: .serif, titleWeight: .semibold, section: false, outlined: true)

    /// C "Native": System Settings surfaces, flat colored icons, one deep cobalt accent.
    static let native = Look(
        accent: Adaptive(0x2457D6, 0x4C84F5), onAccent: Adaptive(0xFFFFFF, 0xFFFFFF),
        link: Adaptive(0x2457D6, 0x6A98F7),
        window: Adaptive(0xF2F2F4, 0x1C1C1E), surface: Adaptive(0xFFFFFF, 0x2A2A2D),
        stroke: Adaptive(0xE3E3E6, 0x38383C), field: Adaptive(0xEBEBEE, 0x3A3A3E),
        glyph: Adaptive(0x6E6E73, 0x98989F), warn: Adaptive(0xC0650A, 0xF0A34E),
        icons: .badge, radius: 10, control: 6, titleFont: .default, titleWeight: .bold, section: true)

    static let current: Look = .graphite

    /// Soft colors for line icons (Graphite): enough to tell sections apart, never loud. Gray stays the glyph grey.
    static func tint(_ c: Color) -> Adaptive {
        switch c {
        case .green: Adaptive(0x2E8B5E, 0x6CC197)
        case .purple, .indigo: Adaptive(0x6B5BD2, 0xA79CF0)
        case .orange: Adaptive(0xC8781F, 0xF0B060)
        case .red: Adaptive(0xC9463D, 0xF08A80)
        case .teal: Adaptive(0x2B86A3, 0x6FC3DB)
        case .gray: look.glyph
        default: Adaptive(0x2F6FD0, 0x7AAAF5)
        }
    }

    /// Flat, quiet versions of the colors badges use (C only).
    static func badge(_ c: Color) -> Color {
        switch c {
        case .green: Color(hex: 0x34A853)
        case .purple, .indigo: Color(hex: 0x5E5CE6)
        case .orange: Color(hex: 0xF09A37)
        case .red: Color(hex: 0xE5484D)
        case .teal: Color(hex: 0x3B8FD9)
        case .gray: Color(hex: 0x8E8E93)
        default: Color(hex: 0x2F7CF6)
        }
    }
}

let look = Look.current
/// The accent, for text and icons.
let brand = look.accent

extension View {
    /// A card: white (or dark) surface with a hairline, no shadow.
    func surface(_ r: CGFloat = look.radius, dim: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(look.surface.opacity(dim ? 0.5 : 1)))
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(look.stroke))
    }
    /// A soft warning box.
    func warnBox() -> some View {
        background(RoundedRectangle(cornerRadius: look.radius, style: .continuous).fill(look.warn.opacity(0.10)))
    }
}

/// The square at the left of a window title (History, Tidy): quiet, never a gradient.
struct TitleMark: View {
    let icon: String
    var body: some View {
        Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(.primary)
            .frame(width: 40, height: 40).surface(10)
    }
}
