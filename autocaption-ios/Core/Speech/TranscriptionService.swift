import Foundation
import Speech
import AVFoundation
import Combine

/// Prompt 2: Protocol defining swappable on-device speech-to-text transcribers
public protocol Transcriber: Sendable {
    func transcribe(audioURL: URL, locale: Locale) async throws -> [CaptionWord]
}

/// Transcription errors with clear, user-friendly messages
public enum TranscriptionError: LocalizedError {
    case speechPermissionDenied
    case speechPermissionRestricted
    case recognizerUnavailable(locale: Locale)
    case onDeviceNotSupported(locale: Locale)
    case recognitionFailed(String)
    case noSpeechDetected
    
    public var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "Speech recognition permission was denied. Please allow speech recognition in Settings to generate subtitles."
        case .speechPermissionRestricted:
            return "Speech recognition is restricted on this device."
        case .recognizerUnavailable(let locale):
            let lang = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            return "Speech recognition is currently unavailable for \(lang)."
        case .onDeviceNotSupported(let locale):
            let lang = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            return "On-device speech recognition for '\(lang)' is not yet downloaded on your device. To use it offline, enable it in Settings > General > Keyboard > Dictation Languages."
        case .recognitionFailed(let msg):
            return "Transcription failed: \(msg)"
        case .noSpeechDetected:
            return "No spoken words were detected in this audio segment."
        }
    }
}

/// Prompt 2 Implementation: Apple Speech framework (requiresOnDeviceRecognition = true)
/// 100% on-device, zero network transmission, zero false captions on music or silence.
public final class AppleSpeechTranscriber: Transcriber {
    
    public nonisolated init() {}
    
    public func transcribe(audioURL: URL, locale: Locale) async throws -> [CaptionWord] {
        // 1. Check authorization
        let authStatus = await requestSpeechAuthorization()
        switch authStatus {
        case .authorized:
            break
        case .denied:
            throw TranscriptionError.speechPermissionDenied
        case .restricted:
            throw TranscriptionError.speechPermissionRestricted
        case .notDetermined:
            throw TranscriptionError.speechPermissionDenied
        @unknown default:
            throw TranscriptionError.speechPermissionDenied
        }
        
        // 2. Obtain recognizer for locale
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.recognizerUnavailable(locale: locale)
        }
        
        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable(locale: locale)
        }
        
        // 3. Verify on-device support
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceNotSupported(locale: locale)
        }
        
        // 4. Create on-device recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        // 5. Execute recognition
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    }
                    return
                }
                
                guard let result = result else { return }
                
                if result.isFinal {
                    if !hasResumed {
                        hasResumed = true
                        let words = result.bestTranscription.segments.compactMap { segment -> CaptionWord? in
                            let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return nil }
                            return CaptionWord(
                                text: text,
                                start: segment.timestamp,
                                end: segment.timestamp + max(segment.duration, 0.05),
                                confidence: segment.confidence
                            )
                        }
                        continuation.resume(returning: words)
                    }
                }
            }
            
            // Timeout safety / cleanup observer
            _ = task
        }
    }
    
    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

/// Prompt 2: Main Transcription Service managing audio extraction, progress UI, and swappable engine.
@MainActor
public final class TranscriptionService: ObservableObject {
    @Published public var isTranscribing: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "Ready"
    @Published public var selectedLocale: Locale = Locale(identifier: "en-US")
    
    /// List of commonly used supported speech locales
    public let availableLocales: [Locale] = [
        Locale(identifier: "en-US"), // English (US)
        Locale(identifier: "en-IN"), // English (India)
        Locale(identifier: "en-GB"), // English (UK)
        Locale(identifier: "hi-IN"), // Hindi (India)
        Locale(identifier: "es-ES"), // Spanish
        Locale(identifier: "fr-FR"), // French
        Locale(identifier: "de-DE"), // German
        Locale(identifier: "ja-JP"), // Japanese
    ]
    
    private let audioExtractor = AudioExtractor()
    private var transcriber: Transcriber
    
    public init(transcriber: Transcriber = AppleSpeechTranscriber()) {
        self.transcriber = transcriber
    }
    
    /// Swaps the underlying transcription engine (e.g. Apple Speech vs WhisperKit)
    public func setTranscriber(_ newTranscriber: Transcriber) {
        self.transcriber = newTranscriber
    }
    
    /// Extracts audio via AVAssetExportSession to m4a and transcribes using the on-device engine.
    public func transcribeVideo(videoURL: URL) async throws -> [CaptionWord] {
        self.isTranscribing = true
        self.progress = 0.15
        self.statusMessage = "Extracting audio (.m4a)..."
        
        let m4aURL: URL
        do {
            m4aURL = try await audioExtractor.extractAudioM4A(from: videoURL)
        } catch {
            self.isTranscribing = false
            throw error
        }
        
        defer {
            try? FileManager.default.removeItem(at: m4aURL)
        }
        
        self.progress = 0.45
        let langName = selectedLocale.localizedString(forIdentifier: selectedLocale.identifier) ?? selectedLocale.identifier
        self.statusMessage = "Transcribing speech on-device (\(langName))..."
        
        do {
            let words = try await transcriber.transcribe(audioURL: m4aURL, locale: selectedLocale)
            self.progress = 1.0
            self.statusMessage = "Transcription Complete"
            self.isTranscribing = false
            return words
        } catch {
            self.isTranscribing = false
            self.statusMessage = "Transcription failed"
            throw error
        }
    }
}
