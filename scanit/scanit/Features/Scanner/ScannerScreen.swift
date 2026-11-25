import ScanItCore
import SwiftData
import SwiftUI

/// Full-screen scanner (`DESIGN.md` §4, BACKLOG IOS-005, IOS-007). Camera fills the screen and the
/// total stays visible in a top HUD. Scanning is the whole gesture: a product whose price is
/// remembered for this store is added on the barcode lock, and otherwise the shelf label is read
/// without a tap and added when it shows one clear price. Each of those adds shows a banner with
/// Undo and Edit. The confirm sheet is left for what cannot be decided alone: a label with
/// several prices, or a price that has to be typed. The scanner stays open throughout.
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
    /// The last item added without a confirm step, while its banner is up.
    @State private var added: AddedItem?
    @State private var editing: CartItemSelection?

    /// Stills taken before giving up on a label; the first is taken on the barcode lock.
    private static let priceReadAttempts = 3
    private static let priceReadRetryDelay = Duration.milliseconds(800)
    private static let bannerDuration = Duration.seconds(6)

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
                offer: labelOffer,
                elsewhere: cheapestElsewhere(for: detected)
            ) { quantity, price, priceSource in
                add(detected, quantity: quantity, price: price, source: priceSource, offer: labelOffer)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editing) { selection in
            EditItemSheet(item: selection.item, currency: session.currency)
                .presentationDetents([.medium])
        }
        .task(id: added?.id) {
            guard let shown = added?.id else { return }
            try? await Task.sleep(for: Self.bannerDuration)
            if !Task.isCancelled, added?.id == shown { added = nil }
        }
        .animation(.snappy, value: added?.id)
        .sensoryFeedback(trigger: pending?.id ?? awaitingPrice?.id) { _, new in new == nil ? nil : .impact(weight: .light) }
        .sensoryFeedback(trigger: added?.id) { _, new in new == nil ? nil : .success }
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

    private var isBusy: Bool { pending != nil || awaitingPrice != nil || editing != nil }

    private func cheapestElsewhere(for detected: DetectedCode) -> PriceElsewhere? {
        PriceMemory.cheapestElsewhere(
            code: detected.code, store: session.store, currency: session.currency, context: context
        )
    }

    private func rememberedPrice(for detected: DetectedCode) -> RememberedPrice? {
        PriceMemory.lookup(code: detected.code.value, store: session.store, context: context)
    }

    private func handleLock(_ detected: DetectedCode) {
        lockedAt = .now
        priceReadFailed = false
        if let remembered = rememberedPrice(for: detected), remembered.price.currency == session.currency {
            add(detected, quantity: 1, price: remembered.price, source: .remembered, seenAt: remembered.observedAt)
        } else if source.readsShelfPrices {
            added = nil
            awaitingPrice = detected
            readPrice()
        } else {
            pending = detected
        }
    }

    /// Reads the shelf label, starting on the barcode lock and trying again for a moment while
    /// the camera settles on it. One clear price is added; several are left to the confirm sheet.
    private func readPrice() {
        guard let detected = awaitingPrice, !isReadingPrice else { return }
        isReadingPrice = true
        priceReadFailed = false
        Task {
            defer { isReadingPrice = false }
            var offer: LabelPriceOffer?
            for attempt in 0..<Self.priceReadAttempts {
                if attempt > 0 { try? await Task.sleep(for: Self.priceReadRetryDelay) }
                // The product was cancelled, or its price typed, while the label was being read.
                guard awaitingPrice?.id == detected.id else { return }
                offer = try? await labelOffer(for: detected)
                if let offer, !offer.isEmpty { break }
            }
            guard awaitingPrice?.id == detected.id else { return }
            guard let offer, !offer.isEmpty else {
                priceReadFailed = true
                return
            }
            awaitingPrice = nil
            if let prefill = offer.prefill, offer.candidates.isEmpty {
                add(detected, quantity: 1, price: prefill, source: .ocr, offer: offer)
            } else {
                labelOffer = offer
                pending = detected
            }
        }
    }

    /// Adds to the cart. An add that skipped the confirm sheet (`.remembered` or `.ocr` straight
    /// from the scan) shows the banner; one confirmed in the sheet needs no second look.
    private func add(
        _ detected: DetectedCode, quantity: Int, price: Money, source priceSource: PriceSource,
        offer: LabelPriceOffer? = nil, seenAt: Date? = nil
    ) {
        let wasConfirmed = pending?.id == detected.id
        trackLabelRead(source: priceSource, offer: offer)
        let elsewhere = cheapestElsewhere(for: detected)
        guard let item = sessions.addItem(
            code: detected.code, quantity: quantity, unitPriceMinor: price.amountMinor,
            priceSource: priceSource, symbology: detected.symbology
        ) else { return }
        // Name and photo arrive later, or when the network is back; the scan never waits.
        enricher.enqueue(item)
        Task { await enricher.flush() }
        guard !wasConfirmed else {
            added = nil
            return
        }
        let shown = AddedItem(
            item: item, price: price, source: priceSource, seenAt: seenAt,
            elsewhere: elsewhere.flatMap { $0.isCheaper(than: price) ? $0 : nil }
        )
        added = shown
        AccessibilityNotification.Announcement("Added, \(price.formatted())").post()
    }

    private func undoAdd(_ shown: AddedItem) {
        sessions.undoAdd(shown.item)
        added = nil
    }

    private func editAdded(_ shown: AddedItem) {
        editing = CartItemSelection(item: shown.item)
        added = nil
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
    private func trackLabelRead(source priceSource: PriceSource, offer: LabelPriceOffer?) {
        guard source.readsShelfPrices, priceSource != .remembered, let lockedAt else { return }
        let outcome = PriceSourceResolver.outcome(
            source: priceSource, prefill: offer?.prefill, labelCandidates: offer?.candidates ?? []
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
        } else if let added {
            AddedItemBanner(
                added: added,
                name: added.item.productName ?? added.item.scannedCode.displayValue,
                onUndo: { undoAdd(added) },
                onEdit: { editAdded(added) }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            hint
        }
    }

    private func priceStep(_ detected: DetectedCode) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(priceReadFailed ? "Couldn't read a price" : "Reading the shelf price…")
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
                    Label("Try again", systemImage: "text.viewfinder")
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

/// Shown before the system prompt: we get one chance at it (`DESIGN.md` → First launch). The
/// button says "Continue", never "Allow": App Review rejects a primer that steers the answer
/// (guideline 5.1.1(iv), 2026-11-20).
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
            Button("Continue", action: onAllow)
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
