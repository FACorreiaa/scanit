import AVFoundation
import ScanItCore
import SwiftUI
import Vision
import VisionKit

/// One barcode lock, normalised. A fresh `id` per detection so `.sheet(item:)` and haptics fire.
struct DetectedCode: Identifiable, Equatable {
    let id = UUID()
    let code: ScannedCode
    let symbology: Symbology

    init(payload: String, symbology: Symbology) {
        self.code = BarcodeNormalizer.normalize(payload: payload, symbology: symbology)
        self.symbology = symbology
    }
}

/// Which camera pipeline this device gets.
enum BarcodeSource {
    /// A12+: VisionKit DataScanner (also does shelf text later, BACKLOG IOS-007).
    case dataScanner
    /// Older or restricted devices: plain AVFoundation barcode reading, price typed by hand.
    case capture
    /// UI tests: buttons that emit the codes in `UITEST_SCAN_CODES`.
    case simulated([String])

    @MainActor static var current: BarcodeSource {
        let info = ProcessInfo.processInfo
        if info.arguments.contains("-ui-testing") {
            let codes = info.environment["UITEST_SCAN_CODES"]?.split(separator: ",").map(String.init) ?? []
            return .simulated(codes)
        }
        return DataScannerViewController.isSupported ? .dataScanner : .capture
    }
}

// MARK: - VisionKit

struct DataScannerView: UIViewControllerRepresentable {
    let isPaused: Bool
    let onDetect: (DetectedCode) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onDetect = onDetect
        context.coordinator.isPaused = isPaused
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDetect: onDetect)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onDetect: (DetectedCode) -> Void
        var isPaused = false

        init(onDetect: @escaping (DetectedCode) -> Void) {
            self.onDetect = onDetect
        }

        // `didAdd` fires once when a code enters the frame. A code that stays in view after the
        // confirm sheet closes does not fire again, which prevents accidental double adds.
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            emitFirstBarcode(in: addedItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            emitFirstBarcode(in: [item])
        }

        private func emitFirstBarcode(in items: [RecognizedItem]) {
            guard !isPaused else { return }
            for item in items {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    onDetect(DetectedCode(payload: payload, symbology: Symbology(barcode.observation.symbology)))
                    return
                }
            }
        }
    }
}

nonisolated extension Symbology {
    init(_ vision: VNBarcodeSymbology) {
        switch vision {
        case .ean13: self = .ean13
        case .ean8: self = .ean8
        case .upce: self = .upce
        case .qr: self = .qr
        default: self = .code128 // the normaliser still accepts a valid numeric GTIN
        }
    }

    init(_ capture: AVMetadataObject.ObjectType) {
        switch capture {
        case .ean13: self = .ean13
        case .ean8: self = .ean8
        case .upce: self = .upce
        case .qr: self = .qr
        default: self = .code128
        }
    }
}

// MARK: - AVFoundation fallback

struct CaptureBarcodeView: UIViewControllerRepresentable {
    let isPaused: Bool
    let onDetect: (DetectedCode) -> Void

    func makeUIViewController(context: Context) -> CaptureBarcodeController {
        CaptureBarcodeController()
    }

    func updateUIViewController(_ controller: CaptureBarcodeController, context: Context) {
        controller.onDetect = onDetect
        controller.isPaused = isPaused
    }
}

final class CaptureBarcodeController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetect: ((DetectedCode) -> Void)?
    var isPaused = false
    private(set) var hasCamera = false

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastPayload: String?
    private var lastDetectionAt = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .qr]
        output.metadataObjectTypes = wanted.filter(output.availableMetadataObjectTypes.contains)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
        hasCamera = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard hasCamera else { return }
        nonisolated(unsafe) let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        nonisolated(unsafe) let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.lazy.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let payload = object.stringValue
        else { return }
        let symbology = Symbology(object.type)
        // Delegate queue is `.main`.
        MainActor.assumeIsolated { handle(payload: payload, symbology: symbology) }
    }

    /// AVFoundation reports a code on every frame; only a new code, or the same one after a
    /// pause of 2 s, counts as a scan.
    private func handle(payload: String, symbology: Symbology) {
        guard !isPaused else { return }
        let now = Date()
        if payload == lastPayload, now.timeIntervalSince(lastDetectionAt) < 2 {
            lastDetectionAt = now
            return
        }
        lastPayload = payload
        lastDetectionAt = now
        onDetect?(DetectedCode(payload: payload, symbology: symbology))
    }
}

// MARK: - Camera permission

enum CameraAccess {
    case notDetermined, authorized, denied

    static var current: CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func request() async -> CameraAccess {
        await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
    }
}
