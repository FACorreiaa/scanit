import ScanItCore
import SwiftData
import SwiftUI

/// Full-screen scanner (`DESIGN.md` §4, BACKLOG IOS-005, IOS-007). Camera fills the screen and the
/// total stays visible in a top HUD. A barcode lock opens the confirm sheet when the price is
/// remembered; otherwise the shelf price is read first, with typing it always one tap away. The
/// scanner stays open after an add so the next product can be scanned straight away.
struct ScannerScreen: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(ProductEnricher.self) private var enricher
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.analytics) private var analytics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let session: ShoppingSession

    @State private var source = BarcodeSource.current
    @State private var access = CameraAccess.current
    @State private var pending: DetectedCode?
    /// Locked on a product with no remembered price: waiting for its shelf price.
    @State private var awaitingPrice: DetectedCode?
    @State private var isReadingPrice = false
    @State private var priceReadFailed = false
    @State private var labelOffer: LabelPriceOffer?
    @State private var lockedAt: Date?
    @State private var scannerCamera = ScannerCamera()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            camera
        }
        .overlay(alignment: .top) { hud }
        .overlay(alignment: .bottom) { bottomOverlay }
        .sheet(item: $pending, onDismiss: { labelOffer = nil }) { detected in
            ConfirmItemSheet(
                detected: detected,
                currency: session.currency,
                remembered: rememberedPrice(for: detected),
                product: enricher.cached(detected.code),
                offer: labelOffer
            ) { quantity, price, priceSource in
                trackLabelRead(source: priceSource, price: price)
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
        .sensoryFeedback(trigger: pending?.id ?? awaitingPrice?.id) { _, new in new == nil ? nil : .impact(weight: .light) }
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
            SimulatedScanner(codes: codes, onDetect: handleLock)
        case (.notDetermined, _):
            CameraPrimer { Task { access = await CameraAccess.request() } }
        case (.denied, _):
            ContentUnavailableView {
                Label("Camera is off", systemImage: "camera.badge.ellipsis")
            } description: {
                Text("ScanItNow needs the camera to read barcodes. Turn it on in Settings.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            }
            .environment(\.colorScheme, .dark)
        case (.authorized, .dataScanner):
            DataScannerView(isPaused: isBusy, camera: scannerCamera, onDetect: handleLock)
                .ignoresSafeArea()
        case (.authorized, .capture):
            CaptureBarcodeView(isPaused: isBusy, onDetect: handleLock)
                .ignoresSafeArea()
        }
    }

    // MARK: - Price step

    private var isBusy: Bool { pending != nil || awaitingPrice != nil }

    private func rememberedPrice(for detected: DetectedCode) -> RememberedPrice? {
        PriceMemory.lookup(code: detected.code.value, store: session.store, context: context)
    }

    private func handleLock(_ detected: DetectedCode) {
        lockedAt = .now
        priceReadFailed = false
        let isRemembered = rememberedPrice(for: detected)?.price.currency == session.currency
        if source.readsShelfPrices, !isRemembered {
            awaitingPrice = detected
        } else {
            pending = detected
        }
    }

    private func readPrice() {
        guard let detected = awaitingPrice, !isReadingPrice else { return }
        isReadingPrice = true
        priceReadFailed = false
        Task {
            defer { isReadingPrice = false }
            let offer = try? await labelOffer(for: detected)
            // The product was cancelled while the still was being read.
            guard awaitingPrice?.id == detected.id else { return }
            guard let offer, !offer.isEmpty else {
                priceReadFailed = true
                return
            }
            labelOffer = offer
            pending = detected
            awaitingPrice = nil
        }
    }

    private func labelOffer(for detected: DetectedCode) async throws -> LabelPriceOffer {
        if case .simulated = source {
            let text = ProcessInfo.processInfo.environment["UITEST_SHELF_TEXT"] ?? ""
            return ShelfPriceReader.offer(fromTestText: text, currency: session.currency)
        }
        let photo = try await scannerCamera.photo()
        return try await ShelfPriceReader.offer(from: photo, currency: session.currency, barcodePayload: detected.payload)
    }

    private func typePrice() {
        pending = awaitingPrice
        awaitingPrice = nil
    }

    /// One event per item that went through the price step. No amounts (`AnalyticsEvent`).
    private func trackLabelRead(source priceSource: PriceSource, price: Money) {
        guard source.readsShelfPrices, priceSource != .remembered, let lockedAt else { return }
        let outcome = PriceSourceResolver.outcome(
            source: priceSource, prefill: labelOffer?.prefill, labelCandidates: labelOffer?.candidates ?? []
        )
        analytics.track(.priceOCRResult(outcome: outcome, ms: Int(Date.now.timeIntervalSince(lockedAt) * 1000)))
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
    private var bottomOverlay: some View {
        if let awaitingPrice {
            priceStep(awaitingPrice)
        } else {
            hint
        }
    }

    private func priceStep(_ detected: DetectedCode) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(priceReadFailed ? "Couldn't read a price" : "Point at the shelf price")
                        .font(.headline)
                        .accessibilityIdentifier("priceStepTitle")
                    Text(priceReadFailed ? "Move closer and try again, or type it." : detected.code.displayValue)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel", systemImage: "xmark") { awaitingPrice = nil }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .tint(.white)
                    .accessibilityIdentifier("cancelPriceStep")
            }
            priceStepLayout { priceStepButtons }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .environment(\.colorScheme, .dark)
    }

    /// Side by side, stacked when large text would squeeze the labels.
    private var priceStepLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }

    @ViewBuilder
    private var priceStepButtons: some View {
        Button(action: typePrice) {
            Text("Type it").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.white)
        .accessibilityIdentifier("typePrice")

        Button(action: readPrice) {
            Group {
                if isReadingPrice {
                    ProgressView()
                } else {
                    Label("Read price", systemImage: "text.viewfinder")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isReadingPrice)
        .accessibilityIdentifier("readPrice")
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
            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Scan as you shop")
                    .font(.title2.weight(.semibold))
                Text("ScanItNow uses the camera to read barcodes and shelf prices. Nothing is recorded or uploaded.")
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

    /// Screenshot mode (`UITEST_AUTOSCAN=<code>`): no test buttons, a dark camera-like backdrop,
    /// and one automatic scan, so App Store captures show the real confirm sheet over the scanner.
    private let autoScan = ProcessInfo.processInfo.environment["UITEST_AUTOSCAN"]
    @State private var didAutoScan = false

    var body: some View {
        if let autoScan {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .task {
                    guard !didAutoScan else { return }
                    didAutoScan = true
                    try? await Task.sleep(for: .milliseconds(600))
                    onDetect(DetectedCode(payload: autoScan, symbology: .ean13))
                }
        } else {
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
}
