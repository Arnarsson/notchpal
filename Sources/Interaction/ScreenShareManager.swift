import AppKit
import ScreenCaptureKit

/// Captures the main display at ~1 FPS as JPEG frames.
/// Designed to feed frames to an AI agent (stub for now — stores latest frame).
@Observable
final class ScreenShareManager: NSObject {
    static let shared = ScreenShareManager()

    var isSharing = false
    var latestFrame: NSImage?
    var frameCount = 0
    var fps: Double = 1.0

    private var stream: SCStream?
    private var streamOutput: StreamOutput?

    private override init() { super.init() }

    func startSharing() async {
        guard !isSharing else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.width = 960   // Half resolution for bandwidth
            config.height = 540
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 FPS
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true

            let output = StreamOutput { [weak self] image in
                Task { @MainActor in
                    self?.latestFrame = image
                    self?.frameCount += 1
                }
            }
            self.streamOutput = output

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
            try await stream.startCapture()

            self.stream = stream
            self.isSharing = true

            AgentRegistry.shared.pushNotification(
                agent: "Screen Share",
                message: "Sharing started — agent can see your screen",
                state: .busy
            )
        } catch {
            AgentRegistry.shared.pushNotification(
                agent: "Screen Share",
                message: "Failed: \(error.localizedDescription)",
                state: .error
            )
        }
    }

    func stopSharing() {
        guard isSharing else { return }
        Task {
            try? await stream?.stopCapture()
            stream = nil
            streamOutput = nil
        }
        isSharing = false
        latestFrame = nil
        frameCount = 0

        AgentRegistry.shared.pushNotification(
            agent: "Screen Share",
            message: "Sharing stopped",
            state: .done
        )
    }

    /// Get the latest frame as JPEG data (ready to send to an agent API).
    func latestFrameAsJPEG(quality: CGFloat = 0.5) -> Data? {
        guard let image = latestFrame,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

// MARK: - Stream output handler

private final class StreamOutput: NSObject, SCStreamOutput {
    let onFrame: (NSImage) -> Void

    init(onFrame: @escaping (NSImage) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rep = NSCIImageRep(ciImage: ciImage)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        onFrame(image)
    }
}
