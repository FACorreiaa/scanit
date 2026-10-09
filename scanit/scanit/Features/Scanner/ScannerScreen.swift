import ScanItCore
import SwiftData
import SwiftUI

/// Full-screen scanner (`DESIGN.md` §4, BACKLOG IOS-005). Camera fills the screen, the total
/// stays visible in a top HUD, and each barcode lock opens the confirm sheet. The scanner stays
/// open after an add so the next product can be scanned straight away.
struct ScannerScreen: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(ProductEnricher.self) private var enricher
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let session: ShoppingSession

    @State private var source = BarcodeSource.current
    @State private var access = CameraAccess.current
    @State private var pending: DetectedCode?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            camera
        }
        .overlay(alignment: .top) { hud }
        .overlay(alignment: .bottom) { hint }
        .sheet(item: $pending) { detected in
            ConfirmItemSheet(
                detected: detected,
                currency: session.currency,
                remembered: PriceMemory.lookup(code: detected.code.value, store: session.store, context: context),
                product: enricher.cached(detected.code)
            ) { quantity, price, priceSource in
                guard let item = sessions.addItem(
                    code: detected.code, quantity: quantity, unitPriceMinor: price.amountMinor,
                    priceSource: priceSource, symbology: detected.symbology
                ) else { return }
                // Name and photo arrive later, or when the network is back; the scan never waits.
                enricher.enqueue(item)
                Task { await enricher.flush() }
            }
            .presentationDetents([.medium, .large])
        }
        .sensoryFeedback(trigger: pending?.id) { _, new in new == nil ? nil : .impact(weight: .light) }
        .sensoryFeedback(trigger: sessions.feedback) { _, event in
            switch event?.kind {
            case .warning: .warning
            case .error: .error
            case nil: nil
            }
        }
        .statusBarHidden()
    }

    // MARK: - Camera

    @ViewBuilder
    private var camera: some View {
        switch (access, source) {
        case (_, .simulated(let codes)):
            SimulatedScanner(codes: codes) { pending = $0 }
        case (.notDetermined, _):
            CameraPrimer { Task { access = await CameraAccess.request() } }
        case (.denied, _):
            ContentUnavailableView {
                Label("Camera is off", systemImage: "camera.badge.ellipsis")
            } description: {
                Text("ScanIt needs the camera to read barcodes. Turn it on in Settings.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            }
            .environment(\.colorScheme, .dark)
        case (.authorized, .dataScanner):
            DataScannerView(isPaused: pending != nil) { pending = $0 }
                .ignoresSafeArea()
        case (.authorized, .capture):
            CaptureBarcodeView(isPaused: pending != nil) { pending = $0 }
                .ignoresSafeArea()
        }
    }

    // MARK: - Overlays

    private var hud: some View {
        HStack(alignment: .top, spacing: 12) {
            TripTotalHeader(total: session.total, limit: session.limit, status: session.limitStatus, compact: true)
                .frame(maxWidth: .infinity)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close scanner")
            .accessibilityIdentifier("closeScanner")
        }
        .padding(16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var hint: some View {
        if access == .authorized, pending == nil {
            Text("Point at a barcode")
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: .capsule)
                .environment(\.colorScheme, .dark)
                .padding(.bottom, 32)
        }
    }
}

/// Shown before the system prompt: we get one chance at it (`DESIGN.md` → First launch).
private struct CameraPrimer: View {
    let onAllow: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 56, weight: .light))
            VStack(spacing: 8) {
                Text("Scan as you shop")
                    .font(.title2.weight(.semibold))
                Text("ScanIt uses the camera to read barcodes and shelf prices. Nothing is recorded or uploaded.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button("Allow camera", action: onAllow)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
        .environment(\.colorScheme, .dark)
    }
}

/// UI-test stand-in for the camera: one button per code in `UITEST_SCAN_CODES`.
private struct SimulatedScanner: View {
    let codes: [String]
    let onDetect: (DetectedCode) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(codes, id: \.self) { code in
                Button("Simulate scan \(code)") {
                    onDetect(DetectedCode(payload: code, symbology: .ean13))
                }
                .buttonStyle(.bordered)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
