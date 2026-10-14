import SwiftUI
import UIKit

/// All colours and fonts live here. Change the accent in one place and the whole app follows.
enum Theme {
    // Surfaces (darkest → lightest)
    static let background = Color(hex: 0x08080A)
    static let surface = Color(hex: 0x111214)
    static let card = Color(hex: 0x16171B)
    static let cardRaised = Color(hex: 0x212329)
    static let stroke = Color(hex: 0x2C2F36)

    // Text
    static let textPrimary = Color(hex: 0xF2F2F0)
    static let textSecondary = Color(hex: 0x9BA0A8)
    static let textFaint = Color(hex: 0x5D626A)

    // The one accent colour (deep red) + a dimmer shade for secondary highlights
    static let accent = Color(hex: 0xE0142F)
    static let ember = Color(hex: 0xFF5A36)
    static let accentDim = Color(hex: 0x6E1020)
    static let accentGlow = Color(hex: 0xE0142F, opacity: 0.35)

    /// Signature red → ember gradient, used sparingly for the main action and progress.
    static let accentGradient = LinearGradient(colors: [accent, ember], startPoint: .leading, endPoint: .trailing)
    /// Dark crimson wash for hero cards.
    static let heroGradient = LinearGradient(colors: [Color(hex: 0x3A0A12), Color(hex: 0x1A0C10), Color(hex: 0x121316)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cornerRadius: CGFloat = 14
    static let gutter: CGFloat = 16
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Fonts

enum AppFont {
    /// PostScript name of the bundled Bebas Neue font.
    static let displayName = "BebasNeue-Regular"
}

extension Font {
    /// Bold condensed uppercase display font (Bebas Neue). Falls back to the system font if missing.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(AppFont.displayName, size: size, relativeTo: style)
    }
}

extension UIFont {
    static func display(_ size: CGFloat) -> UIFont {
        UIFont(name: AppFont.displayName, size: size) ?? .systemFont(ofSize: size, weight: .heavy)
    }
}

// MARK: - UIKit chrome (tab bar + navigation bar)

enum Appearance {
    static func configure() {
        let bg = UIColor(Theme.background)
        let accent = UIColor(Theme.accent)
        let faint = UIColor(Theme.textFaint)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = bg
        nav.shadowColor = .clear
        nav.largeTitleTextAttributes = [.font: UIFont.display(42), .foregroundColor: UIColor(Theme.textPrimary)]
        nav.titleTextAttributes = [.font: UIFont.display(24), .foregroundColor: UIColor(Theme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = accent

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.surface)
        tab.shadowColor = UIColor(Theme.stroke)
        let item = UITabBarItemAppearance()
        item.normal.iconColor = faint
        item.normal.titleTextAttributes = [.font: UIFont.display(13), .foregroundColor: faint]
        item.selected.iconColor = accent
        item.selected.titleTextAttributes = [.font: UIFont.display(13), .foregroundColor: accent]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
