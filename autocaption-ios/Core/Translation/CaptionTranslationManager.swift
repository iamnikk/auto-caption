import Foundation
import Translation
import SwiftUI
import Combine

/// Prompt 11: Caption Translation Manager using Apple's on-device Translation framework.
/// Translates recognized segments while preserving exact timing synchronization.
@MainActor
public final class CaptionTranslationManager: ObservableObject {
    
    @Published public var isTranslating: Bool = false
    @Published public var translationProgress: Double = 0.0
    @Published public var targetLanguage: Locale.Language = Locale.Language(identifier: "hi") // Default Hindi
    
    public init() {}
    
    /// Supported on-device translation target languages
    public let supportedLanguages: [(name: String, code: String)] = [
        ("Hindi", "hi"),
        ("Spanish", "es"),
        ("French", "fr"),
        ("German", "de"),
        ("Japanese", "ja"),
        ("Italian", "it"),
        ("Portuguese", "pt"),
        ("Korean", "ko"),
        ("Chinese (Simplified)", "zh-Hans")
    ]
    
    /// Translates all segments using Apple's Translation session while preserving start/end timestamps.
    @available(iOS 17.4, *)
    public func translateSegments(
        _ segments: [CaptionSegment],
        using session: TranslationSession
    ) async throws -> [CaptionSegment] {
        self.isTranslating = true
        self.translationProgress = 0.1
        
        var translatedSegments: [CaptionSegment] = []
        let total = Double(segments.count)
        
        for (idx, segment) in segments.enumerated() {
            let originalText = segment.text
            
            do {
                let response = try await session.translate(originalText)
                let translatedText = response.targetText
                
                // Distribute timestamps proportionally across translated words
                let translatedTokens = translatedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                let duration = segment.end - segment.start
                let perWordDuration = max(duration / Double(max(translatedTokens.count, 1)), 0.1)
                
                var translatedWords: [CaptionWord] = []
                for (wIdx, token) in translatedTokens.enumerated() {
                    let wStart = segment.start + (Double(wIdx) * perWordDuration)
                    let wEnd = min(wStart + perWordDuration, segment.end)
                    translatedWords.append(CaptionWord(
                        text: token,
                        start: wStart,
                        end: wEnd,
                        isHighlighted: false
                    ))
                }
                
                translatedSegments.append(CaptionSegment(
                    id: segment.id,
                    words: translatedWords.isEmpty ? segment.words : translatedWords,
                    start: segment.start,
                    end: segment.end
                ))
            } catch {
                // If single translation fails, preserve original segment
                translatedSegments.append(segment)
            }
            
            self.translationProgress = Double(idx + 1) / total
        }
        
        self.isTranslating = false
        return translatedSegments
    }
}
