import SwiftUI
import AVFoundation

// MARK: - QRScannerView

struct QRScannerView: View {
    let onScan: (GatewayConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var parseError: String? = nil
    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch cameraPermission {
                case .authorized:
                    scannerContent
                case .notDetermined:
                    Color.black.ignoresSafeArea()
                        .task {
                            let granted = await AVCaptureDevice.requestAccess(for: .video)
                            cameraPermission = granted ? .authorized : .denied
                        }
                default:
                    permissionDeniedView
                }
            }
            .navigationTitle("Scan Gateway QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.clawAccent)
                }
            }
        }
    }

    private var scannerContent: some View {
        ZStack {
            CameraPreview { code in
                if let config = parse(code) {
                    onScan(config)
                } else {
                    parseError = "Not a valid OpenClaw QR code. Try: openclaw://gateway?host=…"
                    // Reset after 2 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run { parseError = nil }
                    }
                }
            }
            .ignoresSafeArea()

            // Viewfinder
            VStack(spacing: 20) {
                Spacer()
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(parseError != nil ? Color.clawDanger : Color.clawAccent, lineWidth: 2.5)
                    .frame(width: 240, height: 240)
                    .shadow(color: (parseError != nil ? Color.clawDanger : Color.clawAccent).opacity(0.4), radius: 12)

                if let err = parseError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(Color.clawDanger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    Text("Point at your gateway's QR code")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted)
            Text("Camera Access Required")
                .font(.headline)
                .foregroundStyle(Color.clawTextStrong)
            Text("Enable camera access in Settings to scan QR codes.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .tint(Color.clawAccent)
        }
    }

    // MARK: - QR parsing

    // Supported formats:
    //   openclaw://gateway?host=X&port=Y&scheme=wss&name=Z
    //   ws://host:port
    //   wss://host:port
    private func parse(_ string: String) -> GatewayConfig? {
        guard let url = URL(string: string),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        if url.scheme == "openclaw", url.host == "gateway" {
            let params = Dictionary(
                (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
                uniquingKeysWith: { first, _ in first }
            )
            guard let host = params["host"], !host.isEmpty else { return nil }
            let port = Int(params["port"] ?? "18789") ?? 18789
            let isSecure = (params["scheme"] ?? "wss") != "ws"
            let name = params["name"] ?? host
            return GatewayConfig(name: name, host: host, port: port, isSecure: isSecure)
        }

        if url.scheme == "ws" || url.scheme == "wss", let host = url.host {
            let isSecure = url.scheme == "wss"
            let port = url.port ?? (isSecure ? 443 : 18789)
            return GatewayConfig(name: host, host: host, port: port, isSecure: isSecure)
        }

        return nil
    }
}

// MARK: - CameraPreview

private struct CameraPreview: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeUIView(context: Context) -> CameraView {
        CameraView(onCode: onCode)
    }

    func updateUIView(_ uiView: CameraView, context: Context) {}
}

private final class CameraView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let onCode: (String) -> Void
    private var lastScanned: String? = nil
    private var resetTimer: Timer?

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(frame: .zero)
        setupSession()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        layer.addSublayer(preview)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue,
              value != lastScanned else { return }

        lastScanned = value
        onCode(value)

        // Allow re-scanning different codes after 2 seconds
        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            self?.lastScanned = nil
        }
    }
}
