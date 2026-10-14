import SceneKit
import SwiftUI
import UIKit

/// Loads the bundled 3D body (MuscleBody.usdz) once. Each muscle group is a node named "m_<muscle id>".
enum MuscleModel {
    private static var template: SCNNode?
    private static let queue = DispatchQueue(label: "muscle-model")

    /// Loads (or reuses) the model off the main thread, then calls back on the main thread with a fresh copy.
    static func load(_ completion: @escaping (SCNNode?) -> Void) {
        queue.async {
            if template == nil, let url = Bundle.main.url(forResource: "MuscleBody", withExtension: "usdz"),
               let scene = try? SCNScene(url: url, options: [.checkConsistency: false]) {
                let root = SCNNode()
                for child in scene.rootNode.childNodes { root.addChildNode(child) }
                template = normalised(root)
            }
            // Copy so each view gets its own materials (geometry data stays shared).
            let copy = template?.clone()
            copy?.enumerateHierarchy { node, _ in node.geometry = node.geometry?.copy() as? SCNGeometry }
            DispatchQueue.main.async { completion(copy) }
        }
    }

    /// Makes the model Y-up, centred on the origin at floor level.
    private static func normalised(_ root: SCNNode) -> SCNNode {
        let container = SCNNode()
        container.addChildNode(root)
        var (lo, hi) = root.boundingBox
        if (hi.z - lo.z) > (hi.y - lo.y) * 1.5 {   // exported Z-up → rotate to Y-up
            root.eulerAngles.x = -.pi / 2
            (lo, hi) = container.boundingBox
        } else {
            (lo, hi) = container.boundingBox
        }
        root.position = SCNVector3(root.position.x - (lo.x + hi.x) / 2,
                                   root.position.y - lo.y,
                                   root.position.z - (lo.z + hi.z) / 2)
        let flat = SCNNode()
        flat.addChildNode(container)
        return flat
    }

    /// Muscle id for a mesh node: its own name or the nearest ancestor named "m_<id>".
    static func muscleId(of node: SCNNode) -> String {
        var n: SCNNode? = node
        while let current = n {
            if let name = current.name, name.hasPrefix("m_") { return String(name.dropFirst(2)) }
            n = current.parent
        }
        return "body"
    }
}

enum BodyView: String, CaseIterable, Identifiable {
    case front = "Front", side = "Side", back = "Back"
    var id: String { rawValue }
}

/// Interactive 3D body: drag to rotate, pinch to zoom. Primary muscles bright red, secondary dark red.
struct Muscle3DView: UIViewRepresentable {
    let primary: [String]
    let secondary: [String]
    let view: BodyView
    /// Changes whenever a view button is tapped, so tapping the same button again resets the camera.
    let viewToken: Int
    @Binding var loaded: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(Theme.card)
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.inertiaEnabled = true
        scnView.defaultCameraController.maximumVerticalAngle = 60
        scnView.defaultCameraController.minimumVerticalAngle = -30
        scnView.scene = SCNScene()
        context.coordinator.view = scnView

        MuscleModel.load { model in
            guard let model else { return }
            context.coordinator.install(model)
            context.coordinator.colour(primary: primary, secondary: secondary)
            context.coordinator.place(view: view, primary: primary, animated: false)
            loaded = true
        }
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        let c = context.coordinator
        guard c.model != nil else { return }
        if c.lastPrimary != primary || c.lastSecondary != secondary {
            c.colour(primary: primary, secondary: secondary)
        }
        if c.lastToken != viewToken {
            c.lastToken = viewToken
            c.place(view: view, primary: primary, animated: true)
        }
    }

    final class Coordinator {
        weak var view: SCNView?
        var model: SCNNode?
        var lastPrimary: [String] = []
        var lastSecondary: [String] = []
        var lastToken = 0
        private let camera = SCNNode()
        private var height: Float = 1.7
        /// Direction the body faces (from the centre towards the chest), in the horizontal plane.
        private var front = SCNVector3(0, 0, 1)

        func install(_ model: SCNNode) {
            guard let scene = view?.scene else { return }
            self.model = model
            scene.rootNode.addChildNode(model)
            let (lo, hi) = model.boundingBox
            height = hi.y - lo.y

            // Work out which way the body faces from where the chest sits relative to the body centre.
            var chest: SCNVector3?
            model.enumerateHierarchy { node, stop in
                if node.geometry != nil, MuscleModel.muscleId(of: node) == "chest" {
                    let (a, b) = node.boundingBox
                    chest = node.convertPosition(SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2), to: nil)
                    stop.pointee = true
                }
            }
            if let chest {
                let cx = chest.x, cz = chest.z
                let len = max(sqrt(cx * cx + cz * cz), 0.0001)
                front = SCNVector3(cx / len, 0, cz / len)
            }

            // Lights: soft ambient, warm key from the front-left, two cool rims from behind.
            func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ color: UIColor, at pos: SCNVector3?) {
                let l = SCNLight(); l.type = type; l.intensity = intensity; l.color = color
                let n = SCNNode(); n.light = l
                if let pos { n.position = pos; n.look(at: SCNVector3(0, height * 0.6, 0)) }
                scene.rootNode.addChildNode(n)
            }
            let h = height
            let side = SCNVector3(front.z, 0, -front.x)
            light(.ambient, 220, .white, at: nil)
            light(.directional, 900, UIColor(white: 1, alpha: 1),
                  at: SCNVector3(front.x * 2 - side.x * 1.5, h * 1.6, front.z * 2 - side.z * 1.5))
            light(.directional, 650, UIColor(red: 0.75, green: 0.82, blue: 1, alpha: 1),
                  at: SCNVector3(-front.x * 2 + side.x * 1.5, h * 1.2, -front.z * 2 + side.z * 1.5))
            light(.directional, 650, UIColor(red: 0.75, green: 0.82, blue: 1, alpha: 1),
                  at: SCNVector3(-front.x * 2 - side.x * 1.5, h * 1.2, -front.z * 2 - side.z * 1.5))

            let cam = SCNCamera()
            cam.fieldOfView = 30
            cam.zNear = 0.05
            cam.zFar = 50
            cam.wantsHDR = false
            camera.camera = cam
            scene.rootNode.addChildNode(camera)
            view?.pointOfView = camera
        }

        func colour(primary: [String], secondary: [String]) {
            lastPrimary = primary
            lastSecondary = secondary
            let p = Set(primary), s = Set(secondary)
            model?.enumerateHierarchy { node, _ in
                guard let geometry = node.geometry else { return }
                let id = MuscleModel.muscleId(of: node)
                let m = SCNMaterial()
                m.lightingModel = .physicallyBased
                m.metalness.contents = 0.0
                if p.contains(id) {
                    m.diffuse.contents = UIColor(red: 0.78, green: 0.06, blue: 0.12, alpha: 1)
                    m.emission.contents = UIColor(red: 0.25, green: 0.0, blue: 0.02, alpha: 1)
                    m.roughness.contents = 0.38
                } else if s.contains(id) {
                    m.diffuse.contents = UIColor(red: 0.42, green: 0.07, blue: 0.10, alpha: 1)
                    m.roughness.contents = 0.5
                } else {
                    m.diffuse.contents = UIColor(red: 0.46, green: 0.47, blue: 0.49, alpha: 1)
                    m.roughness.contents = 0.55
                }
                geometry.materials = [m]
            }
        }

        /// Frames the part of the body that matters for this exercise from the chosen side.
        func place(view: BodyView, primary: [String], animated: Bool) {
            let legs: Set<String> = ["quads", "hamstrings", "glutes", "adductors", "calves"]
            let core: Set<String> = ["abs", "obliques", "lower_back"]
            let set = Set(primary)
            let range: (Float, Float)
            if set.isEmpty { range = (0.0, 1.0) }
            else if set.isSubset(of: legs) { range = set.isSubset(of: ["calves"]) ? (0.0, 0.45) : (0.02, 0.62) }
            else if set.isSubset(of: core) { range = (0.36, 0.86) }
            else { range = (0.45, 1.0) }
            let lo = range.0, hi = range.1

            let target = SCNVector3(0, height * (lo + hi) / 2, 0)
            let dist = height * (hi - lo) * 2.6
            let frontAngle = atan2(front.x, front.z)
            let preferredBack = !set.isEmpty && set.isDisjoint(with: ["upper_chest", "chest", "front_delts", "side_delts",
                                                                     "biceps", "forearms", "abs", "obliques", "quads", "adductors"])
            let base: Float
            switch view {
            case .front: base = frontAngle - 0.3
            case .back: base = frontAngle + .pi + 0.3
            case .side: base = frontAngle + (preferredBack ? .pi * 0.75 : .pi * 0.5)
            }
            let pos = SCNVector3(target.x + sin(base) * dist, target.y + height * 0.03, target.z + cos(base) * dist)

            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.6 : 0
            camera.position = pos
            camera.look(at: target)
            SCNTransaction.commit()
            self.view?.defaultCameraController.target = target
        }
    }
}

/// 3D muscle viewer with Front / Side / Back buttons. Falls back to the rendered images if the model can't load.
struct MuscleViewer: View {
    let exercise: ExerciseDef
    @State private var bodyView: BodyView
    @State private var token = 0
    @State private var loaded = false

    init(exercise: ExerciseDef) {
        self.exercise = exercise
        _bodyView = State(initialValue: exercise.preferredSide == .back ? .back : .front)
    }

    private var hasModel: Bool { Bundle.main.url(forResource: "MuscleBody", withExtension: "usdz") != nil }

    var body: some View {
        if hasModel {
            VStack(spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    Muscle3DView(primary: exercise.primary, secondary: exercise.secondary,
                                 view: bodyView, viewToken: token, loaded: $loaded)
                        .frame(height: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if !loaded {
                        ProgressView().tint(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw")
                        Text("DRAG TO ROTATE · PINCH TO ZOOM")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(8)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                    .padding(10)
                    .allowsHitTesting(false)
                }
                .frame(height: 420)

                HStack(spacing: 8) {
                    ForEach(BodyView.allCases) { v in
                        Button {
                            Haptics.select()
                            bodyView = v
                            token += 1
                        } label: {
                            Text(v.rawValue.uppercased())
                                .font(.display(20))
                                .tracking(1.5)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(bodyView == v ? Color.white : Theme.textSecondary)
                                .background(bodyView == v ? Theme.accent : Theme.cardRaised,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 14) {
                    legend(Theme.accent, "Primary")
                    if !exercise.secondary.isEmpty { legend(Theme.accentDim, "Secondary") }
                    Spacer()
                }
            }
        } else {
            MuscleMapView(exercise: exercise)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textSecondary)
        }
    }
}
