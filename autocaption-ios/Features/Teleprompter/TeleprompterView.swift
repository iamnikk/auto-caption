import SwiftUI
import AVFoundation
import Combine

/// Prompt 10: Teleprompter View with Front Camera Recording
/// Overlay scrolling script near the camera lens, scroll speed (WPM), font size, mirror mode,
/// 3-second countdown, recording with AVCaptureSession, and seamless pass-through to caption flow.
public struct TeleprompterView: View {
    @Environment(\.dismiss) private var dismiss
    public let onFinishRecording: (URL) -> Void
    
    // Script & Teleprompter Settings
    @State private var scriptText: String = "Welcome to AutoCaption! Read your script smoothly looking straight at the camera. The words scroll at your natural speaking pace, keeping your eyes aligned with your audience."
    @State private var wordsPerMinute: Double = 140
    @State private var fontSize: CGFloat = 26
    @State private var isMirrored: Bool = false
    @State private var isScrolling: Bool = false
    @State private var scrollOffset: CGFloat = 0.0
    
    // Camera & Recording State
    @StateObject private var cameraManager = TeleprompterCameraManager()
    @State private var countdown: Int = 0
    @State private var isCountingDown: Bool = false
    @State private var isRecording: Bool = false
    @State private var scrollTimer: Timer?
    
    public init(onFinishRecording: @escaping (URL) -> Void) {
        self.onFinishRecording = onFinishRecording
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. Camera Preview
            CameraPreviewRepresentable(session: cameraManager.session, isMirrored: isMirrored)
                .ignoresSafeArea()
            
            // Dark gradient overlay to make teleprompter text easily readable
            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.black.opacity(0.4), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
            
            // 2. Teleprompter Overlay positioned right beneath the notch/camera
            VStack(spacing: 0) {
                // Eye-line indicator
                HStack {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("LOOK HERE (CAMERA LENS)")
                        .font(.caption2.bold())
                        .foregroundColor(.red)
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                }
                .padding(.top, 40)
                
                // Scrolling Script Box
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(scriptText)
                                .font(.system(size: fontSize, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 20)
                                .offset(y: -scrollOffset)
                                .scaleEffect(x: isMirrored ? -1 : 1, y: 1) // Mirror mode
                        }
                    }
                }
                .frame(height: 220)
                
                Spacer()
                
                // 3. Teleprompter Controls Bar
                teleprompterControls
                    .padding(.bottom, 30)
            }
            
            // 4. Countdown Overlay
            if isCountingDown {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    Text("\(countdown)")
                        .font(.system(size: 100, weight: .black, design: .rounded))
                        .foregroundColor(.yellow)
                        .scaleEffect(1.2)
                        .animation(.spring(), value: countdown)
                }
            }
        }
        .onAppear {
            cameraManager.startCamera()
        }
        .onDisappear {
            cameraManager.stopCamera()
            stopScrolling()
        }
    }
    
    // MARK: - Teleprompter Controls
    private var teleprompterControls: some View {
        VStack(spacing: 16) {
            // WPM & Font Slider Sheet
            HStack(spacing: 20) {
                // WPM Speed
                VStack(spacing: 2) {
                    Text("\(Int(wordsPerMinute)) WPM")
                        .font(.caption.bold())
                        .foregroundColor(.yellow)
                    Slider(value: $wordsPerMinute, in: 80...240, step: 10)
                        .frame(width: 120)
                        .tint(.yellow)
                }
                
                // Font Size
                VStack(spacing: 2) {
                    Text("\(Int(fontSize)) pt")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Slider(value: $fontSize, in: 18...42, step: 2)
                        .frame(width: 100)
                        .tint(.white)
                }
                
                // Mirror Toggle
                Button(action: { isMirrored.toggle() }) {
                    Image(systemName: isMirrored ? "arrow.left.and.right.righttriangle.left.righttriangle.right.fill" : "arrow.left.and.right")
                        .foregroundColor(isMirrored ? .yellow : .white)
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.7)))
            
            // Action Buttons: Close, Record / Pause, Done
            HStack(spacing: 40) {
                // Close
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                }
                
                // Record Button
                Button(action: toggleRecordingFlow) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 72, height: 72)
                        
                        if isRecording {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 58, height: 58)
                        }
                    }
                }
                
                // Pause / Resume Scroll
                Button(action: toggleScrolling) {
                    Image(systemName: isScrolling ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                }
            }
        }
    }
    
    // MARK: - Teleprompter Engine
    
    private func toggleRecordingFlow() {
        if isRecording {
            stopRecording()
        } else {
            startCountdownAndRecord()
        }
    }
    
    private func startCountdownAndRecord() {
        isCountingDown = true
        countdown = 3
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            countdown -= 1
            if countdown <= 0 {
                timer.invalidate()
                isCountingDown = false
                startRecording()
            }
        }
    }
    
    private func startRecording() {
        isRecording = true
        startScrolling()
        cameraManager.startRecording { outputURL in
            if let url = outputURL {
                onFinishRecording(url)
                dismiss()
            }
        }
    }
    
    private func stopRecording() {
        isRecording = false
        stopScrolling()
        cameraManager.stopRecording()
    }
    
    private func startScrolling() {
        isScrolling = true
        let pixelsPerSecond = (wordsPerMinute / 60.0) * (fontSize * 0.9)
        let interval = 0.03
        
        scrollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            scrollOffset += CGFloat(pixelsPerSecond * interval)
        }
    }
    
    private func stopScrolling() {
        isScrolling = false
        scrollTimer?.invalidate()
        scrollTimer = nil
    }
    
    private func toggleScrolling() {
        if isScrolling {
            stopScrolling()
        } else {
            startScrolling()
        }
    }
}

// MARK: - Camera Manager for Teleprompter
final class TeleprompterCameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var recordingCompletion: ((URL?) -> Void)?
    
    func startCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            
            // Use front camera
            guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let videoInput = try? AVCaptureDeviceInput(device: frontCamera),
                  self.session.canAddInput(videoInput) else { return }
            self.session.addInput(videoInput)
            
            // Microphone
            if let mic = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }
            
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
            }
            
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
    
    func stopCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }
    
    func startRecording(completion: @escaping (URL?) -> Void) {
        self.recordingCompletion = completion
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Teleprompter_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: tempURL)
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
    }
    
    func stopRecording() {
        movieOutput.stopRecording()
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.recordingCompletion?(error == nil ? outputFileURL : nil)
        }
    }
}

// MARK: - Representable Camera Preview
struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
            previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
            previewLayer.connection?.isVideoMirrored = !isMirrored
        }
    }
}
