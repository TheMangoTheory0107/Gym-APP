import SwiftUI

/// First launch: who you are, your goal and experience, and permissions. Four quick screens.
struct OnboardingView: View {
    let onDone: () -> Void

    @AppStorage(ProfileKey.name) private var name = ProfileDefault.name
    @AppStorage(ProfileKey.goal) private var goal = "Build muscle"
    @AppStorage(ProfileKey.experience) private var experience = "New to the gym"
    @AppStorage(ProfileKey.healthSyncEnabled) private var healthConnected = false
    @State private var page = 0
    @State private var notificationsOn = false

    private let goals: [(String, String)] = [("Build muscle", "dumbbell.fill"), ("Lose fat", "flame.fill"),
                                             ("Get stronger", "bolt.fill"), ("Stay fit", "heart.fill")]
    private let levels: [(String, String)] = [("New to the gym", "Show me what to do, step by step"),
                                              ("Some experience", "I know the basics"),
                                              ("Experienced", "Just let me log fast")]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(i <= page ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.cardRaised))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 12)

            TabView(selection: $page) {
                welcome.tag(0)
                goalPage.tag(1)
                levelPage.tag(2)
                permissions.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            Button(page == 3 ? "Let's go" : "Continue") {
                Haptics.tap()
                if page < 3 { page += 1 } else { onDone() }
            }
            .buttonStyle(.primary)
            .padding(Theme.gutter)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func pageTitle(_ kicker: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker.uppercased()).font(.display(18)).tracking(2).foregroundStyle(Theme.ember)
            Text(title.uppercased()).font(.display(46)).foregroundStyle(Theme.textPrimary)
                .lineLimit(3).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(Theme.accentGradient)
            pageTitle("Welcome", "Your coach in your pocket")
            VStack(alignment: .leading, spacing: 14) {
                feature("figure.strengthtraining.traditional", "Every workout, guided", "One exercise at a time, with form tips and the muscles it works.")
                feature("fork.knife", "Your diet, one tap", "Log planned meals instantly, or just type or say what you ate.")
                feature("chart.line.uptrend.xyaxis", "See yourself improve", "Strength, body weight and weekly reports, all automatic.")
            }
            TextField("Your name", text: $name)
                .font(.title3.weight(.semibold))
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ember)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var goalPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            pageTitle("Step 1", "What's your main goal?")
            ForEach(goals, id: \.0) { g in
                choice(title: g.0, subtitle: nil, icon: g.1, selected: goal == g.0) { goal = g.0 }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var levelPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            pageTitle("Step 2", "How much gym experience?")
            ForEach(levels, id: \.0) { l in
                choice(title: l.0, subtitle: l.1, icon: nil, selected: experience == l.0) { experience = l.0 }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            pageTitle("Step 3", "Connect your phone")
            permissionRow(icon: "heart.fill", title: "Apple Health",
                          text: "Steps, calories and workouts from your iPhone and Apple Watch appear automatically.",
                          on: healthConnected) {
                Task {
                    try? await HealthKitManager.shared.requestAuthorization()
                    healthConnected = true
                    await HealthData.shared.refresh()
                }
            }
            permissionRow(icon: "bell.fill", title: "Reminders",
                          text: "Rest timer alerts with the phone locked, plus water and supplement reminders.",
                          on: notificationsOn) {
                Task { notificationsOn = await NotificationManager.shared.requestPermission() }
            }
            Text("You can change these any time in Settings.")
                .font(.caption).foregroundStyle(Theme.textFaint)
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func choice(title: String, subtitle: String?, icon: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 14) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Theme.ember).frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased()).font(.display(24))
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(selected ? .white.opacity(0.85) : Theme.textSecondary)
                    }
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").font(.title3) }
            }
            .foregroundStyle(selected ? Color.white : Theme.textPrimary)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card))
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.clear : Theme.stroke))
        }
        .buttonStyle(.plain)
    }

    private func permissionRow(icon: String, title: String, text: String, on: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ember)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
                Button(on ? "Connected" : "Allow") {
                    Haptics.tap()
                    action()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(on ? Theme.textSecondary : Theme.ember)
                .disabled(on)
            }
        }
        .cardStyle()
    }
}
