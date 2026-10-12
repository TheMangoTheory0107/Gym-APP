import Combine
import SwiftData
import SwiftUI
import UIKit

/// Loads bundled JPEGs (form photos, muscle renders) once and keeps them in memory.
enum BundledImage {
    private static let cache = NSCache<NSString, UIImage>()

    static func load(_ name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let path = Bundle.main.path(forResource: name, ofType: "jpg"),
              let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

/// Front or back view of the body.
enum BodySide: String, CaseIterable, Identifiable {
    case front, back
    var id: String { rawValue }
}

extension ExerciseDef {
    private static let frontMuscles: Set<String> = ["upper_chest", "chest", "front_delts", "side_delts", "biceps",
                                                   "forearms", "abs", "obliques", "quads", "adductors"]

    /// The side where the main muscle is most visible.
    var preferredSide: BodySide {
        guard let first = primary.first else { return .front }
        return ExerciseDef.frontMuscles.contains(first) ? .front : .back
    }
}

// MARK: - Muscle map

/// HD 3D render of the body with this exercise's muscles lit:
/// primary = bright red, secondary = dark red. Images are pre-rendered (see tools/render).
struct MuscleMapView: View {
    let exercise: ExerciseDef
    @State private var side: BodySide

    init(exercise: ExerciseDef) {
        self.exercise = exercise
        _side = State(initialValue: exercise.preferredSide)
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let image = BundledImage.load("muscles_\(exercise.id)_\(side.rawValue)") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .id(side)
                        .transition(.opacity)
                } else {
                    Rectangle().fill(Theme.cardRaised)
                        .aspectRatio(0.75, contentMode: .fit)
                        .overlay(Text("Muscle image missing").font(.caption).foregroundStyle(Theme.textFaint))
                }

                HStack(spacing: 14) {
                    legend(color: Theme.accent, text: "Primary")
                    if !exercise.secondary.isEmpty { legend(color: Theme.accentDim, text: "Secondary") }
                }
                .padding(10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: side)

            HStack(spacing: 8) {
                ForEach(BodySide.allCases) { s in
                    Button {
                        Haptics.select()
                        side = s
                    } label: {
                        Text(s.rawValue.uppercased())
                            .font(.display(20))
                            .tracking(1.5)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(side == s ? Color.white : Theme.textSecondary)
                            .background(side == s ? Theme.accent : Theme.cardRaised,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

// MARK: - Form demo

/// Alternates the start and end photos to show the movement. Tap to pause.
struct FormDemoView: View {
    let exercise: ExerciseDef
    @State private var frame = 0
    @State private var paused = false

    private let ticker = Timer.publish(every: 1.1, on: .main, in: .common).autoconnect()

    var body: some View {
        let frames = [0, 1].compactMap { BundledImage.load("form_\(exercise.id)_\($0)") }
        ZStack(alignment: .topLeading) {
            if frames.isEmpty {
                Rectangle().fill(Theme.cardRaised).frame(height: 200)
            } else {
                Image(uiImage: frames[frame % frames.count])
                    .resizable()
                    .scaledToFit()
                    .id(frame % frames.count)
                    .transition(.opacity)
            }
            Text(paused ? "PAUSED" : "FORM DEMO")
                .font(.display(15))
                .tracking(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Theme.textPrimary)
                .padding(10)
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 5) {
                ForEach(0..<max(frames.count, 1), id: \.self) { i in
                    Circle().fill(i == frame % max(frames.count, 1) ? Theme.accent : Color.white.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            paused.toggle()
        }
        .onReceive(ticker) { _ in
            guard !paused, frames.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.35)) { frame += 1 }
        }
    }
}

// MARK: - Detail screen

struct ExerciseDetailView: View {
    let exercise: ExerciseDef
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @State private var best: String?
    @State private var last: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenTitle(title: exercise.name, kicker: exercise.equipment)

                FormDemoView(exercise: exercise)
                    .cardStyle(padding: 8)

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Muscles worked")
                    MuscleMapView(exercise: exercise)
                    FlowTags(names: Catalog.shared.muscleNames(exercise.primary), filled: true)
                    if !exercise.secondary.isEmpty {
                        FlowTags(names: Catalog.shared.muscleNames(exercise.secondary), filled: false)
                    }
                }
                .cardStyle()

                if last != nil || best != nil {
                    HStack {
                        StatTile(label: "Last time", value: last ?? "—")
                        StatTile(label: "Best", value: best ?? "—", highlight: true)
                    }
                    .cardStyle()
                }

                if let cues = exercise.cues, !cues.isEmpty {
                    BulletCard(title: "Form cues", items: cues, icon: "checkmark")
                }
                if let mistakes = exercise.mistakes, !mistakes.isEmpty {
                    BulletCard(title: "Common mistakes", items: mistakes, icon: "xmark")
                }

                if let url = exercise.youtubeSearchURL {
                    Button {
                        Haptics.tap()
                        openURL(url)
                    } label: {
                        Label("Watch form video", systemImage: "play.rectangle.fill")
                    }
                    .buttonStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { loadHistory() }
    }

    private func loadHistory() {
        let all = WorkoutStats.history(exerciseId: exercise.id, excluding: nil, context: context)
        guard !all.isEmpty else { return }
        last = WorkoutStats.lastSummary(WorkoutStats.lastTime(exerciseId: exercise.id, excluding: nil, context: context),
                                        exercise: exercise)
        best = WorkoutStats.lastSummary(all, exercise: exercise)
    }
}
