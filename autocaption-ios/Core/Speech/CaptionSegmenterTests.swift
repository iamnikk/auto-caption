import Foundation

/// Prompt 3 Unit Tests: Verifies CaptionSegmenter timing invariants and pacing limits.
public struct CaptionSegmenterTests {
    
    public static func runAllTests() -> Bool {
        print("🧪 Running CaptionSegmenter Unit Tests...")
        testNonOverlappingTiming()
        testFastPacingLimit()
        testBalancedPacingLimit()
        testPauseBreakThreshold()
        testPunctuationBreak()
        print("✅ All CaptionSegmenter Unit Tests Passed Successfully!")
        return true
    }
    
    /// Test 1: Verify that segments never overlap in time
    public static func testNonOverlappingTiming() {
        let sampleWords: [CaptionWord] = [
            CaptionWord(text: "Create", start: 0.0, end: 0.3),
            CaptionWord(text: "viral", start: 0.35, end: 0.6),
            CaptionWord(text: "captions", start: 0.65, end: 1.0),
            CaptionWord(text: "instantly", start: 1.5, end: 1.9), // Pause > 0.4s
            CaptionWord(text: "with", start: 1.95, end: 2.1),
            CaptionWord(text: "AI", start: 2.15, end: 2.4)
        ]
        
        let segments = CaptionSegmenter.segment(words: sampleWords, pacing: .fast)
        assert(!segments.isEmpty, "Segments should not be empty")
        
        for i in 0..<(segments.count - 1) {
            let current = segments[i]
            let next = segments[i + 1]
            assert(current.start < current.end, "Segment start must be strictly before end")
            assert(current.end <= next.start + 0.001, "Segments must never overlap: \(current.end) > \(next.start)")
        }
    }
    
    /// Test 2: Verify .fast pacing never exceeds 3 words per segment
    public static func testFastPacingLimit() {
        let words: [CaptionWord] = (0..<10).map { i in
            CaptionWord(text: "Word\(i)", start: Double(i) * 0.3, end: Double(i) * 0.3 + 0.25)
        }
        
        let segments = CaptionSegmenter.segment(words: words, pacing: .fast)
        for seg in segments {
            assert(seg.words.count <= PacingMode.fast.maxWords, "Segment has \(seg.words.count) words, which exceeds .fast limit of 3")
        }
    }
    
    /// Test 3: Verify .balanced pacing never exceeds 6 words per segment
    public static func testBalancedPacingLimit() {
        let words: [CaptionWord] = (0..<15).map { i in
            CaptionWord(text: "Word\(i)", start: Double(i) * 0.3, end: Double(i) * 0.3 + 0.25)
        }
        
        let segments = CaptionSegmenter.segment(words: words, pacing: .balanced)
        for seg in segments {
            assert(seg.words.count <= PacingMode.balanced.maxWords, "Segment exceeds .balanced limit of 6")
        }
    }
    
    /// Test 4: Verify that a pause > 0.4s triggers a segment break
    public static func testPauseBreakThreshold() {
        let words: [CaptionWord] = [
            CaptionWord(text: "Hello", start: 1.0, end: 1.3),
            CaptionWord(text: "World", start: 2.0, end: 2.4) // 0.7s pause (> 0.4s)
        ]
        
        let segments = CaptionSegmenter.segment(words: words, pacing: .balanced)
        assert(segments.count == 2, "Expected 2 segments due to pause > 0.4s, got \(segments.count)")
        assert(segments[0].text == "Hello")
        assert(segments[1].text == "World")
    }
    
    /// Test 5: Verify terminal punctuation triggers an immediate segment boundary
    public static func testPunctuationBreak() {
        let words: [CaptionWord] = [
            CaptionWord(text: "Stop.", start: 0.0, end: 0.3),
            CaptionWord(text: "Go", start: 0.35, end: 0.6)
        ]
        
        let segments = CaptionSegmenter.segment(words: words, pacing: .relaxed)
        assert(segments.count == 2, "Expected punctuation to break into 2 segments, got \(segments.count)")
        assert(segments[0].text == "Stop.")
        assert(segments[1].text == "Go")
    }
}
