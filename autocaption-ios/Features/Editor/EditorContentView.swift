import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

/// Main Editor Screen (Prompts 1, 2, 3):
/// 1. Video Import with PhotosPicker (limited-library aware, 5-minute length validation).
/// 2. On-Device Transcription via TranscriptionService (Apple Speech with requiresOnDeviceRecognition = true, m4a extraction).
/// 3. CaptionSegmenter pacing (.fast, .balanced, .relaxed) with 0.4s pause detection and non-overlapping timing.
public struct EditorContentView: View {
    @StateObject private var videoImportManager = VideoImportManager()
    @StateObject private var transcriptionService = TranscriptionService()
    
    // Video import & Project State
    @State private var currentProject: Project?
    @State private var rawWords: [CaptionWord] = []
    @State private var pacingMode: PacingMode = .fast
    @State private var videoThumbnail: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    @State private var isPhotosPickerPresented: Bool = false
    @State private var isFileImporterPresented: Bool = false
    
    // Player State
    @State private var player: AVPlayer?
    @State private var currentTime: TimeInterval = 0.0
    @State private var isPlaying: Bool = false
    @State private var timeObserverToken: Any?
    
    // UI & Status
    @State private var isLoading: Bool = false
    @State private var loadingStatusText: String = "Loading video..."
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let project = currentProject, let player = player {
                    VStack(spacing: 0) {
                        // 1. Video Player with Subtitle Overlay and Aspect Ratio
                        ZStack {
                            VideoPlayer(player: player)
                                .aspectRatio(project.aspectRatio.ratio, contentMode: .fit)
                                .cornerRadius(16)
                                .overlay(
                                    CaptionOverlayView(
                                        currentTime: currentTime,
                                        segments: project.segments,
                                        style: project.style
                                    )
                                    .allowsHitTesting(false)
                                )
                                .clipped()
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Metadata & Duration pill
                        if let meta = project.metadata {
                            HStack(spacing: 12) {
                                Label(formatTime(meta.duration), systemImage: "clock")
                                Label("\(Int(meta.resolution.width))x\(Int(meta.resolution.height))", systemImage: "aspectratio")
                                Label(meta.isPortrait ? "Portrait" : "Landscape", systemImage: meta.isPortrait ? "iphone" : "ipad.landscape")
                            }
                            .font(.caption2.bold())
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                        }
                        
                        // 2. Playback & Timeline Controls
                        playbackControls
                            .padding(.vertical, 6)
                        
                        // 3. Pacing Mode Selector (Fast / Balanced / Relaxed)
                        pacingSelector
                            .padding(.bottom, 6)
                        
                        // 4. Caption Style Presets Selector
                        stylePresetSelector
                            .padding(.bottom, 14)
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
                if currentProject != nil {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Change") {
                            resetSession()
                        }
                        .foregroundColor(.white)
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            languageMenu
                            
                            Button(action: exportVideo) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export")
                                }
                                .bold()
                                .foregroundColor(.yellow)
                            }
                        }
                    }
                    #else
                    ToolbarItem(placement: .navigation) {
                        Button("Change Video") {
                            resetSession()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        HStack {
                            languageMenu
                            Button("Export", action: exportVideo)
                        }
                    }
                    #endif
                }
            }
            .overlay {
                if isLoading || transcriptionService.isTranscribing {
                    loadingHUD
                }
            }
            .alert("Notice", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An error occurred.")
            }
            // Photos Sheet (Prompt 1: videos only, limited library support)
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
                    handleImportFromFileURL(url)
                case .failure(let error):
                    displayError(error.localizedDescription)
                }
            }
            .onChange(of: selectedItem) { newItem in
                guard let newItem = newItem else { return }
                handlePhotosPickerSelection(newItem)
            }
        }
    }
    
    // MARK: - Language Selector Menu (Prompt 2)
    private var languageMenu: some View {
        Menu {
            Section("Speech Language (On-Device)") {
                ForEach(transcriptionService.availableLocales, id: \.identifier) { locale in
                    let name = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
                    Button {
                        transcriptionService.selectedLocale = locale
                        if let project = currentProject {
                            transcribeImportedVideo(project.sourceVideoURL)
                        }
                    } label: {
                        HStack {
                            Text(name)
                            if transcriptionService.selectedLocale.identifier == locale.identifier {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
                .foregroundColor(.yellow)
        }
    }
    
    // MARK: - Empty State (Import Screen)
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.yellow)
            
            VStack(spacing: 8) {
                Text("AI Auto-Caption Studio")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                Text("Select any video up to 5 minutes to generate 100% on-device, synchronized animated captions.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 12) {
                // Button 1: Pick from Photos Library
                Button(action: {
                    isPhotosPickerPresented = true
                }) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: 260)
                        .padding()
                        .background(Color.yellow)
                        .cornerRadius(30)
                }
                
                // Button 2: Browse Files
                Button(action: {
                    isFileImporterPresented = true
                }) {
                    Label("Browse Files / Mac", systemImage: "folder.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(30)
                }
                
                // Button 3: Instant Demo Video (for fast zero-touch testing)
                Button(action: {
                    loadDemoVideo()
                }) {
                    Text("Try with Sample Demo Reel")
                        .font(.footnote)
                        .foregroundColor(.yellow.opacity(0.9))
                        .padding(.top, 6)
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
            
            if let duration = currentProject?.metadata?.duration {
                Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.gray)
            } else {
                Text(formatTime(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.gray)
            }
        }
    }
    
    // MARK: - Pacing Mode Selector (Prompt 3)
    private var pacingSelector: some View {
        HStack(spacing: 8) {
            ForEach(PacingMode.allCases) { mode in
                let isSelected = pacingMode == mode
                Button {
                    pacingMode = mode
                    applyPacing(mode)
                } label: {
                    Text(mode.rawValue)
                        .font(.caption2.bold())
                        .foregroundColor(isSelected ? .black : .white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSelected ? Color.yellow : Color.white.opacity(0.12))
                        )
                }
            }
        }
    }
    
    // MARK: - Style Preset Selector
    private var stylePresetSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CaptionStylePreset.allCases) { preset in
                    let isSelected = currentProject?.style.preset == preset
                    Button(action: {
                        currentProject?.style.preset = preset
                    }) {
                        Text(preset.rawValue)
                            .font(.caption.bold())
                            .foregroundColor(isSelected ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.yellow : Color.white.opacity(0.15))
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
                
                Text(isLoading ? loadingStatusText : transcriptionService.statusMessage)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.15)))
        }
    }
    
    // MARK: - Video Import & Transcription Handling
    
    private func handlePhotosPickerSelection(_ item: PhotosPickerItem) {
        Task {
            await MainActor.run {
                self.isLoading = true
                self.loadingStatusText = "Importing & validating video..."
            }
            
            do {
                let imported = try await videoImportManager.importVideo(from: item)
                let thumb = await videoImportManager.generateThumbnail(for: imported.localURL)
                
                await MainActor.run {
                    self.videoThumbnail = thumb
                    self.setupProjectAndPlayer(with: imported)
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    displayError(error.localizedDescription)
                }
            }
        }
    }
    
    private func handleImportFromFileURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            displayError("Permission to access the selected file was denied.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        Task {
            await MainActor.run {
                self.isLoading = true
                self.loadingStatusText = "Copying & inspecting video..."
            }
            
            do {
                let imported = try await videoImportManager.processLocalVideo(at: url)
                let thumb = await videoImportManager.generateThumbnail(for: imported.localURL)
                
                await MainActor.run {
                    self.videoThumbnail = thumb
                    self.setupProjectAndPlayer(with: imported)
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    displayError(error.localizedDescription)
                }
            }
        }
    }
    
    private func setupProjectAndPlayer(with imported: VideoImportManager.ImportedVideo) {
        let initialAspect: AspectRatio = imported.metadata.isPortrait ? .portrait9_16 : .landscape16_9
        self.currentProject = Project(
            sourceVideoURL: imported.localURL,
            segments: [],
            style: CaptionStyle(),
            aspectRatio: initialAspect,
            metadata: imported.metadata
        )
        
        setupPlayer(with: imported.localURL)
        transcribeImportedVideo(imported.localURL)
    }
    
    private func transcribeImportedVideo(_ videoURL: URL) {
        Task {
            await MainActor.run {
                self.isLoading = false
            }
            
            do {
                let words = try await transcriptionService.transcribeVideo(videoURL: videoURL)
                await MainActor.run {
                    self.rawWords = words
                    self.applyPacing(self.pacingMode)
                }
            } catch {
                await MainActor.run {
                    self.rawWords = []
                    self.currentProject?.segments = []
                    displayError(error.localizedDescription)
                }
            }
        }
    }
    
    private func applyPacing(_ mode: PacingMode) {
        let segments = CaptionSegmenter.segment(words: self.rawWords, pacing: mode)
        self.currentProject?.segments = segments
    }
    
    private func loadDemoVideo() {
        guard let url = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4") else { return }
        
        let meta = VideoMetadata(duration: 15.0, resolution: CGSize(width: 1280, height: 720), isPortrait: false)
        self.currentProject = Project(
            sourceVideoURL: url,
            segments: [],
            style: CaptionStyle(),
            aspectRatio: .landscape16_9,
            metadata: meta
        )
        
        setupPlayer(with: url)
        transcribeImportedVideo(url)
    }
    
    private func setupPlayer(with url: URL) {
        let player = AVPlayer(url: url)
        self.player = player
        
        // 60fps periodic time observer for smooth subtitles
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
        currentProject = nil
        videoThumbnail = nil
        rawWords = []
        currentTime = 0.0
    }
    
    private func exportVideo() {
        // Will be wired in Prompt 6
    }
    
    private func displayError(_ message: String) {
        self.errorMessage = message
        self.showErrorAlert = true
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, ms)
    }
}

#Preview("AutoCaption Studio") {
    EditorContentView()
        .preferredColorScheme(.dark)
}
