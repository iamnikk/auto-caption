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
    case audioExtractionFailed
    
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
            return "On-device speech recognition for '\(lang)' is not yet downloaded on your device."
        case .recognitionFailed(let msg):
            return "Transcription failed: \(msg)"
        case .noSpeechDetected:
            return "No spoken words were detected in this audio segment."
        case .audioExtractionFailed:
            return "Could not extract audio track from video."
        }
    }
}

/// Apple Speech Framework Transcriber
public final class AppleSpeechTranscriber: Transcriber {
    
    public nonisolated init() {}
    
    public func transcribe(audioURL: URL, locale: Locale) async throws -> [CaptionWord] {
        let authStatus = await requestSpeechAuthorization()
        guard authStatus == .authorized else {
            throw TranscriptionError.speechPermissionDenied
        }
        
        let targetLocale = locale.identifier == "auto" ? Locale(identifier: "en-US") : locale
        guard let recognizer = SFSpeechRecognizer(locale: targetLocale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable(locale: targetLocale)
        }
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        // If device has on-device model installed, use it; otherwise allow system recognition
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            _ = recognizer.recognitionTask(with: request) { result, error in
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
                                end: segment.timestamp + max(segment.duration, 0.1),
                                confidence: segment.confidence
                            )
                        }
                        continuation.resume(returning: words)
                    }
                }
            }
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

/// Transcription Engine Mode
public enum TranscriptionEngineMode: String, CaseIterable, Identifiable {
    case whisperAI = "Whisper AI (Multilingual & Hindi)"
    case appleSpeech = "Apple Speech (System)"
    public var id: String { rawValue }
}

/// Prompt 2: Main Transcription Service managing audio extraction, progress UI, and swappable engine.
@MainActor
public final class TranscriptionService: ObservableObject {
    @Published public var isTranscribing: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "Ready"
    @Published public var selectedLocale: Locale = Locale(identifier: "auto")
    @Published public var engineMode: TranscriptionEngineMode = .whisperAI
    
    public let availableLocales: [Locale] = [
        Locale(identifier: "auto"),  // Auto-Detect (Whisper)
        Locale(identifier: "en-US"), // English (US)
        Locale(identifier: "hi-IN"), // Hindi (India)
        Locale(identifier: "en-IN"), // English (India)
        Locale(identifier: "es-ES"), // Spanish
        Locale(identifier: "fr-FR"), // French
        Locale(identifier: "de-DE"), // German
        Locale(identifier: "ja-JP")  // Japanese
    ]
    
    private let audioExtractor = AudioExtractor()
    public let whisperManager = WhisperManager()
    private let appleSpeechTranscriber = AppleSpeechTranscriber()
    
    public init() {}
    
    /// Transcribes video using Whisper AI (with auto language detection) or Apple Speech with automatic fallback.
    public func transcribeVideo(videoURL: URL) async throws -> [CaptionWord] {
        self.isTranscribing = true
        self.progress = 0.15
        self.statusMessage = "Extracting audio track..."
        
        let m4aURL: URL
        do {
            m4aURL = try await audioExtractor.extractAudioM4A(from: videoURL)
        } catch {
            self.isTranscribing = false
            self.statusMessage = "Audio extraction failed"
            throw TranscriptionError.audioExtractionFailed
        }
        defer { try? FileManager.default.removeItem(at: m4aURL) }
        
        // 1. Primary Engine: Whisper AI (supports 99+ languages, Hindi, Urdu, English without needing Apple dictation pack)
        if engineMode == .whisperAI {
            do {
                self.statusMessage = "Transcribing with Whisper AI..."
                self.progress = 0.40
                let words = try await whisperManager.transcribe(audioURL: m4aURL, locale: selectedLocale)
                
                if !words.isEmpty {
                    self.progress = 1.0
                    self.statusMessage = "Transcription Complete (\(words.count) words)"
                    self.isTranscribing = false
                    return words
                }
            } catch {
                print("⚠️ Whisper AI returned error, falling back to Apple Speech: \(error.localizedDescription)")
            }
        }
        
        // 2. Secondary Engine / Fallback: Apple Speech
        do {
            self.statusMessage = "Transcribing with Apple Speech..."
            self.progress = 0.70
            let words = try await appleSpeechTranscriber.transcribe(audioURL: m4aURL, locale: selectedLocale)
            
            if !words.isEmpty {
                self.progress = 1.0
                self.statusMessage = "Transcription Complete (\(words.count) words)"
                self.isTranscribing = false
                return words
            }
        } catch {
            print("⚠️ Apple Speech failed: \(error.localizedDescription)")
        }
        
        // 3. Fallback: If Apple Speech was preferred but failed, try Whisper AI
        if engineMode != .whisperAI {
            do {
                self.statusMessage = "Falling back to Whisper AI..."
                self.progress = 0.85
                let words = try await whisperManager.transcribe(audioURL: m4aURL, locale: selectedLocale)
                if !words.isEmpty {
                    self.progress = 1.0
                    self.statusMessage = "Transcription Complete (\(words.count) words)"
                    self.isTranscribing = false
                    return words
                }
            } catch {
                print("⚠️ Fallback to Whisper AI also failed: \(error.localizedDescription)")
            }
        }
        
        self.isTranscribing = false
        self.statusMessage = "No speech detected in audio"
        return []
    }
}
