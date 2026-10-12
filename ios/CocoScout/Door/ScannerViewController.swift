import AVFoundation
import Combine
import SwiftUI
import UIKit

/// The door's camera: full screen, scanning one ticket after another until
/// it's closed. It only reads codes. Each one goes back to the door page,
/// which checks it in exactly as a tap on the list would, and the page's
/// answer comes back here as a big colored card with a sound and a buzz.
///
/// Reads QR tickets and the barcodes other ticket sites print. Ignores the
/// same code for a few seconds (the camera sees it many times a second), has
/// a flashlight for dark lobbies, and keeps the screen awake while open.
/// With no camera (the Simulator) or no permission, it takes a typed code.
final class ScannerViewController: UIViewController {
    enum Event {
        case code(String)
        case undo(ticketID: String)
        case fulfill(url: String)
        case closed
    }

    var onEvent: (Event) -> Void = { _ in }

    private let model: ScannerModel
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.cocoscout.door-scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var camera: AVCaptureDevice?
    private let feedback = DoorFeedback()
    private var lastCode: (code: String, at: Date)?
    private var waitingTimer: Timer?
    private var hideTimer: Timer?

    private static let repeatWindow: TimeInterval = 4
    private static let resultSeconds: TimeInterval = 8

    init(title: String, subtitle: String) {
        model = ScannerModel(title: title, subtitle: subtitle)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        model.onClose = { [weak self] in self?.close() }
        model.onTorch = { [weak self] in self?.toggleTorch() }
        model.onCode = { [weak self] code in self?.found(code, typed: true) }
        model.onUndo = { [weak self] ticketID in self?.onEvent(.undo(ticketID: ticketID)) }
        model.onFulfill = { [weak self] url in
            self?.model.delivering.insert(url)
            self?.onEvent(.fulfill(url: url))
        }

        let overlay = UIHostingController(rootView: ScannerOverlay(model: model))
        overlay.view.backgroundColor = .clear
        addChild(overlay)
        overlay.view.frame = view.bounds
        overlay.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay.view)
        overlay.didMove(toParent: self)

        startCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        KeepAwake.hold("door-scanner")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        KeepAwake.release("door-scanner")
        waitingTimer?.invalidate()
        hideTimer?.invalidate()
        sessionQueue.async { [session] in session.stopRunning() }
    }

    // MARK: Results from the door page

    func show(_ result: DoorResult) {
        waitingTimer?.invalidate()
        model.waiting = false
        model.delivering.removeAll()
        withAnimation(.easeOut(duration: 0.15)) { model.result = result }
        if !result.quiet { feedback.play(result.tone) }

        // Gone after a few seconds, unless something is still to hand over.
        hideTimer?.invalidate()
        guard !result.waitingOnDelivery else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.resultSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                withAnimation(.easeIn(duration: 0.2)) { self?.model.result = nil }
            }
        }
    }

    // MARK: Codes

    private func found(_ raw: String, typed: Bool = false) {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !model.waiting else { return }
        if !typed, let last = lastCode, last.code == code, Date().timeIntervalSince(last.at) < Self.repeatWindow { return }
        lastCode = (code, Date())

        model.waiting = true
        if typed { model.typedCode = "" }
        onEvent(.code(code))

        // Never stuck: if the page doesn't answer, scanning picks up again.
        waitingTimer?.invalidate()
        waitingTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.waiting = false }
        }
    }

    private func close() {
        setTorch(on: false)
        dismiss(animated: true) { [onEvent] in onEvent(.closed) }
    }

    // MARK: Camera

    private func startCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { [weak self] in
                    if granted { self?.configureCamera() } else { self?.model.camera = .denied }
                }
            }
        default:
            model.camera = .denied
        }
    }

    private func configureCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            model.camera = .unavailable
            return
        }

        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        session.sessionPreset = .high
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            model.camera = .unavailable
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // QR tickets, plus the barcodes other ticket sites print.
        let wanted: [AVMetadataObject.ObjectType] = [.qr, .aztec, .pdf417, .dataMatrix, .code128, .code39, .ean13]
        output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
        session.commitConfiguration()

        camera = device
        focusClose(device)

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        model.hasTorch = device.hasTorch
        model.camera = .running
        sessionQueue.async { [session] in session.startRunning() }
    }

    /// Phones held close to the lens: focus near, and zoom in a little on
    /// cameras that can't focus that close (Apple's AVCamBarcode approach), so
    /// a code on a phone screen fills the frame while still in focus.
    private func focusClose(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }

        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }

        let minimumFocus = Float(device.minimumFocusDistance) // millimeters, -1 when unknown
        guard minimumFocus > 0 else { return }
        let halfView = device.activeFormat.videoFieldOfView / 2 * .pi / 180
        let codeMillimeters: Float = 25 / 0.6 // a 25 mm code filling 60% of the frame
        let codeDistance = codeMillimeters / tan(halfView)
        guard codeDistance < minimumFocus else { return }
        let zoom = min(CGFloat(minimumFocus / codeDistance), device.activeFormat.videoMaxZoomFactor, 3)
        device.videoZoomFactor = max(1, zoom)
    }

    private func toggleTorch() {
        setTorch(on: camera?.torchMode != .on)
    }

    private func setTorch(on: Bool) {
        guard let camera, camera.hasTorch, (try? camera.lockForConfiguration()) != nil else { return }
        camera.torchMode = on ? .on : .off
        camera.unlockForConfiguration()
        model.torchOn = on
    }
}

extension ScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        guard let code = codes.first else { return }
        // Delivered on the main queue (setMetadataObjectsDelegate above).
        MainActor.assumeIsolated { found(code) }
    }
}

/// What the scanner screen shows; the overlay draws it.
@MainActor
final class ScannerModel: ObservableObject {
    enum Camera {
        case starting
        case running
        case unavailable
        case denied
    }

    let title: String
    let subtitle: String
    @Published var camera: Camera = .starting
    @Published var hasTorch = false
    @Published var torchOn = false
    @Published var result: DoorResult?
    /// A code went to the page and its answer isn't back yet.
    @Published var waiting = false
    /// Delivered taps on their way.
    @Published var delivering = Set<String>()
    @Published var typedCode = ""

    var onClose: () -> Void = {}
    var onTorch: () -> Void = {}
    var onCode: (String) -> Void = { _ in }
    var onUndo: (String) -> Void = { _ in }
    var onFulfill: (String) -> Void = { _ in }

    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}
