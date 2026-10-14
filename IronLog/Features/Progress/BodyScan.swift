import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import Vision

/// Values read from a body-composition report.
struct BodyScanResult {
    var weight: Double?
    var bodyFatPercent: Double?
    var fatMass: Double?
    var muscleMass: Double?
    var bmi: Double?
    var visceralFat: Double?
    var bmr: Double?
    var bodyWater: Double?
    var score: Double?
    var rawText = ""

    var foundCount: Int {
        [weight, bodyFatPercent, fatMass, muscleMass, bmi, visceralFat, bmr, bodyWater, score].compactMap { $0 }.count
    }
}

/// Reads InBody / Tanita / smart-scale reports with Apple's on-device text recognition (no internet).
enum BodyScanReader {
    /// Runs OCR and groups the recognised words into rows, left to right.
    static func recognise(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let items = obs.compactMap { o -> (CGRect, String)? in
                    guard let t = o.topCandidates(1).first?.string else { return nil }
                    return (o.boundingBox, t)
                }
                // Group into rows by vertical position (Vision's y goes up from the bottom).
                var rows: [(y: CGFloat, parts: [(CGFloat, String)])] = []
                for (box, text) in items.sorted(by: { $0.0.midY > $1.0.midY }) {
                    if let i = rows.firstIndex(where: { abs($0.y - box.midY) < max(box.height * 0.6, 0.008) }) {
                        rows[i].parts.append((box.minX, text))
                    } else {
                        rows.append((box.midY, [(box.minX, text)]))
                    }
                }
                cont.resume(returning: rows.map { $0.parts.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: " ") })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch { cont.resume(returning: []) }
            }
        }
    }

    static func parse(_ rows: [String]) -> BodyScanResult {
        var r = BodyScanResult()
        r.rawText = rows.joined(separator: "\n")
        let lower = rows.map { $0.lowercased() }

        func value(after keys: [String], excluding: [String] = [], range: ClosedRange<Double>) -> Double? {
            for (i, row) in lower.enumerated() {
                guard let key = keys.first(where: { row.contains($0) }),
                      !excluding.contains(where: { row.contains($0) }) else { continue }
                let tail = String(row[row.range(of: key)!.upperBound...])
                if let v = firstNumber(in: tail), range.contains(v) { return v }
                // Value printed on the next row (common on InBody sheets)
                if i + 1 < lower.count, let v = firstNumber(in: lower[i + 1]), range.contains(v) { return v }
            }
            return nil
        }

        r.weight = value(after: ["weight", "body weight", "wt."],
                         excluding: ["control", "target", "ideal", "lean", "standard", "fat free", "muscle"], range: 30...250)
        r.muscleMass = value(after: ["skeletal muscle mass", "smm", "muscle mass", "skeletal muscle"], range: 10...90)
        r.fatMass = value(after: ["body fat mass", "fat mass"], excluding: ["free", "control"], range: 2...120)
        r.bodyFatPercent = value(after: ["percent body fat", "pbf", "body fat %", "body fat percentage", "body fat(%)",
                                         "fat %", "fat%", "body fat"], excluding: ["mass", "control"], range: 3...65)
        r.bmi = value(after: ["body mass index", "bmi"], range: 12...60)
        r.visceralFat = value(after: ["visceral fat level", "visceral fat", "visceral"], excluding: ["area"], range: 1...30)
        r.bmr = value(after: ["basal metabolic rate", "bmr"], range: 800...4000)
        r.bodyWater = value(after: ["total body water", "body water", "tbw", "water"], range: 15...85)
        r.score = value(after: ["inbody score", "fitness score", "body score", "score"], range: 30...110)
        return r
    }

    /// First decimal number in a string, ignoring anything inside a "(min~max)" range.
    static func firstNumber(in text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: ",", with: ".")
        guard let match = cleaned.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(cleaned[match])
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Camera for taking a photo of the report.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Scan a report → review the numbers → save as a weigh-in with body composition.
struct BodyScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(ProfileKey.healthSyncEnabled) private var healthSync = false

    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var reading = false
    @State private var result: BodyScanResult?
    @State private var date = Date.now
    @State private var fields: [String: String] = [:]

    private let rows: [(key: String, label: String, unit: String)] = [
        ("weight", "Weight", "kg"), ("bodyFat", "Body fat", "%"), ("fatMass", "Fat mass", "kg"),
        ("muscle", "Skeletal muscle mass", "kg"), ("visceral", "Visceral fat level", ""),
        ("bmr", "BMR", "kcal"), ("water", "Body water", "L"), ("score", "Score", "/100"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if result == nil {
                        intro
                    } else {
                        review
                    }
                }
                .padding(Theme.gutter)
            }
            .screenBackground()
            .navigationTitle("BODY SCAN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if result != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold) }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in Task { await read(image) } }.ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await read(image)
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
            Text("READ YOUR BODY REPORT").font(.display(34)).foregroundStyle(Theme.textPrimary)
            Text("Take a clear, flat photo of your InBody printout or your scale's results screen. The numbers are read on your phone; nothing is uploaded.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
            if reading {
                HStack(spacing: 10) { ProgressView().tint(Theme.accent); Text("Reading…").foregroundStyle(Theme.textSecondary) }
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera.fill") }
                    .buttonStyle(.primary)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .font(.display(22)).tracking(1.2)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Theme.textPrimary)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
            }
            Label("Works with InBody 270 / 570 / 770, Tanita, Omron and most smart-scale apps.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(Theme.textFaint)
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 14) {
            let found = result?.foundCount ?? 0
            Label(found > 0 ? "Found \(found) values. Check them before saving." : "Couldn't read numbers. Try a sharper photo, or type them in.",
                  systemImage: found > 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(found > 0 ? Theme.ember : Theme.textSecondary)
            DatePicker("Date of scan", selection: $date, in: ...Date.now, displayedComponents: .date)
                .tint(Theme.accent)
                .cardStyle(padding: 12)
            VStack(spacing: 0) {
                ForEach(rows, id: \.key) { row in
                    HStack {
                        Text(row.label).font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        TextField("—", text: Binding(get: { fields[row.key] ?? "" }, set: { fields[row.key] = $0 }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.display(22))
                            .frame(width: 90)
                        Text(row.unit).font(.caption.weight(.bold)).foregroundStyle(Theme.textFaint).frame(width: 36, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                    Divider().overlay(Theme.stroke)
                }
            }
            .padding(.horizontal, 14)
            .cardStyle(padding: 0)
            Button("Save scan") { save() }.buttonStyle(.primary)
            Button("Scan again") { result = nil; fields = [:] }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    @MainActor
    private func read(_ image: UIImage) async {
        reading = true
        let rows = await BodyScanReader.recognise(image)
        let r = BodyScanReader.parse(rows)
        func f(_ v: Double?) -> String { v.map { Fmt.weight(($0 * 10).rounded() / 10) } ?? "" }
        fields = ["weight": f(r.weight), "bodyFat": f(r.bodyFatPercent), "fatMass": f(r.fatMass), "muscle": f(r.muscleMass),
                  "visceral": f(r.visceralFat), "bmr": f(r.bmr), "water": f(r.bodyWater), "score": f(r.score)]
        // Fill body fat % from fat mass if only that was printed.
        if r.bodyFatPercent == nil, let fm = r.fatMass, let w = r.weight, w > 0 { fields["bodyFat"] = f(fm / w * 100) }
        result = r
        reading = false
        Haptics.success()
    }

    private func number(_ key: String) -> Double? {
        Double((fields[key] ?? "").replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        guard let weight = number("weight") else { Haptics.warning(); return }
        let m = BodyMetric(date: date, weightKg: weight, bodyFatPercent: number("bodyFat"), source: "scan")
        m.fatMassKg = number("fatMass")
        m.muscleMassKg = number("muscle")
        m.visceralFat = number("visceral")
        m.bmr = number("bmr")
        m.bodyWater = number("water")
        m.bodyScore = number("score")
        context.insert(m)
        try? context.save()
        if healthSync {
            let bf = m.bodyFatPercent
            Task {
                try? await HealthKitManager.shared.saveWeight(kg: weight, date: date)
                if let bf { try? await HealthKitManager.shared.saveBodyFat(percent: bf, date: date) }
            }
        }
        Haptics.success()
        dismiss()
    }
}

/// Latest body-composition readings (shown when a scan has been saved).
struct BodyCompositionCard: View {
    let metric: BodyMetric

    var body: some View {
        let items: [(String, String, String)] = [
            ("Muscle mass", metric.muscleMassKg.map { String(format: "%.1f", $0) } ?? "", "kg"),
            ("Fat mass", metric.fatMassKg.map { String(format: "%.1f", $0) } ?? "", "kg"),
            ("Visceral fat", metric.visceralFat.map { String(format: "%.0f", $0) } ?? "", "lvl"),
            ("BMR", metric.bmr.map { String(format: "%.0f", $0) } ?? "", "kcal"),
            ("Body water", metric.bodyWater.map { String(format: "%.1f", $0) } ?? "", "L"),
            ("Score", metric.bodyScore.map { String(format: "%.0f", $0) } ?? "", ""),
        ].filter { !$0.1.isEmpty }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Body composition")
                Spacer()
                Text(metric.date.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.textFaint)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(items, id: \.0) { item in
                    StatTile(label: item.0, value: item.1, unit: item.2.isEmpty ? nil : item.2)
                }
            }
        }
        .cardStyle()
    }
}
