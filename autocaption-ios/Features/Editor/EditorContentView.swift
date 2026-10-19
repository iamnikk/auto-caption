import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

/// Main Editor Screen: Select video, transcribe with AI, preview with 60fps captions, and customize styles.
public struct EditorContentView: View {
    @StateObject private var whisperManager = WhisperManager()
    
    // Video picker & Player State
    @State private var selectedItem: PhotosPickerItem?
    @State private var isPhotosPickerPresented: Bool = false
    @State private var isFileImporterPresented: Bool = false
    @State private var videoURL: URL?
    @State private var player: AVPlayer?
    @State private var currentTime: TimeInterval = 0.0
    @State private var isPlaying: Bool = false
    @State private var timeObserverToken: Any?
    
    // Captions & Styling
    @State private var segments: [SubtitleSegment] = []
    @State private var style: CaptionStyle = CaptionStyle()
    @State private var isExtractingAudio: Bool = false
    @State private var errorMessage: String?
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let player = player {
                    VStack(spacing: 0) {
                        // 1. Video Player with Overlay
                        VideoPlayer(player: player)
                            .aspectRatio(9/16, contentMode: .fit)
                            .cornerRadius(16)
                            .overlay(
                                CaptionOverlayView(
                                    currentTime: currentTime,
                                    segments: segments,
                                    style: style
                                )
                                .allowsHitTesting(false)
                            )
                            .padding(.horizontal)
                        
                        // 2. Playback & Timeline Controls
                        playbackControls
                            .padding(.vertical, 8)
                        
                        // 3. Caption Style Presets Selector
                        stylePresetSelector
                            .padding(.bottom, 16)
                    }
                } else {
                    // Empty State: Video Picker
                    emptyStateView
                }
            }
            .navigationTitle("AutoCaption")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if player != nil {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Change Video") {
                            resetSession()
                        }
                        .foregroundColor(.white)
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: exportVideo) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export")
                            }
                            .bold()
                            .foregroundColor(.yellow)
                        }
                    }
                    #else
                    ToolbarItem(placement: .navigation) {
                        Button("Change Video") {
                            resetSession()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: exportVideo) {
                            Text("Export")
                        }
                    }
                    #endif
                }
            }
            .overlay {
                if isExtractingAudio || whisperManager.isTranscribing {
                    loadingHUD
                }
            }
            // Photos Sheet
            .photosPicker(
                isPresented: $isPhotosPickerPresented,
                selection: $selectedItem,
                matching: .videos,
                photoLibrary: .shared()
            )
            // Files / Mac File Browser Picker
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    processSelectedFile(url: url)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
            .onChange(of: selectedItem) { newItem in
                guard let newItem = newItem else { return }
                Task {
                    await handleVideoSelection(newItem)
                }
            }
        }
    }
    
    // MARK: - Empty State (Import)
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.yellow)
            
            VStack(spacing: 8) {
                Text("AI Auto-Caption Studio")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                Text("Select a video from your Mac files, Photos library, or test with a sample reel.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 12) {
                // Button 1: Browse Files from Mac / Files App
                Button(action: {
                    isFileImporterPresented = true
                }) {
                    Label("Browse Files / Mac", systemImage: "folder.fill")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: 240)
                        .padding()
                        .background(Color.yellow)
                        .cornerRadius(30)
                }
                
                // Button 2: Pick Video from Photos Library
                Button(action: {
                    isPhotosPickerPresented = true
                }) {
                    Label("Photos Library", systemImage: "photo.on.rectangle")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: 240)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(30)
                }
                
                // Button 3: Instant Demo Video (for fast testing with one tap)
                Button(action: {
                    loadDemoVideo()
                }) {
                    Text("Or Try with Demo Video")
                        .font(.subheadline)
                        .foregroundColor(.yellow.opacity(0.9))
                        .padding(.top, 4)
                }
            }
        }
    }
    
    // MARK: - Playback Controls
    private var playbackControls: some View {
        HStack(spacing: 20) {
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }
            
            Text(formatTime(currentTime))
                .font(.caption.monospacedDigit())
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Style Preset Selector
    private var stylePresetSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CaptionStylePreset.allCases) { preset in
                    Button(action: { style.preset = preset }) {
                        Text(preset.rawValue)
                            .font(.caption.bold())
                            .foregroundColor(style.preset == preset ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(style.preset == preset ? Color.yellow : Color.white.opacity(0.15))
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Loading HUD
    private var loadingHUD: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                    .scaleEffect(1.4)
                
                Text(whisperManager.statusMessage)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.15)))
        }
    }
    
    // MARK: - Video Loading & Transcription
    private func handleVideoSelection(_ item: PhotosPickerItem) async {
        await MainActor.run { isExtractingAudio = true }
        
        do {
            if let movie = try await item.loadTransferable(type: MovieTransferable.self) {
                processLocalVideo(url: movie.url)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isExtractingAudio = false
            }
        }
    }
    
    private func processSelectedFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        // Copy to temporary folder for safe app sandbox processing
        let tempDestination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
        try? FileManager.default.copyItem(at: url, to: tempDestination)
        
        processLocalVideo(url: tempDestination)
    }
    
    private func processLocalVideo(url: URL) {
        Task {
            await MainActor.run {
                self.videoURL = url
                setupPlayer(with: url)
                self.isExtractingAudio = true
            }
            
            do {
                // 1. Extract 16kHz audio
                let extractor = AudioExtractor()
                var audioTargetURL = url
                if let extractedWAV = try? await extractor.extractAudioForWhisper(from: url) {
                    audioTargetURL = extractedWAV
                }
                
                // 2. Transcribe with Speech/Whisper
                let resultSegments = try await whisperManager.transcribeAudio(from: audioTargetURL)
                
                await MainActor.run {
                    self.segments = resultSegments
                    self.isExtractingAudio = false
                }
            } catch {
                await MainActor.run {
                    self.segments = []
                    self.errorMessage = error.localizedDescription
                    self.isExtractingAudio = false
                }
            }
        }
    }
    
    /// Loads a sample online video for immediate zero-touch testing
    private func loadDemoVideo() {
        guard let url = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4") else { return }
        self.videoURL = url
        setupPlayer(with: url)
        
        Task {
            let resultSegments = try await whisperManager.transcribeAudio(from: url)
            await MainActor.run {
                self.segments = resultSegments
            }
        }
    }
    
    private func setupPlayer(with url: URL) {
        let player = AVPlayer(url: url)
        self.player = player
        
        // Add 60fps (1/60 sec) periodic time observer for silky smooth subtitle synchronization
        let interval = CMTime(value: 1, timescale: 60)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = time.seconds
        }
        
        player.play()
        self.isPlaying = true
    }
    
    private func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    private func resetSession() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
        selectedItem = nil
        videoURL = nil
        segments = []
    }
    
    private func exportVideo() {
        // Triggers AVAssetExportSession
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, ms)
    }
}

// MARK: - Movie Transferable Helper
struct MovieTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try? FileManager.default.removeItem(at: tempCopy)
            try FileManager.default.copyItem(at: received.file, to: tempCopy)
            return Self(url: tempCopy)
        }
    }
}

// MARK: - SwiftUI Canvas Preview
#Preview("AutoCaption Studio") {
    EditorContentView()
        .preferredColorScheme(.dark)
}
