import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

/// Unified Main Editor Screen:
/// - Prompts 0-3: Foundation models, video import with 5-minute validation, on-device transcription, and pacing modes.
/// - Prompt 4: Caption editor with segment timeline, tap to seek, word emphasis toggle, steppers, split, merge, delete, undo/redo.
/// - Prompt 5: 10 original styles with shared CALayer renderer and style customization sheet.
/// - Prompt 6 & 7: Export with burned-in captions, Photos saving, share sheet, and auto-crop aspect ratio presets.
/// - Prompts 8-12: Silence removal, background music mixing, teleprompter camera, translation, and studio sound.
public struct EditorContentView: View {
    @StateObject private var videoImportManager = VideoImportManager()
    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var videoExporter = VideoExporter()
    @StateObject private var translationManager = CaptionTranslationManager()
    
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
    
    // Navigation / Sheets
    enum ActiveTab: String, CaseIterable, Identifiable {
        case styles = "Styles"
        case captions = "Captions"
        case aspect = "Aspect"
        case audio = "Audio"
        var id: String { rawValue }
    }
    @State private var activeTab: ActiveTab = .styles
    @State private var isCustomizingStyle: Bool = false
    @State private var isTeleprompterPresented: Bool = false
    @State private var exportedShareURL: URL?
    @State private var isShareSheetPresented: Bool = false
    
    // UI & Status
    @State private var isLoading: Bool = false
    @State private var loadingStatusText: String = "Loading video..."
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false
    
    // Audio options
    @State private var isStudioSoundEnabled: Bool = false
    @State private var isSilenceRemovalActive: Bool = false
    
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
                        .frame(maxHeight: 340)
                        
                        // Metadata pill & Playback Controls
                        playbackControls
                            .padding(.vertical, 4)
                        
                        // Tab Selector (Styles | Captions | Aspect | Audio)
                        editorTabPicker
                            .padding(.horizontal)
                            .padding(.bottom, 6)
                        
                        // Tab Content View
                        tabContentView
                            .frame(maxHeight: .infinity)
                    }
                } else {
                    // Empty State: Video Picker & Teleprompter Entry
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
                            
                            Button(action: triggerExport) {
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
                        Button("Change Video", action: resetSession)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        HStack {
                            languageMenu
                            Button("Export", action: triggerExport)
                        }
                    }
                    #endif
                }
            }
            .overlay {
                if isLoading || transcriptionService.isTranscribing || videoExporter.isExporting {
                    loadingHUD
                }
            }
            .alert("Notice", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "An error occurred.")
            }
            .sheet(isPresented: $isCustomizingStyle) {
                if let project = currentProject {
                    StyleCustomizationSheet(
                        style: Binding(
                            get: { self.currentProject?.style ?? CaptionStyle() },
                            set: { self.currentProject?.style = $0 }
                        )
                    )
                }
            }
            .fullScreenCover(isPresented: $isTeleprompterPresented) {
                TeleprompterView { recordedURL in
                    handleImportFromFileURL(recordedURL)
                }
            }
            .sheet(isPresented: $isShareSheetPresented) {
                if let shareURL = exportedShareURL {
                    ShareSheetView(activityItems: [shareURL])
                }
            }
            .photosPicker(
                isPresented: $isPhotosPickerPresented,
                selection: $selectedItem,
                matching: .videos,
                photoLibrary: .shared()
            )
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
    
    // MARK: - Editor Tabs
    private var editorTabPicker: some View {
        HStack(spacing: 8) {
            ForEach(ActiveTab.allCases) { tab in
                let isSelected = activeTab == tab
                Button {
                    activeTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.caption.bold())
                        .foregroundColor(isSelected ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isSelected ? Color.yellow : Color.white.opacity(0.12))
                        )
                }
            }
        }
    }
    
    @ViewBuilder
    private var tabContentView: some View {
        switch activeTab {
        case .styles:
            stylesTabView
        case .captions:
            captionsTabView
        case .aspect:
            aspectRatioTabView
        case .audio:
            audioToolsTabView
        }
    }
    
    // MARK: - Tab 1: Styles Tab View
    private var stylesTabView: some View {
        VStack(spacing: 12) {
            // Horizontal Style Preset Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CaptionStylePreset.allCases) { preset in
                        let isSelected = currentProject?.style.preset == preset
                        Button(action: { currentProject?.style.preset = preset }) {
                            Text(preset.rawValue)
                                .font(.caption.bold())
                                .foregroundColor(isSelected ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(isSelected ? Color.yellow : Color.white.opacity(0.15))
                                )
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Pacing Selector (Fast, Balanced, Relaxed)
            pacingSelector
            
            // Customize Fine Controls Button
            Button(action: { isCustomizingStyle = true }) {
                Label("Customize Font, Colors & Position", systemImage: "slider.horizontal.3")
                    .font(.caption.bold())
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 20).stroke(Color.yellow, lineWidth: 1))
            }
            .padding(.top, 4)
            
            Spacer()
        }
    }
    
    // MARK: - Tab 2: Captions Editor Tab View (Prompt 4)
    private var captionsTabView: some View {
        CaptionEditorView(
            segments: Binding(
                get: { self.currentProject?.segments ?? [] },
                set: { self.currentProject?.segments = $0 }
            ),
            currentTime: currentTime,
            onSeek: { targetTime in
                seekPlayer(to: targetTime)
            }
        )
    }
    
    // MARK: - Tab 3: Aspect Ratio Presets (Prompt 7)
    private var aspectRatioTabView: some View {
        VStack(spacing: 16) {
            Text("Select Aspect Ratio Framing")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                ForEach(AspectRatio.allCases) { ratio in
                    let isSelected = currentProject?.aspectRatio == ratio
                    Button {
                        currentProject?.aspectRatio = ratio
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: aspectIcon(ratio))
                                .font(.title2)
                            Text(ratio.rawValue)
                                .font(.caption.bold())
                        }
                        .foregroundColor(isSelected ? .black : .white)
                        .frame(width: 72, height: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Color.yellow : Color.white.opacity(0.15))
                        )
                    }
                }
            }
            
            Text("Auto-crop fills the frame centered with automatic transformation.")
                .font(.caption)
                .foregroundColor(.gray)
            
            Spacer()
        }
        .padding(.top, 12)
    }
    
    // MARK: - Tab 4: Audio Tools (Prompts 8 & 12)
    private var audioToolsTabView: some View {
        VStack(spacing: 16) {
            // Silence Removal (Prompt 8)
            Toggle(isOn: $isSilenceRemovalActive) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic Silence Removal")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("Cuts pauses > 0.4s to keep videos energetic & tight.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .tint(.yellow)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12)))
            .onChange(of: isSilenceRemovalActive) { active in
                if active {
                    applySilenceRemoval()
                }
            }
            
            // Studio Sound (Prompt 12)
            Toggle(isOn: $isStudioSoundEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Studio Sound (Audio Cleanup)")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("80Hz rumble cut, voice presence EQ boost, and normalization.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .tint(.yellow)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12)))
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
    
    // MARK: - Playback Controls
    private var playbackControls: some View {
        HStack(spacing: 20) {
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
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
            
            Spacer()
            
            if let meta = currentProject?.metadata {
                Text("\(Int(meta.resolution.width))x\(Int(meta.resolution.height))")
                    .font(.caption2.monospaced())
                    .foregroundColor(.gray.opacity(0.8))
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Pacing Mode Selector
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
    
    // MARK: - Empty State (Import & Teleprompter)
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.yellow)
            
            VStack(spacing: 8) {
                Text("AI Auto-Caption Studio")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                Text("Import a video or record directly using the built-in teleprompter for viral animated captions.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 12) {
                // Button 1: Pick from Photos Library
                Button(action: { isPhotosPickerPresented = true }) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: 260)
                        .padding()
                        .background(Color.yellow)
                        .cornerRadius(30)
                }
                
                // Button 2: Teleprompter Recording (Prompt 10)
                Button(action: { isTeleprompterPresented = true }) {
                    Label("Record with Teleprompter", systemImage: "camera.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(30)
                }
                
                // Button 3: Browse Files
                Button(action: { isFileImporterPresented = true }) {
                    Label("Browse Files / Mac", systemImage: "folder.fill")
                        .font(.footnote.bold())
                        .foregroundColor(.gray)
                }
            }
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
                
                let text = videoExporter.isExporting ? videoExporter.statusMessage :
                    (isLoading ? loadingStatusText : transcriptionService.statusMessage)
                
                Text(text)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                
                if videoExporter.isExporting {
                    ProgressView(value: videoExporter.exportProgress)
                        .progressViewStyle(.linear)
                        .tint(.yellow)
                        .frame(width: 180)
                }
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
            await MainActor.run { self.isLoading = false }
            
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
    
    private func applySilenceRemoval() {
        guard let project = currentProject else { return }
        Task {
            let service = SilenceRemovalService()
            do {
                let silences = try await service.detectSilences(in: project.sourceVideoURL)
                let remapped = SilenceRemovalService.remapTimestamps(segments: project.segments, removedSilences: silences)
                await MainActor.run {
                    self.currentProject?.segments = remapped
                }
            } catch {
                displayError("Silence analysis failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func triggerExport() {
        guard let project = currentProject else { return }
        Task {
            do {
                let outputURL = try await videoExporter.export(project: project)
                await MainActor.run {
                    self.exportedShareURL = outputURL
                    self.isShareSheetPresented = true
                }
            } catch {
                displayError(error.localizedDescription)
            }
        }
    }
    
    private func setupPlayer(with url: URL) {
        let player = AVPlayer(url: url)
        self.player = player
        
        let interval = CMTime(value: 1, timescale: 60)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = time.seconds
        }
        
        player.play()
        self.isPlaying = true
    }
    
    private func seekPlayer(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
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
    
    private func aspectIcon(_ ratio: AspectRatio) -> String {
        switch ratio {
        case .portrait9_16: return "iphone"
        case .square1_1: return "square"
        case .portrait4_5: return "rectangle.portrait"
        case .landscape16_9: return "ipad.landscape"
        }
    }
}

// MARK: - Share Sheet Helper (UIActivityViewController)
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview("AutoCaption Studio") {
    EditorContentView()
        .preferredColorScheme(.dark)
}
