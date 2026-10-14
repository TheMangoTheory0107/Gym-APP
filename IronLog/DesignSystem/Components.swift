import SwiftUI

// MARK: - Screen background

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}

extension View {
    /// Near-black app background behind a screen.
    func screenBackground() -> some View { modifier(ScreenBackground()) }

    /// Gunmetal card look.
    func cardStyle(padding: CGFloat = 16, raised: Bool = false) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(raised ? Theme.cardRaised : Theme.card)
                    .overlay(
                        // Faint top highlight for a machined, premium edge.
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.035), .clear], startPoint: .top, endPoint: .center))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke.opacity(0.7), lineWidth: 1)
            )
    }

    /// Crimson hero card used for the most important thing on a screen.
    func heroCardStyle(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1)
            )
    }
}

// MARK: - Headings

/// Small uppercase label used above sections, e.g. "TODAY'S WORK".
struct SectionLabel: View {
    let text: String
    var accent = false

    var body: some View {
        Text(text.uppercased())
            .font(.display(18, relativeTo: .headline))
            .tracking(1.5)
            .foregroundStyle(accent ? Theme.accent : Theme.textSecondary)
    }
}

/// Big screen title with an optional red kicker line above it.
struct ScreenTitle: View {
    let title: String
    var kicker: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kicker {
                Text(kicker.uppercased())
                    .font(.display(18, relativeTo: .subheadline))
                    .tracking(2)
                    .foregroundStyle(Theme.accent)
            }
            Text(title.uppercased())
                .font(.display(48, relativeTo: .largeTitle))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

/// Full-width, 56pt tall, red. Use for the one main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(24, relativeTo: .title3))
            .tracking(1.5)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.accentGradient)
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
            .shadow(color: Theme.accentGlow, radius: configuration.isPressed ? 6 : 16, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Full-width gunmetal button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(22, relativeTo: .title3))
            .tracking(1.2)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.cardRaised.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Tags

/// Small capsule tag, e.g. a muscle name.
struct Tag: View {
    let text: String
    var filled = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Color.white : Theme.textSecondary)
            .background(filled ? Theme.accent : Theme.cardRaised, in: Capsule())
    }
}

// MARK: - Stats

/// Big number with a small label underneath.
struct StatTile: View {
    let label: String
    let value: String
    var unit: String? = nil
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.display(34, relativeTo: .title))
                    .foregroundStyle(highlight ? Theme.accent : Theme.textPrimary)
                    .monospacedDigit()
                if let unit {
                    Text(unit.uppercased())
                        .font(.display(16, relativeTo: .caption))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rings

/// Horizontal progress bar with the accent gradient.
struct GradientBar: View {
    let progress: Double
    var height: CGFloat = 6
    var muted = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.cardRaised)
                Capsule()
                    .fill(muted ? AnyShapeStyle(Theme.textSecondary) : AnyShapeStyle(Theme.accentGradient))
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
    }
}

/// Small pill with an SF Symbol, e.g. "55 min".
struct InfoPill: View {
    let icon: String
    let text: String
    var highlight = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .foregroundStyle(highlight ? Theme.ember : Theme.textSecondary)
        .background(highlight ? Theme.accent.opacity(0.16) : Theme.cardRaised.opacity(0.9), in: Capsule())
    }
}

/// Bold progress ring. `progress` can go past 1 (over target) and shows a second lap.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 14
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.cardRaised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(Theme.textPrimary.opacity(0.85), style: StrokeStyle(lineWidth: lineWidth * 0.45, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)
    }
}

// MARK: - Empty state

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(title.uppercased())
                .font(.display(26))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 24)
    }
}
