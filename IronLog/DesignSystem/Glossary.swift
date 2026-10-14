import SwiftUI

/// Plain-English explanations for gym words, shown from small "?" buttons.
enum Glossary {
    static let terms: [String: (title: String, text: String)] = [
        "set": ("Set", "One round of an exercise. \"3 sets of 10\" means: do 10 reps, rest, repeat 3 times."),
        "rep": ("Rep", "One full movement, e.g. lowering and pressing the dumbbells once. Aim for the range shown, e.g. 8–12."),
        "rest": ("Rest", "The break between sets so your muscles recover. 60–90 s for most moves, up to 2–3 min for heavy lifts."),
        "weight": ("Choosing a weight", "Pick a weight you can lift for the target reps with 1–2 reps left in the tank and clean form. If all sets feel easy, go up a little next time."),
        "pr": ("PR · Personal record", "Your best ever on an exercise: the heaviest weight, the most reps, or the strongest estimated 1-rep max."),
        "volume": ("Volume", "Weight × reps added up for all sets. More volume over the weeks usually means more muscle."),
        "1rm": ("Estimated 1RM", "The most you could lift once, estimated from your sets. Useful for tracking strength without maxing out."),
        "macros": ("Macros", "Protein builds muscle, carbs fuel training, fat supports hormones. Each has a daily target."),
    ]
}

/// Small round "?" that pops up a short explanation.
struct HelpButton: View {
    let term: String
    @State private var showing = false

    var body: some View {
        Button {
            Haptics.tap()
            showing = true
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20, height: 20)
                .background(Theme.cardRaised, in: Circle())
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing) {
            if let entry = Glossary.terms[term] {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title.uppercased()).font(.display(20)).foregroundStyle(Theme.ember)
                    Text(entry.text).font(.subheadline).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(width: 280)
                .presentationCompactAdaptation(.popover)
            }
        }
        .accessibilityLabel("What is \(term)?")
    }
}

/// Short burst of red/ember particles for finishing a workout or hitting a PR.
struct CelebrationBurst: View {
    @State private var start = Date.now
    private let particles: [(angle: Double, speed: Double, size: Double, hue: Double)] = (0..<70).map { _ in
        (Double.random(in: 0...(2 * .pi)), Double.random(in: 160...420), Double.random(in: 4...9), Double.random(in: 0...1))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < 2.2 else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.35)
                for p in particles {
                    let x = origin.x + cos(p.angle) * p.speed * t
                    let y = origin.y + sin(p.angle) * p.speed * t + 260 * t * t
                    let alpha = max(0, 1 - t / 2.2)
                    let color = p.hue > 0.5 ? Color(hex: 0xE0142F) : p.hue > 0.2 ? Color(hex: 0xFF5A36) : Color.white
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: p.size, height: p.size * 0.6), cornerRadius: 1.5),
                             with: .color(color.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { start = .now }
    }
}
