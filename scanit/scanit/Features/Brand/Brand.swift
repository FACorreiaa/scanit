import RealityKit
import SwiftUI

/// Brand pieces from `brand/` (see brand/README.md). The mark and wordmark are vector assets with
/// light and dark variants; the mascot is a 3D illustration with a transparent background.
struct MascotView: View {
    var height: CGFloat = 180
    var body: some View {
        Image("Mascot")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// ScanBot in 3D (`Resources/scanbot.usdz`, converted from `brand/3d/scanbot.glb`), turning slowly like
/// the website hero. Shows the still `MascotView` while the model loads, if it fails to load, and
/// always when Reduce Motion is on.
struct Mascot3DView: View {
    var height: CGFloat = 220
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.loading
    @State private var spin: EventSubscription?

    private enum Phase { case loading, shown, failed }

    var body: some View {
        if reduceMotion || phase == .failed {
            MascotView(height: height)
        } else {
            ZStack {
                MascotView(height: height)
                    .opacity(phase == .shown ? 0 : 1)
                RealityView { content in
                    guard let bot = try? await Entity(named: "scanbot") else {
                        phase = .failed
                        return
                    }
                    // Centre the model on a pivot and scale it to a 1 m box so the camera framing
                    // doesn't depend on the exporter's units.
                    let bounds = bot.visualBounds(relativeTo: nil)
                    let size = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
                    guard size > 0 else {
                        phase = .failed
                        return
                    }
                    bot.position = -bounds.center
                    let pivot = Entity()
                    pivot.addChild(bot)
                    pivot.scale = SIMD3(repeating: 1 / size)
                    // Same starting angle as the web (camera-orbit 20deg): a three-quarter view.
                    pivot.orientation = simd_quatf(angle: -.pi / 9, axis: [0, 1, 0])
                    content.add(pivot)

                    let camera = PerspectiveCamera()
                    camera.camera.fieldOfViewInDegrees = 30
                    camera.look(at: .zero, from: [0, 0.2, 2.1], relativeTo: nil)
                    content.add(camera)

                    let key = DirectionalLight()
                    key.light.intensity = 2_500
                    key.look(at: .zero, from: [1, 2, 2], relativeTo: nil)
                    content.add(key)

                    // ~12° a second, matching rotation-per-second on the web.
                    spin = content.subscribe(to: SceneEvents.Update.self) { event in
                        let turn = simd_quatf(angle: Float(event.deltaTime) * .pi / 15, axis: [0, 1, 0])
                        pivot.orientation = turn * pivot.orientation
                    }
                    withAnimation(.easeOut(duration: 0.5)) { phase = .shown }
                }
                .opacity(phase == .shown ? 1 : 0)
            }
            .frame(width: height * 1.2, height: height)
            .accessibilityHidden(true)
        }
    }
}

#Preview("Mascot 3D") {
    Mascot3DView()
}

#Preview("Mascot") {
    HStack(spacing: 32) {
        MascotView()
        MascotView().environment(\.colorScheme, .dark).padding().background(.black)
    }
    .padding()
}
