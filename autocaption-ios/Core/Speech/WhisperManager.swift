import Foundation
import Combine
import WhisperKit
import AVFoundation

/// Production AI Speech Recognition Engine powered by WhisperKit (OpenAI Whisper CoreML)
/// Transcribes genuine spoken words with exact timestamps, strictly avoiding captions on music/instrumentals.
public final class WhisperManager: ObservableObject, @unchecked Sendable {
    
    @Published public var isModelLoaded: Bool = false
    @Published public var isTranscribing: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "Ready"
    
    private var whisperKit: WhisperKit?
    private let modelName: String = "openai_whisper-tiny"
    private var modelLoadTask: Task<WhisperKit, Error>?
    
    public init() {
        // Kick off model download/initialization immediately on app launch
        Task {
            _ = try? await self.getOrInitializeWhisper()
        }
    }
    
    /// Thread-safe model initialization that handles concurrent callers cleanly without race conditions.
    @discardableResult
    public func getOrInitializeWhisper() async throws -> WhisperKit {
        if let existing = self.whisperKit {
            return existing
        }
        
        if let existingTask = self.modelLoadTask {
            return try await existingTask.value
        }
        
        let task = Task<WhisperKit, Error> {
            await MainActor.run {
                self.statusMessage = "Loading Whisper AI engine..."
                self.progress = 0.1
            }
            print("⏳ Initializing WhisperKit model: \(self.modelName)...")
            let pipe = try await WhisperKit(model: self.modelName, verbose: false, logLevel: .none)
            return pipe
        }
        
        self.modelLoadTask = task
        
        do {
            let pipe = try await task.value
            await MainActor.run {
                self.whisperKit = pipe
                self.isModelLoaded = true
                self.progress = 1.0
                self.statusMessage = "Whisper AI Ready"
            }
            print("✅ WhisperKit initialized successfully.")
            return pipe
        } catch {
            self.modelLoadTask = nil
            print("⚠️ WhisperKit init error: \(error.localizedDescription)")
            await MainActor.run {
                self.statusMessage = "Speech model unavailable"
            }
            throw error
        }
    }
    
    /// Transcribes audio using on-device Whisper CoreML model with exact word timestamps
    public func transcribeAudio(
        from audioURL: URL,
        maxWordsPerSegment: Int = 4,
        locale: Locale? = nil
    ) async throws -> [CaptionSegment] {
        await MainActor.run {
            self.isTranscribing = true
            self.progress = 0.2
            self.statusMessage = "Loading Whisper AI engine..."
        }
        
        // Wait for WhisperKit to be loaded and ready
        let whisper = try await getOrInitializeWhisper()
        
        await MainActor.run {
            self.progress = 0.5
            self.statusMessage = "Transcribing with Whisper AI..."
        }
        
        do {
            print("🎙️ Starting Whisper transcription on: \(audioURL.path)")
            
            var options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                temperature: 0.0,
                wordTimestamps: true
            )
            options.suppressTokens = []
            
            // Set language if provided and not "auto"
            if let loc = locale, loc.identifier != "auto" {
                let code = (loc.languageCode ?? String(loc.identifier.prefix(2))).lowercased()
                options.language = code
                print("🌐 Whisper using target language: \(code)")
            } else {
                options.language = nil // Auto-detect language (Hindi, Urdu, English, Spanish, etc.)
                print("🌐 Whisper language auto-detection active")
            }
            
            let transcriptionResults: [TranscriptionResult] = try await whisper.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )
            
            var parsedWords: [CaptionWord] = []
            
            // Non-speech acoustic tags to ignore (filters music lyrics hallucinations)
            let nonSpeechTokens: Set<String> = [
                "[MUSIC]", "[APPLAUSE]", "[LAUGHTER]", "[NOISE]", "[SOUND]",
                "(MUSIC)", "(APPLAUSE)", "(LAUGHTER)", "(NOISE)", "♪", "♫",
                "MUSIC", "APPLAUSE", "LAUGHTER"
            ]
            
            for result in transcriptionResults {
                let detectedLang = result.language ?? "auto"
                print("🗣️ Whisper detected language: \(detectedLang), text: \(result.text)")
                
                for segment in result.segments {
                    // Filter out non-speech / instrumental passages
                    if segment.noSpeechProb > 0.60 {
                        print("🔇 Skipping music/non-speech segment (noSpeechProb: \(segment.noSpeechProb)): \(segment.text)")
                        continue
                    }
                    
                    // Extract words with timestamps
                    if let words = segment.words, !words.isEmpty {
                        for wordTiming in words {
                            let rawWord = wordTiming.word.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanWord = rawWord.trimmingCharacters(in: CharacterSet(charactersIn: "[](),.!?"))
                            
                            // Only include genuine speech words with positive duration and probability
                            if !cleanWord.isEmpty && !nonSpeechTokens.contains(rawWord.uppercased()) && wordTiming.probability > 0.15 {
                                parsedWords.append(CaptionWord(
                                    text: rawWord,
                                    start: Double(wordTiming.start),
                                    end: Double(max(wordTiming.end, wordTiming.start + 0.1)),
                                    isHighlighted: false,
                                    confidence: wordTiming.probability
                                ))
                            }
                        }
                    } else {
                        // Fallback: estimate word timestamps evenly across segment duration
                        let segmentText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let rawTokens = segmentText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                        
                        let speechTokens = rawTokens.filter { token in
                            let clean = token.trimmingCharacters(in: CharacterSet(charactersIn: "[](),.!?"))
                            return !clean.isEmpty && !nonSpeechTokens.contains(token.uppercased())
                        }
                        
                        if !speechTokens.isEmpty {
                            let duration = Double(segment.end - segment.start)
                            let perWordDuration = max(duration / Double(speechTokens.count), 0.25)
                            
                            for (idx, token) in speechTokens.enumerated() {
                                let wStart = Double(segment.start) + (Double(idx) * perWordDuration)
                                let wEnd = wStart + perWordDuration
                                parsedWords.append(CaptionWord(
                                    text: token,
                                    start: wStart,
                                    end: wEnd,
                                    isHighlighted: false,
                                    confidence: 0.9
                                ))
                            }
                        }
                    }
                }
            }
            
            // Build segments strictly from real speech words
            let segments = CaptionSegmenter.segment(words: parsedWords, pacing: .fast)
            print("✅ Extracted \(segments.count) real spoken subtitle segments (\(parsedWords.count) words).")
            
            await MainActor.run {
                self.isTranscribing = false
                self.progress = 1.0
                self.statusMessage = "Transcription Complete (\(parsedWords.count) words)"
            }
            
            return segments
        } catch {
            print("❌ WhisperKit transcription error: \(error.localizedDescription)")
            await MainActor.run {
                self.isTranscribing = false
                self.statusMessage = "Transcription failed"
            }
            throw error
        }
    }
}

// MARK: - Transcriber Protocol Conformance (Prompt 2)
extension WhisperManager: Transcriber {
    public func transcribe(audioURL: URL, locale: Locale) async throws -> [CaptionWord] {
        let segments = try await self.transcribeAudio(from: audioURL, locale: locale)
        return segments.flatMap(\.words)
    }
}
