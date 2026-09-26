import Foundation
import AVFoundation
import Vision
import AppKit
import SwiftUI
import simd

/// Real-time live camera face-tracking manager using Apple Vision and AVFoundation.
/// Detects facial landmarks and 3D head pose and maps them directly to 52 ARKit blend shapes on 3D Memojis.
@MainActor
public final class FaceTrackingManager: NSObject, ObservableObject {
    public static let shared = FaceTrackingManager()
    
    @Published public var isRunning: Bool = false
    @Published public var isFaceDetected: Bool = false
    @Published public var permissionDenied: Bool = false
    @Published public var isCameraAvailable: Bool = true
    @Published public var previewLayer: AVCaptureVideoPreviewLayer?
    
    private nonisolated(unsafe) var captureSession: AVCaptureSession?
    private nonisolated(unsafe) var videoOutput: AVCaptureVideoDataOutput?
    private let captureQueue = DispatchQueue(label: "com.culture.facetracker.capture", qos: .userInteractive)
    private let visionQueue = DispatchQueue(label: "com.culture.facetracker.vision", qos: .userInteractive)
    
    private weak var targetStageView: NSView?
    private nonisolated(unsafe) var sampleDelegate: FaceTrackingSampleBufferDelegate?
    
    // Exponential moving average smoothing state
    private var smoothedWeights: [String: Double] = [:]
    private var smoothedRoll: Float = 0
    private var smoothedYaw: Float = 0
    private var smoothedPitch: Float = 0
    
    private override init() {
        super.init()
    }
    
    /// Updates the target stage AVTView being driven by face tracking
    public func updateTargetView(_ view: NSView?) {
        self.targetStageView = view
        if let view = view {
            AvatarKitBridge.shared.resetToNeutralPose(on: view, duration: 0.0)
        }
    }
    
    /// Checks camera permission and starts face tracking on the provided target AVTView
    public func startTracking(on view: NSView?) {
        self.targetStageView = view
        
        if let view = view {
            AvatarKitBridge.shared.resetToNeutralPose(on: view, duration: 0.0)
        }
        
        // If capture session is already running, just update target view and continue seamlessly
        if isRunning, captureSession != nil {
            return
        }
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            self.permissionDenied = false
            self.setupAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.permissionDenied = false
                        self?.setupAndStartSession()
                    } else {
                        self?.permissionDenied = true
                        self?.isRunning = false
                    }
                }
            }
        case .denied, .restricted:
            self.permissionDenied = true
            self.isRunning = false
        @unknown default:
            self.permissionDenied = true
            self.isRunning = false
        }
    }
    
    /// Stops camera face tracking and smoothly resets the avatar pose
    public func stopTracking() {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            if let session = self.captureSession, session.isRunning {
                session.stopRunning()
            }
            self.captureSession = nil
            self.videoOutput = nil
            self.sampleDelegate = nil
            
            DispatchQueue.main.async {
                self.isRunning = false
                self.isFaceDetected = false
                self.previewLayer = nil
                self.smoothedWeights.removeAll()
                self.smoothedRoll = 0
                self.smoothedYaw = 0
                self.smoothedPitch = 0
                
                // Return avatar to neutral pose
                if let view = self.targetStageView {
                    AvatarKitBridge.shared.resetToNeutralPose(on: view)
                }
            }
        }
    }
    
    private func setupAndStartSession() {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Clean up any stale existing session first
            if let existing = self.captureSession {
                if existing.isRunning {
                    existing.stopRunning()
                }
                self.captureSession = nil
                self.videoOutput = nil
                self.sampleDelegate = nil
            }
            
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .vga640x480
            
            // Find front-facing or default video camera
            var cameraDevice: AVCaptureDevice?
            if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                cameraDevice = front
            } else if let anyCamera = AVCaptureDevice.default(for: .video) {
                cameraDevice = anyCamera
            }
            
            guard let camera = cameraDevice,
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else {
                DispatchQueue.main.async {
                    self.isCameraAvailable = false
                    self.isRunning = false
                }
                session.commitConfiguration()
                return
            }
            
            session.addInput(input)
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            
            let delegate = FaceTrackingSampleBufferDelegate { [weak self] sampleBuffer in
                self?.processSampleBuffer(sampleBuffer)
            }
            self.sampleDelegate = delegate
            output.setSampleBufferDelegate(delegate, queue: self.visionQueue)
            
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                return
            }
            
            session.addOutput(output)
            session.commitConfiguration()
            
            self.captureSession = session
            self.videoOutput = output
            
            session.startRunning()
            
            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: session)
                layer.videoGravity = .resizeAspectFill
                if let conn = layer.connection, conn.isVideoMirroringSupported {
                    conn.automaticallyAdjustsVideoMirroring = false
                    conn.isVideoMirrored = true
                }
                self.isRunning = session.isRunning
                self.isCameraAvailable = true
                self.previewLayer = layer
            }
        }
    }
    
    nonisolated private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectFaceLandmarksRequest { [weak self] req, err in
            guard let self = self else { return }
            guard let observations = req.results as? [VNFaceObservation],
                  let face = observations.first,
                  let landmarks = face.landmarks else {
                Task { @MainActor in
                    self.isFaceDetected = false
                }
                return
            }
            
            let weights = Self.extractWeights(landmarks: landmarks)
            let roll = face.roll?.floatValue ?? 0
            let yaw = face.yaw?.floatValue ?? 0
            let pitch = face.pitch?.floatValue ?? 0
            
            Task { @MainActor in
                self.isFaceDetected = true
                self.applyPose(targetWeights: weights, rollVal: roll, yawVal: yaw, pitchVal: pitch)
            }
        }
        
        // Fast processing on Apple Neural Engine
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }
    
    nonisolated private static func extractWeights(landmarks: VNFaceLandmarks2D) -> [String: Double] {
        var targetWeights: [String: Double] = [:]
        
        // 1. Eye Blinks (Eye Aspect Ratio)
        if let leftEye = landmarks.leftEye, leftEye.pointCount >= 6 {
            let pts = leftEye.normalizedPoints
            let minY = pts.map { $0.y }.min() ?? 0
            let maxY = pts.map { $0.y }.max() ?? 0
            let minX = pts.map { $0.x }.min() ?? 0
            let maxX = pts.map { $0.x }.max() ?? 0
            let ear = Double((maxY - minY) / max(maxX - minX, 0.001))
            let blink = clamp((0.21 - ear) / (0.21 - 0.11), min: 0.0, max: 1.0)
            targetWeights["eyeBlinkLeft"] = blink
        }
        
        if let rightEye = landmarks.rightEye, rightEye.pointCount >= 6 {
            let pts = rightEye.normalizedPoints
            let minY = pts.map { $0.y }.min() ?? 0
            let maxY = pts.map { $0.y }.max() ?? 0
            let minX = pts.map { $0.x }.min() ?? 0
            let maxX = pts.map { $0.x }.max() ?? 0
            let ear = Double((maxY - minY) / max(maxX - minX, 0.001))
            let blink = clamp((0.21 - ear) / (0.21 - 0.11), min: 0.0, max: 1.0)
            targetWeights["eyeBlinkRight"] = blink
        }
        
        // 2. Jaw Open (Mouth Aspect Ratio)
        if let lips = landmarks.innerLips ?? landmarks.outerLips, lips.pointCount >= 4 {
            let pts = lips.normalizedPoints
            let minY = pts.map { $0.y }.min() ?? 0
            let maxY = pts.map { $0.y }.max() ?? 0
            let minX = pts.map { $0.x }.min() ?? 0
            let maxX = pts.map { $0.x }.max() ?? 0
            let mar = Double((maxY - minY) / max(maxX - minX, 0.001))
            let rawJaw = clamp((mar - 0.06) / 0.32, min: 0.0, max: 1.0)
            targetWeights["jawOpen"] = rawJaw
        }
        
        // 3. Smile & Frown Detection
        if let lips = landmarks.outerLips, lips.pointCount >= 6 {
            let pts = lips.normalizedPoints
            let minXPt = pts.min(by: { $0.x < $1.x }) ?? CGPoint.zero
            let maxXPt = pts.max(by: { $0.x < $1.x }) ?? CGPoint.zero
            let avgY = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
            
            // Vision coordinates have (0,0) at bottom-left. Smiling raises corners (higher Y).
            let leftCornerLift = Double(minXPt.y - avgY)
            let rightCornerLift = Double(maxXPt.y - avgY)
            
            let smileLeft = clamp((leftCornerLift + 0.015) / 0.035, min: 0.0, max: 1.0)
            let smileRight = clamp((rightCornerLift + 0.015) / 0.035, min: 0.0, max: 1.0)
            targetWeights["mouthSmileLeft"] = smileLeft
            targetWeights["mouthSmileRight"] = smileRight
            
            if smileLeft < 0.1 && smileRight < 0.1 {
                let frownLeft = clamp((-leftCornerLift - 0.01) / 0.03, min: 0.0, max: 1.0)
                let frownRight = clamp((-rightCornerLift - 0.01) / 0.03, min: 0.0, max: 1.0)
                targetWeights["mouthFrownLeft"] = frownLeft
                targetWeights["mouthFrownRight"] = frownRight
            }
        }
        
        // 4. Eyebrows (Inner up & brow down)
        if let brow = landmarks.leftEyebrow, let eye = landmarks.leftEye {
            let browAvgY = brow.normalizedPoints.map { $0.y }.reduce(0, +) / CGFloat(max(brow.pointCount, 1))
            let eyeAvgY = eye.normalizedPoints.map { $0.y }.reduce(0, +) / CGFloat(max(eye.pointCount, 1))
            let dist = Double(browAvgY - eyeAvgY)
            
            let browUp = clamp((dist - 0.04) / 0.03, min: 0.0, max: 1.0)
            targetWeights["browInnerUp"] = browUp
            
            if browUp < 0.1 {
                let browDown = clamp((0.032 - dist) / 0.02, min: 0.0, max: 1.0)
                targetWeights["browDownLeft"] = browDown
                targetWeights["browDownRight"] = browDown
            }
        }
        
        return targetWeights
    }
    
    private func applyPose(targetWeights: [String: Double], rollVal: Float, yawVal: Float, pitchVal: Float) {
        guard let view = targetStageView else { return }
        
        // Smooth weights (Exponential Moving Average)
        let alpha = 0.45
        let trackedKeys = [
            "eyeBlinkLeft", "eyeBlinkRight",
            "jawOpen",
            "mouthSmileLeft", "mouthSmileRight",
            "mouthFrownLeft", "mouthFrownRight",
            "browInnerUp", "browDownLeft", "browDownRight"
        ]
        
        for key in trackedKeys {
            let targetVal = targetWeights[key] ?? 0.0
            let current = smoothedWeights[key] ?? 0.0
            smoothedWeights[key] = current * (1.0 - alpha) + targetVal * alpha
        }
        
        // 5. Head Pose (Roll, Yaw, Pitch)
        let rotAlpha: Float = 0.35
        smoothedRoll = smoothedRoll * (1.0 - rotAlpha) + rollVal * rotAlpha
        smoothedYaw = smoothedYaw * (1.0 - rotAlpha) + yawVal * rotAlpha
        smoothedPitch = smoothedPitch * (1.0 - rotAlpha) + pitchVal * rotAlpha
        
        // Convert to quaternion for neck orientation
        let qRoll = simd_quaternion(smoothedRoll * 0.75, simd_float3(0, 0, 1))
        let qYaw = simd_quaternion(-smoothedYaw * 0.75, simd_float3(0, 1, 0))
        let qPitch = simd_quaternion(smoothedPitch * 0.65, simd_float3(1, 0, 0))
        let neckOrientation = qYaw * qPitch * qRoll
        
        // Build pose and apply directly to avatar
        if let pose = AvatarKitBridge.shared.buildAvatarPose(weights: smoothedWeights, neckOrientation: neckOrientation) {
            AvatarKitBridge.shared.applyPose(pose, on: view)
        }
    }
    
    nonisolated private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        return Swift.min(Swift.max(value, min), max)
    }
}

/// Helper delegate for AVCaptureVideoDataOutput
private final class FaceTrackingSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onFrame: @Sendable (CMSampleBuffer) -> Void
    
    init(onFrame: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.onFrame = onFrame
        super.init()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame(sampleBuffer)
    }
}

/// NSView container for CALayer-based video preview with automatic layout resizing
private final class CameraPreviewContainerView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            guard oldValue !== previewLayer else { return }
            oldValue?.removeFromSuperlayer()
            if let layer = previewLayer {
                layer.frame = bounds
                self.layer?.addSublayer(layer)
            }
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

/// Compact live camera preview overlay for picture-in-picture feedback
@MainActor
public struct CameraPreviewView: NSViewRepresentable {
    public let previewLayer: AVCaptureVideoPreviewLayer?
    
    public init(previewLayer: AVCaptureVideoPreviewLayer?) {
        self.previewLayer = previewLayer
    }
    
    public func makeNSView(context: Context) -> NSView {
        let view = CameraPreviewContainerView(frame: .zero)
        view.previewLayer = previewLayer
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        if let container = nsView as? CameraPreviewContainerView {
            container.previewLayer = previewLayer
        }
    }
}
