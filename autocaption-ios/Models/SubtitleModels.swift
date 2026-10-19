import Foundation
import SwiftUI

/// Represents a single word recognized by the AI speech-to-text model with exact timestamps.
public struct SubtitleWord: Identifiable, Codable, Equatable {
    public let id: UUID
    public var word: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var confidence: Float
    
    public init(
        id: UUID = UUID(),
        word: String,
        start: TimeInterval,
        end: TimeInterval,
        confidence: Float = 1.0
    ) {
        self.id = id
        self.word = word
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

/// Represents a subtitle segment (phrase or 3-5 word chunk) displayed on screen at once.
public struct SubtitleSegment: Identifiable, Codable, Equatable {
    public let id: UUID
    public var words: [SubtitleWord]
    public var start: TimeInterval
    public var end: TimeInterval
    
    public var text: String {
        words.map { $0.word }.joined(separator: " ")
    }
    
    public init(
        id: UUID = UUID(),
        words: [SubtitleWord],
        start: TimeInterval,
        end: TimeInterval
    ) {
        self.id = id
        self.words = words
        self.start = start
        self.end = end
    }
}

/// Available animated caption styles inspired by viral Reels/Shorts formats.
public enum CaptionStylePreset: String, CaseIterable, Identifiable, Codable {
    case karaokeHighlight = "Karaoke Highlight" // Active word changes color as spoken
    case wordPop = "Word Pop"                   // Active word pops up / scales with spring
    case backgroundPill = "Color Box"           // Active word highlighted with a rounded pill background
    case boldOutline = "Bold Outline"           // Classic bold white text with black stroke
    case minimalSub = "Minimal Subtitle"        // Clean lower-third subtitles
    
    public var id: String { rawValue }
}

/// Caption visual customization settings.
public struct CaptionStyle: Codable, Equatable {
    public var preset: CaptionStylePreset
    public var fontName: String
    public var fontSize: CGFloat
    public var textColorHex: String
    public var highlightColorHex: String
    public var backgroundColorHex: String?
    public var strokeColorHex: String?
    public var strokeWidth: CGFloat
    public var maxWordsPerSegment: Int
    public var verticalPositionPercentage: CGFloat // 0.0 top, 0.5 center, 0.8 bottom
    
    public init(
        preset: CaptionStylePreset = .karaokeHighlight,
        fontName: String = "HelveticaNeue-Black",
        fontSize: CGFloat = 32.0,
        textColorHex: String = "#FFFFFF",
        highlightColorHex: String = "#FFDE03", // Vivid yellow
        backgroundColorHex: String? = nil,
        strokeColorHex: String? = "#000000",
        strokeWidth: CGFloat = 3.0,
        maxWordsPerSegment: Int = 4,
        verticalPositionPercentage: CGFloat = 0.75
    ) {
        self.preset = preset
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColorHex = textColorHex
        self.highlightColorHex = highlightColorHex
        self.backgroundColorHex = backgroundColorHex
        self.strokeColorHex = strokeColorHex
        self.strokeWidth = strokeWidth
        self.maxWordsPerSegment = maxWordsPerSegment
        self.verticalPositionPercentage = verticalPositionPercentage
    }
}
