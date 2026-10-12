import SwiftUI

/// Colours for the widget (same values as the app's Theme).
enum WStyle {
    static let background = Color(red: 0.039, green: 0.039, blue: 0.043)
    static let card = Color(red: 0.11, green: 0.118, blue: 0.133)
    static let accent = Color(red: 0.784, green: 0.063, blue: 0.18)
    static let text = Color(red: 0.95, green: 0.95, blue: 0.94)
    static let dim = Color(red: 0.61, green: 0.63, blue: 0.66)

    /// Condensed heavy system font, close to the app's Bebas Neue headings.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }
}
