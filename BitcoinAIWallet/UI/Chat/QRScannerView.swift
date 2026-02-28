import SwiftUI
import AVFoundation

// MARK: - QRScannerView
// Camera-based QR code scanner presented as a sheet.
// Scans Bitcoin addresses and BIP21 URIs, parses them,
// and returns the result to the caller.
//
// Supports:
//   - Plain Bitcoin addresses (bc1q..., bc1p..., 1..., 3...)
//   - BIP21 URIs: bitcoin:address?amount=X&label=Y
//
// Platform: iOS 17.0+
// Frameworks: SwiftUI, AVFoundation

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    @State private var errorMessage: String?
    @State private var hasScanned = false

    var body: some View {
        ZStack {
            // Camera preview
            QRCameraPreview(onCodeDetected: handleDetectedCode)
                .ignoresSafeArea()

            // Scanner overlay
            scannerOverlay

            // Top bar
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: AppIcons.close)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)
                }

                Spacer()
            }

            // Error message
            if let error = errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(.white)
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.md)
                        .background(
                            Capsule().fill(AppColors.error.opacity(0.9))
                        )
                        .padding(.bottom, 80)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Scanner Overlay

    private var scannerOverlay: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.65
            let rect = CGRect(
                x: (geometry.size.width - size) / 2,
                y: (geometry.size.height - size) / 2 - 40,
                width: size,
                height: size
            )

            ZStack {
                // Dimmed background with cutout
                Color.black.opacity(0.5)
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .frame(width: size, height: size)
                            .position(x: rect.midX, y: rect.midY)
                    }

                // Viewfinder corners
                ViewfinderCorners(rect: rect)

                // Title text
                VStack {
                    Text(L10n.Scanner.title)
                        .font(AppTypography.headingSmall)
                        .foregroundColor(.white)
                        .padding(.top, rect.minY - 50)

                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Code Handling

    private func handleDetectedCode(_ code: String) {
        guard !hasScanned else { return }
        hasScanned = true

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsed = BIP21Parser.parse(trimmed) {
            // Build send command from BIP21 URI
            var command = "send"
            if let amount = parsed.amount { command += " \(amount) BTC" }
            command += " to \(parsed.address)"
            HapticManager.success()
            onScan(command)
            dismiss()
        } else {
            // Check if it's a plain Bitcoin address
            let validator = AddressValidator()
            if validator.isValid(trimmed) {
                HapticManager.success()
                onScan(trimmed)
                dismiss()
            } else {
                // Not a valid Bitcoin QR code
                HapticManager.error()
                hasScanned = false
                withAnimation {
                    errorMessage = L10n.Scanner.error
                }
                // Clear error after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        errorMessage = nil
                    }
                }
            }
        }
    }
}

// MARK: - BIP21Parser

/// Parses BIP21 Bitcoin URIs into components.
///
/// Format: `bitcoin:<address>?amount=<amount>&label=<label>&message=<message>`
struct BIP21Parser {

    struct ParsedURI {
        let address: String
        var amount: String?
        var label: String?
        var message: String?
    }

    /// Parse a BIP21 URI string.
    /// Returns nil if the string is not a valid BIP21 URI.
    static func parse(_ uri: String) -> ParsedURI? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must start with "bitcoin:"
        let lowered = trimmed.lowercased()
        guard lowered.hasPrefix("bitcoin:") else { return nil }

        // Remove the scheme
        let afterScheme = String(trimmed.dropFirst("bitcoin:".count))

        // Split address from query parameters
        let parts = afterScheme.split(separator: "?", maxSplits: 1)
        let address = String(parts[0])

        // Validate the address
        let validator = AddressValidator()
        guard validator.isValid(address) else { return nil }

        var result = ParsedURI(address: address)

        // Parse query parameters if present
        if parts.count > 1 {
            let queryString = String(parts[1])
            let params = queryString.split(separator: "&")

            for param in params {
                let keyValue = param.split(separator: "=", maxSplits: 1)
                guard keyValue.count == 2 else { continue }

                let key = String(keyValue[0]).lowercased()
                let value = String(keyValue[1])
                    .removingPercentEncoding ?? String(keyValue[1])

                switch key {
                case "amount":
                    // Validate amount is a valid decimal
                    if Decimal(string: value) != nil {
                        result.amount = value
                    }
                case "label":
                    result.label = value
                case "message":
                    result.message = value
                default:
                    break
                }
            }
        }

        return result
    }
}

// MARK: - QRCameraPreview

/// UIViewRepresentable that wraps AVCaptureSession for QR code scanning.
struct QRCameraPreview: UIViewRepresentable {
    let onCodeDetected: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let session = AVCaptureSession()
        context.coordinator.session = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return view
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeDetected: onCodeDetected)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        let onCodeDetected: (String) -> Void

        init(onCodeDetected: @escaping (String) -> Void) {
            self.onCodeDetected = onCodeDetected
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            onCodeDetected(value)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.session?.stopRunning()
    }
}

// MARK: - ViewfinderCorners

/// Draws corner brackets for the scanner viewfinder.
private struct ViewfinderCorners: View {
    let rect: CGRect
    private let cornerLength: CGFloat = 24
    private let lineWidth: CGFloat = 3

    var body: some View {
        Canvas { context, _ in
            let path = cornerPath()
            context.stroke(path, with: .color(.white), lineWidth: lineWidth)
        }
    }

    private func cornerPath() -> Path {
        Path { p in
            let r: CGFloat = 8

            // Top-left
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                           control: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))

            // Top-right
            p.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                           control: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))

            // Bottom-left
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                           control: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))

            // Bottom-right
            p.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                           control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        }
    }
}

// MARK: - Reverse Mask Extension

private extension View {
    func reverseMask<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        self.mask {
            Rectangle()
                .overlay {
                    content()
                        .blendMode(.destinationOut)
                }
        }
    }
}
