import Foundation
import AVFoundation
import Vision
import AppKit
import SwiftUI
import simd
import CoreVideo

func fileLog(_ msg: String) {
    let url = URL(fileURLWithPath: "/Users/mac/Documents/culture-memoji.log")
    let line = "\(Date()) - \(msg)\n"
    print(msg)
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}

/// Real-time live camera face-tracking manager using Apple Vision and AVFoundation.
///
/// Architecture:
///   - **CVDisplayLink** drives avatar pose at 60fps — independent of Vision's frame rate.
///   - **Quaternion SLERP** (t=0.18) smooths head rotation on the 4D sphere, giving
///     FaceTime-like buttery motion with no euler-angle discontinuities.
///   - **VNDetectFaceRectanglesRequest** (cheap) runs every camera frame → fresh roll/yaw/pitch at 30fps.
///   - **VNDetectFaceLandmarksRequest** (expensive) runs every 2nd frame (~15fps) for blend shapes.
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
    private let visionQueue  = DispatchQueue(label: "com.culture.facetracker.vision",  qos: .userInteractive)

    private weak var targetStageView: NSView?
    private nonisolated(unsafe) var sampleDelegate: FaceTrackingSampleBufferDelegate?

    // MARK: - Rotation state (SLERP)
    /// Target quaternion written from Vision thread (via Task @MainActor).
    private var targetNeckQuat:  simd_quatf = .faceIdentity
    /// Currently displayed quaternion, advanced toward targetNeckQuat at 60fps by CVDisplayLink.
    private var currentNeckQuat: simd_quatf = .faceIdentity

    // MARK: - Blend shape state (EMA, ~15fps)
    private var smoothedWeights: [String: Double] = [:]

    // MARK: - Frame throttle for expensive landmark detection
    /// Every frame: cheap face-rect (head pose). Every 2nd frame: full landmarks (blend shapes).
    private nonisolated(unsafe) var _frameCounterAtomic: Int32 = 0
    private let landmarkFrameInterval: Int32 = 2

    // MARK: - CVDisplayLink (60fps render loop)
    private nonisolated(unsafe) var displayLink: CVDisplayLink?

    // MARK: - Emote overlay state
    /// Currently active emote pose name. Nil = no emote active.
    @Published public private(set) var activeEmoteName: String? = nil
    /// Blend shape weights from the currently active emote. Nil = no emote.
    private var emoteWeights: [String: Double]? = nil
    /// 0.0 = pure live tracking, 1.0 = full emote expression blended in.
    private var emoteBlend: Double = 0.0
    @Published public var isEmotePlaying: Bool = false
    private var emoteTask: Task<Void, Never>?
    /// 3D element emojis/props (tears, hearts, halo, etc.) attached directly to the head bone
    private var activePropNodes: [AnyObject] = []

    private override init() { super.init() }

    // MARK: - Emote API

    /// Blends a sticker emote expression and displays its 3D element emojis (props: hearts,
    /// tears, explosion, halo, confetti, etc.) on top of live head tracking.
    /// Head rotation keeps following your face smoothly in real-time.
    /// By default (duration = nil), the emote stays active on the model indefinitely until deselected or replaced.
    public func playEmote(named poseName: String, on view: NSView,
                          isAnimoji: Bool = false, animojiName: String? = nil,
                          duration: Double? = nil) {
        guard isRunning else {
            fileLog(String(format: "[EMOTE] playEmote('%@')) — SKIPPED: isRunning=false", poseName))
            return
        }

        // ── EARLY EXIT: If this exact emote is already active with props, don't re-trigger.
        if activeEmoteName == poseName, !activePropNodes.isEmpty, isEmotePlaying {
            fileLog(String(format: "[EMOTE] playEmote('%@')) — EARLY EXIT (same emote, %d props, playing)", poseName, activePropNodes.count))
            return
        }

        fileLog(String(format: "[EMOTE] playEmote('%@')) — STARTING (prev=%@, prevProps=%d, isPlaying=%d)",
              poseName, activeEmoteName ?? "nil", activePropNodes.count, isEmotePlaying ? 1 : 0))

        emoteTask?.cancel()

        // 1. Clean up any previously active props before attaching new ones
        if !activePropNodes.isEmpty {
            AvatarKitBridge.shared.removeStickerProps(activePropNodes)
            activePropNodes.removeAll()
        }

        // 2. Attach the 3D element emoji props directly to the head bone
        let props = AvatarKitBridge.shared.attachStickerProps(
            named: poseName,
            to: view,
            animojiNamed: isAnimoji ? animojiName : nil
        )
        activePropNodes = props
        fileLog(String(format: "[EMOTE] playEmote('%@')) — attached %d prop nodes", poseName, props.count))
        AvatarKitBridge.shared.setStickerPropsOpacity(props, opacity: 0.0)

        // 3. Extract static blend shapes (if any) to crossfade facial expressions
        let weights = AvatarKitBridge.shared.extractStaticPoseWeights(
            named: poseName,
            animojiNamed: isAnimoji ? animojiName : nil
        )
        emoteWeights = weights
        emoteBlend = 0.0

        // 4. Set @Published state AFTER all prop/weight setup is complete.
        activeEmoteName = poseName
        isEmotePlaying = true

        // 5. Smooth blend in
        let fadeIn = 0.25

        emoteTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let steps = 15
            for i in 1...steps {
                guard !Task.isCancelled else {
                    fileLog(String(format: "[EMOTE] playEmote('%@')) — fade-in CANCELLED at step %d/%d", poseName, i, steps))
                    return
                }
                let progress = Double(i) / Double(steps)
                self.emoteBlend = progress
                AvatarKitBridge.shared.setStickerPropsOpacity(self.activePropNodes, opacity: CGFloat(progress))
                try? await Task.sleep(nanoseconds: UInt64(fadeIn / Double(steps) * 1_000_000_000))
            }
            self.emoteBlend = 1.0
            AvatarKitBridge.shared.setStickerPropsOpacity(self.activePropNodes, opacity: 1.0)
            fileLog(String(format: "[EMOTE] playEmote('%@')) — fade-in COMPLETE, %d props at full opacity", poseName, self.activePropNodes.count))
            
            // CONTINUOUS LOOP to prevent particles from dying:
            // Re-attach props every 2 seconds while active
            let loopDuration: UInt64 = 2_000_000_000
            while !Task.isCancelled && duration == nil {
                try? await Task.sleep(nanoseconds: loopDuration)
                guard !Task.isCancelled else { break }
                
                // Remove old
                AvatarKitBridge.shared.removeStickerProps(self.activePropNodes)
                self.activePropNodes.removeAll()
                
                // Attach new
                let newProps = AvatarKitBridge.shared.attachStickerProps(
                    named: poseName,
                    to: view,
                    animojiNamed: isAnimoji ? animojiName : nil
                )
                self.activePropNodes = newProps
                AvatarKitBridge.shared.setStickerPropsOpacity(newProps, opacity: 1.0)
            }

            if let duration = duration, duration > 0 {
                let fadeOut = 0.35
                let holdTime = max(0, duration - fadeIn - fadeOut)
                if holdTime > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(holdTime * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }

                for i in 1...steps {
                    guard !Task.isCancelled else { return }
                    let progress = 1.0 - Double(i) / Double(steps)
                    self.emoteBlend = progress
                    AvatarKitBridge.shared.setStickerPropsOpacity(self.activePropNodes, opacity: CGFloat(progress))
                    try? await Task.sleep(nanoseconds: UInt64(fadeOut / Double(steps) * 1_000_000_000))
                }
                self.emoteBlend    = 0.0
                self.emoteWeights  = nil
                self.isEmotePlaying = false
                self.activeEmoteName = nil

                AvatarKitBridge.shared.removeStickerProps(self.activePropNodes)
                self.activePropNodes.removeAll()
            }
        }
    }

    /// Smoothly fades out any active emote, removes element emoji props, and returns to pure live face tracking.
    public func cancelEmote(on view: NSView? = nil, animated: Bool = true) {
        fileLog(String(format: "[EMOTE] cancelEmote() — active=%@, props=%d, blend=%.2f, animated=%d",
              activeEmoteName ?? "nil", activePropNodes.count, emoteBlend, animated ? 1 : 0))
        fileLog("Stack trace: \(Thread.callStackSymbols.prefix(15).joined(separator: "\n"))")
        emoteTask?.cancel()
        activeEmoteName = nil
        isEmotePlaying = false
        emoteWeights = nil

        let propsToRemove = activePropNodes
        activePropNodes.removeAll()

        if animated && emoteBlend > 0.05 && !propsToRemove.isEmpty {
            let startBlend = emoteBlend
            emoteTask = Task { @MainActor [weak self] in
                defer {
                    AvatarKitBridge.shared.removeStickerProps(propsToRemove)
                }
                guard let self else { return }
                let steps = 10
                let fadeOut = 0.2
                for i in 1...steps {
                    guard !Task.isCancelled else { return }
                    let progress = startBlend * (1.0 - Double(i) / Double(steps))
                    self.emoteBlend = progress
                    AvatarKitBridge.shared.setStickerPropsOpacity(propsToRemove, opacity: CGFloat(progress))
                    try? await Task.sleep(nanoseconds: UInt64(fadeOut / Double(steps) * 1_000_000_000))
                }
                self.emoteBlend = 0.0
            }
        } else {
            emoteBlend = 0.0
            AvatarKitBridge.shared.removeStickerProps(propsToRemove)
        }
    }

    // MARK: - Public API

    /// Updates the target stage AVTView being driven by face tracking.
    public func updateTargetView(_ view: NSView?) {
        // Only cancel emotes if the target view actually changed (different view or nil)
        if targetStageView !== view {
            cancelEmote()
        }
        targetStageView = view
        if let view { AvatarKitBridge.shared.resetToNeutralPose(on: view, duration: 0.0) }
    }

    /// Requests camera permission (if needed) and begins face tracking on `view`.
    public func startTracking(on view: NSView?) {
        targetStageView = view
        if let view { AvatarKitBridge.shared.resetToNeutralPose(on: view, duration: 0.0) }

        // If already running, seamlessly re-target without restarting the session.
        if isRunning, captureSession != nil { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionDenied = false
            setupAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.permissionDenied = false; self?.setupAndStartSession() }
                    else        { self?.permissionDenied = true;  self?.isRunning = false }
                }
            }
        default:
            permissionDenied = true
            isRunning = false
        }
    }

    /// Stops tracking and smoothly returns the avatar to its neutral pose.
    public func stopTracking() {
        cancelEmote()
        stopDisplayLink()
        captureQueue.async { [weak self] in
            guard let self else { return }
            captureSession?.stopRunning()
            captureSession = nil
            videoOutput = nil
            sampleDelegate = nil
            DispatchQueue.main.async {
                self.isRunning = false
                self.isFaceDetected = false
                self.previewLayer = nil
                self.smoothedWeights.removeAll()
                self.currentNeckQuat = .faceIdentity
                self.targetNeckQuat  = .faceIdentity
                if let v = self.targetStageView { AvatarKitBridge.shared.resetToNeutralPose(on: v) }
            }
        }
    }

    // MARK: - Session Setup

    private func setupAndStartSession() {
        captureQueue.async { [weak self] in
            guard let self else { return }

            // Tear down any stale session.
            captureSession?.stopRunning()
            captureSession = nil; videoOutput = nil; sampleDelegate = nil

            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .vga640x480

            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                      ?? AVCaptureDevice.default(for: .video)
            guard let cam = camera,
                  let input = try? AVCaptureDeviceInput(device: cam),
                  session.canAddInput(input) else {
                DispatchQueue.main.async { self.isCameraAvailable = false; self.isRunning = false }
                session.commitConfiguration(); return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            let delegate = FaceTrackingSampleBufferDelegate { [weak self] buf in self?.processSampleBuffer(buf) }
            sampleDelegate = delegate
            output.setSampleBufferDelegate(delegate, queue: visionQueue)
            guard session.canAddOutput(output) else { session.commitConfiguration(); return }
            session.addOutput(output)
            session.commitConfiguration()

            captureSession = session
            videoOutput = output
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
                self.startDisplayLink()
            }
        }
    }

    // MARK: - CVDisplayLink (60fps SLERP render loop)

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let link = dl else { return }

        // Pass self as unretained raw pointer — CVDisplayLink holds the callback alive.
        // We retain once here and release when stopDisplayLink is called.
        let ptr = Unmanaged.passRetained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, ctx -> CVReturn in
            let mgr = Unmanaged<FaceTrackingManager>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { mgr.stepSlerp() }
            return kCVReturnSuccess
        }, ptr)
        CVDisplayLinkStart(link)
        displayLink = link
        // Release the extra retain — the opaque pointer in the callback is now the only owner.
        Unmanaged<FaceTrackingManager>.fromOpaque(ptr).release()
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    /// Advances the SLERP one step toward `targetNeckQuat` and pushes the full pose.
    /// Runs at ~60fps via CVDisplayLink — decoupled from Vision's camera frame rate.
    /// Also applies emote blend: emoteBlend∈[0,1] crossfades between live tracking and emote expression.
    private var _debugFrameCounter: Int = 0
    private func stepSlerp() {
        guard isRunning, let view = targetStageView else { return }

        // Ensure we take the short arc (negate target when dot product < 0).
        var target = targetNeckQuat
        if simd_dot(currentNeckQuat.vector, target.vector) < 0 { target = simd_quaternion(-target.vector) }
        currentNeckQuat = simd_slerp(currentNeckQuat, target, 0.18)

        // Merge live tracking weights with emote weights using emoteBlend factor
        let finalWeights: [String: Double]
        if emoteBlend > 0.001, let ew = emoteWeights {
            var merged: [String: Double] = [:]
            // Union of all keys in both weight dictionaries
            let allKeys = Set(smoothedWeights.keys).union(ew.keys)
            for key in allKeys {
                let live  = smoothedWeights[key] ?? 0.0
                let emote = ew[key] ?? 0.0
                merged[key] = live * (1.0 - emoteBlend) + emote * emoteBlend
            }
            finalWeights = merged
        } else {
            finalWeights = smoothedWeights
        }

        if let pose = AvatarKitBridge.shared.buildAvatarPose(weights: finalWeights,
                                                              neckOrientation: currentNeckQuat) {
            AvatarKitBridge.shared.applyPose(pose, on: view)
        }
        
        // Force props to stay visible (in case their internal animations try to fade them out)
        if !activePropNodes.isEmpty && emoteBlend > 0.99 {
            AvatarKitBridge.shared.setStickerPropsOpacity(activePropNodes, opacity: 1.0)
        }

        // ── DEBUG: check prop survival once per second (~60 frames)
        _debugFrameCounter += 1
        if _debugFrameCounter % 60 == 0, !activePropNodes.isEmpty {
            let parentSel = NSSelectorFromString("parentNode")
            var orphanCount = 0
            for node in activePropNodes {
                if (node as AnyObject).responds(to: parentSel) {
                    let parent = (node as AnyObject).perform(parentSel)?.takeUnretainedValue()
                    if parent == nil { orphanCount += 1 }
                }
            }
            if orphanCount > 0 {
                fileLog(String(format: "[EMOTE] ⚠️ stepSlerp: %d/%d prop nodes ORPHANED (removed from scene by AvatarKit!))",
                      orphanCount, activePropNodes.count))
            }
        }
    }


    // MARK: - Vision Pipeline

    nonisolated private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let count = OSAtomicIncrement32(&_frameCounterAtomic)

        // Cheap face-rectangle request → fresh head pose every camera frame (~30fps).
        let poseReq = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            guard let self,
                  let face = (req.results as? [VNFaceObservation])?.first else {
                Task { @MainActor in self?.isFaceDetected = false }
                return
            }
            let roll  = face.roll?.floatValue  ?? 0
            let yaw   = face.yaw?.floatValue   ?? 0
            let pitch = face.pitch?.floatValue ?? 0
            // Raw quaternion from Vision euler angles — SLERP in stepSlerp() smooths it at 60fps.
            let qR = simd_quaternion( roll  * 0.75, simd_float3(0, 0, 1))
            let qY = simd_quaternion(-yaw   * 0.75, simd_float3(0, 1, 0))
            let qP = simd_quaternion( pitch * 0.65, simd_float3(1, 0, 0))
            let raw = qY * qP * qR
            Task { @MainActor in self.targetNeckQuat = raw; self.isFaceDetected = true }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        // Expensive landmark request every 2nd frame (~15fps) for blend shapes.
        if count % landmarkFrameInterval == 0 {
            let lmReq = VNDetectFaceLandmarksRequest { [weak self] req, _ in
                guard let self,
                      let face = (req.results as? [VNFaceObservation])?.first,
                      let lm = face.landmarks else { return }
                let w = Self.extractWeights(landmarks: lm)
                Task { @MainActor in self.applyBlendShapes(targetWeights: w) }
            }
            try? handler.perform([poseReq, lmReq])
        } else {
            try? handler.perform([poseReq])
        }
    }

    // MARK: - Blend Shape Smoothing

    /// Adaptive EMA using real AvatarKit key names (underscore format, matching sticker weights).
    /// Live tracking runs continuously — emote blending happens in stepSlerp, not here.
    private func applyBlendShapes(targetWeights: [String: Double]) {
        let keys = [
            "eyeBlink_L", "eyeBlink_R",
            "jawOpen",
            "mouthSmile_L", "mouthSmile_R",
            "mouthFrown_L", "mouthFrown_R",
            "browInnerUp", "browDown_L", "browDown_R",
            "eyeSquint_L", "eyeSquint_R"
        ]
        let baseAlpha = 0.75, fastAlpha = 0.92, threshold = 0.12
        for key in keys {
            let target  = targetWeights[key] ?? 0.0
            let current = smoothedWeights[key] ?? 0.0
            let alpha   = abs(target - current) > threshold ? fastAlpha : baseAlpha
            smoothedWeights[key] = current + alpha * (target - current)
        }
    }

    // MARK: - Landmark Extraction (AvatarKit underscore key names)

    nonisolated private static func extractWeights(landmarks: VNFaceLandmarks2D) -> [String: Double] {
        var w: [String: Double] = [:]

        func eyeAspectRatio(_ region: VNFaceLandmarkRegion2D?) -> Double? {
            guard let r = region, r.pointCount >= 6 else { return nil }
            let pts = r.normalizedPoints
            let h = Double((pts.map { $0.y }.max() ?? 0) - (pts.map { $0.y }.min() ?? 0))
            let wd = Double((pts.map { $0.x }.max() ?? 0) - (pts.map { $0.x }.min() ?? 0))
            return clamp((0.21 - h / max(wd, 0.001)) / (0.21 - 0.11), min: 0, max: 1)
        }
        w["eyeBlink_L"] = eyeAspectRatio(landmarks.leftEye)
        w["eyeBlink_R"] = eyeAspectRatio(landmarks.rightEye)

        if let lips = landmarks.innerLips ?? landmarks.outerLips, lips.pointCount >= 4 {
            let pts = lips.normalizedPoints
            let h  = Double((pts.map { $0.y }.max() ?? 0) - (pts.map { $0.y }.min() ?? 0))
            let wd = Double((pts.map { $0.x }.max() ?? 0) - (pts.map { $0.x }.min() ?? 0))
            w["jawOpen"] = clamp((h / max(wd, 0.001) - 0.06) / 0.32, min: 0, max: 1)
        }

        if let lips = landmarks.outerLips, lips.pointCount >= 6 {
            let pts  = lips.normalizedPoints
            let avgY = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
            let lL = Double((pts.min { $0.x < $1.x }?.y ?? 0) - avgY)
            let lR = Double((pts.max { $0.x < $1.x }?.y ?? 0) - avgY)
            let smL = clamp((lL + 0.015) / 0.035, min: 0, max: 1)
            let smR = clamp((lR + 0.015) / 0.035, min: 0, max: 1)
            w["mouthSmile_L"] = smL; w["mouthSmile_R"] = smR
            if smL < 0.1 && smR < 0.1 {
                w["mouthFrown_L"] = clamp((-lL - 0.01) / 0.03, min: 0, max: 1)
                w["mouthFrown_R"] = clamp((-lR - 0.01) / 0.03, min: 0, max: 1)
            }
        }

        if let brow = landmarks.leftEyebrow, let eye = landmarks.leftEye {
            let bY = brow.normalizedPoints.map { $0.y }.reduce(0, +) / CGFloat(max(brow.pointCount, 1))
            let eY = eye.normalizedPoints.map  { $0.y }.reduce(0, +) / CGFloat(max(eye.pointCount,  1))
            let dist = Double(bY - eY)
            let up   = clamp((dist - 0.04) / 0.03, min: 0, max: 1)
            w["browInnerUp"] = up
            if up < 0.1 { let dn = clamp((0.032 - dist) / 0.02, min: 0, max: 1); w["browDown_L"] = dn; w["browDown_R"] = dn }
        }
        return w
    }

    nonisolated private static func clamp(_ v: Double, min lo: Double, max hi: Double) -> Double {
        Swift.min(Swift.max(v, lo), hi)
    }
}

// MARK: - Helpers

private extension simd_quatf {
    /// Neutral head orientation (no rotation).
    static let faceIdentity = simd_quaternion(Float(0), simd_float3(0, 1, 0))
}

// MARK: - AVCapture delegate

private final class FaceTrackingSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onFrame: @Sendable (CMSampleBuffer) -> Void
    init(onFrame: @escaping @Sendable (CMSampleBuffer) -> Void) { self.onFrame = onFrame; super.init() }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame(sampleBuffer)
    }
}

// MARK: - Camera Preview Views

/// NSView container that hosts a `AVCaptureVideoPreviewLayer` and auto-resizes it.
private final class CameraPreviewContainerView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            guard oldValue !== previewLayer else { return }
            oldValue?.removeFromSuperlayer()
            if let l = previewLayer { l.frame = bounds; self.layer?.addSublayer(l) }
        }
    }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor }
    required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true); previewLayer?.frame = bounds; CATransaction.commit()
    }
}

/// Compact live camera preview overlay for picture-in-picture feedback.
@MainActor
public struct CameraPreviewView: NSViewRepresentable {
    public let previewLayer: AVCaptureVideoPreviewLayer?
    public init(previewLayer: AVCaptureVideoPreviewLayer?) { self.previewLayer = previewLayer }

    public func makeNSView(context: Context) -> NSView {
        let v = CameraPreviewContainerView(frame: .zero); v.previewLayer = previewLayer; return v
    }
    public func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CameraPreviewContainerView)?.previewLayer = previewLayer
    }
}
