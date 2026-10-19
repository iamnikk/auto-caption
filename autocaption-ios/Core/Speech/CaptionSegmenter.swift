import Foundation

/// Pacing modes for chunking words into on-screen caption segments.
public enum PacingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case fast = "Fast (Reels/TikTok)"        // 1-3 words per segment
    case balanced = "Balanced"               // 4-6 words per segment
    case relaxed = "Relaxed (Sentences)"     // Full sentences, max 2 lines (~42 chars/line)
    
    public var id: String { rawValue }
    
    public var maxWords: Int {
        switch self {
        case .fast: return 3
        case .balanced: return 6
        case .relaxed: return 12
        }
    }
    
    public var maxCharacters: Int {
        switch self {
        case .fast: return 30
        case .balanced: return 50
        case .relaxed: return 84 // ~42 chars/line across 2 lines
        }
    }
}

/// Prompt 3: CaptionSegmenter groups [CaptionWord] into [CaptionSegment] respecting pacing, punctuation, and pauses.
public struct CaptionSegmenter {
    
    private static let terminalPunctuation: Set<Character> = [".", "!", "?", ";", ":"]
    private static let pauseThreshold: TimeInterval = 0.4 // 400ms pause triggers boundary
    
    /// Groups individual recognized words into bite-sized on-screen caption segments.
    public static func segment(
        words: [CaptionWord],
        pacing: PacingMode = .fast
    ) -> [CaptionSegment] {
        guard !words.isEmpty else { return [] }
        
        var segments: [CaptionSegment] = []
        var currentWords: [CaptionWord] = []
        
        for (index, word) in words.enumerated() {
            currentWords.append(word)
            
            let isLastWord = (index == words.count - 1)
            let nextWord = isLastWord ? nil : words[index + 1]
            
            // 1. Check if current word ends with terminal punctuation (. ! ?)
            let hasPunctuationBreak = word.text.last.map { terminalPunctuation.contains($0) } ?? false
            
            // 2. Check if pause between this word and next word exceeds 0.4 seconds
            let hasPauseBreak: Bool
            if let next = nextWord {
                hasPauseBreak = (next.start - word.end) > pauseThreshold
            } else {
                hasPauseBreak = false
            }
            
            // 3. Check pacing constraints (word count and character limits)
            let currentTextLength = currentWords.map(\.text).joined(separator: " ").count
            let reachedWordLimit = currentWords.count >= pacing.maxWords
            let reachedCharLimit = currentTextLength >= pacing.maxCharacters
            
            // Determine if a segment boundary should occur here
            let shouldBreak = isLastWord || hasPunctuationBreak || hasPauseBreak || reachedWordLimit || reachedCharLimit
            
            if shouldBreak && !currentWords.isEmpty {
                // Ensure timing validity: start <= end
                let startTime = currentWords.first!.start
                let endTime = max(currentWords.last!.end, startTime + 0.1)
                
                segments.append(CaptionSegment(
                    id: UUID(),
                    words: currentWords,
                    start: startTime,
                    end: endTime
                ))
                currentWords.removeAll()
            }
        }
        
        // Handle any trailing words
        if !currentWords.isEmpty {
            let startTime = currentWords.first!.start
            let endTime = max(currentWords.last!.end, startTime + 0.1)
            segments.append(CaptionSegment(
                id: UUID(),
                words: currentWords,
                start: startTime,
                end: endTime
            ))
        }
        
        return segments
    }
}
