import SwiftUI
import AVFoundation
import MealTrackerLocalization

/// Authorization is requested only when this explicitly presented scanner starts.
struct BarcodeScanner: UIViewControllerRepresentable {
    let copy: AppCopy
    let completion: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController(); controller.copy = copy; controller.completion = completion; return controller
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var copy = AppCopy(language: .sv)
    var completion: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "MealTracker.barcode.camera")
    private var delivered = false
    private var preview: AVCaptureVideoPreviewLayer?
    private var active = false
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    @objc private func background() { queue.async { [session] in if session.isRunning { session.stopRunning() } } }
    @objc private func foreground() { if active && !delivered && AVCaptureDevice.authorizationStatus(for: .video) == .authorized { configure() } }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); active = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async { guard let self, self.active else { return }; allowed ? self.configure() : self.message("cameraDenied") }
            }
        default: message("cameraDenied")
        }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); stop() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func stop() { active = false; queue.async { [session] in if session.isRunning { session.stopRunning() } } }
    private func message(_ key: String) {
        let label = UILabel(); label.text = copy.text(key); label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body); label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center; label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), label.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    }
    private func configure() {
        guard active, !delivered else { return }
        guard session.inputs.isEmpty else { queue.async { [session] in if !session.isRunning { session.startRunning() } }; return }
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { message("cameraUnavailable"); return }
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { message("cameraUnavailable"); return }
        session.addInput(input); session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13].filter { output.availableMetadataObjectTypes.contains($0) }
        let layer = AVCaptureVideoPreviewLayer(session: session); layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0); preview = layer; layer.frame = view.bounds
        queue.async { [session] in session.startRunning() }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard active, !delivered, let code = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).compactMap(BarcodeInput.normalized).first else { return }
        delivered = true; stop(); completion?(code)
    }
}
