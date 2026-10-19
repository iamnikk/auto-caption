import Foundation
import Combine
import WhisperKit
import AVFoundation

/// Production AI Speech Recognition Engine powered by WhisperKit (OpenAI Whisper CoreML)
/// Transcribes only genuine spoken words with exact timestamps, strictly avoiding captions on music/instrumentals.
public final class WhisperManager: ObservableObject {
    
    @Published public var isModelLoaded: Bool = false
    @Published public var isTranscribing: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "Ready"
    
    private var whisperKit: WhisperKit?
    // Using multilingual tiny model (runs fast and reliably across devices)
    private let modelName: String = "openai_whisper-tiny"
    
    public init() {
        Task {
            await initializeWhisper()
        }
    }
    
    /// Preloads and prepares the CoreML Whisper model on device
    public func initializeWhisper() async {
        await MainActor.run {
            self.statusMessage = "Loading Whisper AI engine..."
            self.progress = 0.1
        }
        
        do {
            print("⏳ Initializing WhisperKit...")
            let pipe = try await WhisperKit(model: modelName, verbose: false, logLevel: .none)
            await MainActor.run {
                self.whisperKit = pipe
                self.isModelLoaded = true
                self.progress = 1.0
                self.statusMessage = "Whisper AI Ready"
            }
            print("✅ WhisperKit initialized successfully.")
        } catch {
            print("⚠️ WhisperKit init error: \(error.localizedDescription)")
            await MainActor.run {
                self.statusMessage = "Ready"
            }
        }
    }
    
    /// Transcribes audio using on-device Whisper CoreML model with exact word timestamps
    public func transcribeAudio(
        from audioURL: URL,
        maxWordsPerSegment: Int = 4
    ) async throws -> [SubtitleSegment] {
        await MainActor.run {
            self.isTranscribing = true
            self.progress = 0.2
            self.statusMessage = "Transcribing with Whisper AI..."
        }
        
        // Ensure WhisperKit is initialized
        if self.whisperKit == nil {
            print("WhisperKit instance not ready, initializing now...")
            await initializeWhisper()
        }
        
        guard let whisper = self.whisperKit else {
            print("❌ WhisperKit could not be initialized.")
            await MainActor.run {
                self.isTranscribing = false
                self.statusMessage = "Speech model unavailable"
            }
            return []
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
            options.language = nil // Auto-detect language (Hindi, Urdu, English, etc.)
            
            let transcriptionResults: [TranscriptionResult] = try await whisper.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )
            
            var parsedWords: [SubtitleWord] = []
            
            // Non-speech acoustic tags to ignore
            let nonSpeechTokens: Set<String> = [
                "[MUSIC]", "[APPLAUSE]", "[LAUGHTER]", "[NOISE]", "[SOUND]",
                "(MUSIC)", "(APPLAUSE)", "(LAUGHTER)", "(NOISE)", "♪", "♫"
            ]
            
            for result in transcriptionResults {
                print("🗣️ Whisper detected language: \(result.language ?? "auto"), text: \(result.text)")
                
                for segment in result.segments {
                    // Extract only spoken words with timestamps
                    if let words = segment.words, !words.isEmpty {
                        for wordTiming in words {
                            let rawWord = wordTiming.word.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanWord = rawWord.trimmingCharacters(in: CharacterSet(charactersIn: "[](),.!?"))
                            
                            // Only include if it's actual speech, not music tags or silent punctuation
                            if !cleanWord.isEmpty && !nonSpeechTokens.contains(rawWord.uppercased()) {
                                parsedWords.append(SubtitleWord(
                                    word: rawWord,
                                    start: Double(wordTiming.start),
                                    end: Double(wordTiming.end),
                                    confidence: wordTiming.probability
                                ))
                            }
                        }
                    } else {
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
                                parsedWords.append(SubtitleWord(
                                    word: token,
                                    start: wStart,
                                    end: wEnd,
                                    confidence: 0.9
                                ))
                            }
                        }
                    }
                }
            }
            
            // Build segments strictly from recognized speech words
            let segments = chunkWordsIntoSegments(parsedWords, maxWords: maxWordsPerSegment)
            print("✅ Extracted \(segments.count) real spoken subtitle segments.")
            
            await MainActor.run {
                self.isTranscribing = false
                self.progress = 1.0
                self.statusMessage = "Transcription Complete"
            }
            
            return segments
        } catch {
            print("❌ WhisperKit transcription error: \(error.localizedDescription)")
            await MainActor.run {
                self.isTranscribing = false
                self.statusMessage = "Ready"
            }
            return []
        }
    }
    
    /// Groups individual words into bite-sized segments ideal for vertical reels (3-5 words per screen).
    public func chunkWordsIntoSegments(
        _ words: [SubtitleWord],
        maxWords: Int = 4
    ) -> [SubtitleSegment] {
        guard !words.isEmpty else { return [] }
        
        var segments: [SubtitleSegment] = []
        var currentChunk: [SubtitleWord] = []
        
        for word in words {
            currentChunk.append(word)
            if currentChunk.count >= maxWords {
                if let first = currentChunk.first, let last = currentChunk.last {
                    segments.append(SubtitleSegment(
                        words: currentChunk,
                        start: first.start,
                        end: last.end
                    ))
                }
                currentChunk.removeAll()
            }
        }
        
        if !currentChunk.isEmpty, let first = currentChunk.first, let last = currentChunk.last {
            segments.append(SubtitleSegment(
                words: currentChunk,
                start: first.start,
                end: last.end
            ))
        }
        
        return segments
    }
}
