import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Prompt 0: Domain Models

/// CaptionWord: Represents a single word with exact start/end timestamps, confidence, and keyword emphasis state.
public struct CaptionWord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var isHighlighted: Bool
    public var confidence: Float
    
    /// Alias for backwards compatibility
    public var word: String {
        get { text }
        set { text = newValue }
    }
    
    public init(
        id: UUID = UUID(),
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        isHighlighted: Bool = false,
        confidence: Float = 1.0
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.isHighlighted = isHighlighted
        self.confidence = confidence
    }
    
    public init(
        id: UUID = UUID(),
        word: String,
        start: TimeInterval,
        end: TimeInterval,
        isHighlighted: Bool = false,
        confidence: Float = 1.0
    ) {
        self.init(id: id, text: word, start: start, end: end, isHighlighted: isHighlighted, confidence: confidence)
    }
}

/// CaptionSegment: Represents a chunk of words displayed on screen at once.
public struct CaptionSegment: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var words: [CaptionWord]
    public var start: TimeInterval
    public var end: TimeInterval
    
    public var text: String {
        words.map(\.text).joined(separator: " ")
    }
    
    public init(
        id: UUID = UUID(),
        words: [CaptionWord],
        start: TimeInterval,
        end: TimeInterval
    ) {
        self.id = id
        self.words = words
        self.start = start
        self.end = end
    }
}

/// Animation styles
public enum CaptionAnimation: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "None"
    case fade = "Fade"
    case popScale = "Pop Scale"
    case slideUp = "Slide Up"
    case karaokeHighlight = "Karaoke Highlight"
    
    public var id: String { rawValue }
}

/// Positioning on video frame
public struct CaptionPosition: Codable, Equatable, Sendable {
    public var verticalOffsetPercentage: CGFloat   // 0.0 top, 0.5 center, 0.75 lower third
    public var horizontalOffsetPercentage: CGFloat // 0.5 center
    
    public init(vertical: CGFloat = 0.75, horizontal: CGFloat = 0.5) {
        self.verticalOffsetPercentage = vertical
        self.horizontalOffsetPercentage = horizontal
    }
}

/// 10 Starter Style Presets (Prompt 5)
public enum CaptionStylePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case minimal = "Minimal"
    case boldPop = "Bold Pop"
    case karaokeHighlight = "Karaoke"
    case typewriter = "Typewriter"
    case bounce = "Bounce"
    case glow = "Glow"
    case outline = "Outline"
    case boxed = "Boxed"
    case gradient = "Gradient"
    case handwritten = "Handwritten"
    
    public var id: String { rawValue }
}

/// CaptionStyle: Visual presentation configuration
public struct CaptionStyle: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var preset: CaptionStylePreset
    public var fontName: String
    public var fontSize: CGFloat
    public var textColor: String          // Hex string, e.g. "#FFFFFF"
    public var highlightColor: String      // Hex string, e.g. "#FFDE03"
    public var strokeColor: String?        // Hex string, e.g. "#000000"
    public var strokeWidth: CGFloat
    public var backgroundColor: String?    // Hex string, e.g. "#00000080"
    public var position: CaptionPosition
    public var animation: CaptionAnimation
    
    // Legacy compatibility helpers
    public var textColorHex: String { textColor }
    public var highlightColorHex: String { highlightColor }
    public var strokeColorHex: String? { strokeColor }
    public var backgroundColorHex: String? { backgroundColor }
    public var verticalPositionPercentage: CGFloat { position.verticalOffsetPercentage }
    
    public init(
        id: UUID = UUID(),
        name: String = "Karaoke Pop",
        preset: CaptionStylePreset = .karaokeHighlight,
        fontName: String = "HelveticaNeue-Black",
        fontSize: CGFloat = 32.0,
        textColor: String = "#FFFFFF",
        highlightColor: String = "#FFDE03",
        strokeColor: String? = "#000000",
        strokeWidth: CGFloat = 3.0,
        backgroundColor: String? = nil,
        position: CaptionPosition = CaptionPosition(vertical: 0.75, horizontal: 0.5),
        animation: CaptionAnimation = .karaokeHighlight
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.highlightColor = highlightColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.backgroundColor = backgroundColor
        self.position = position
        self.animation = animation
    }
}

/// Aspect ratio presets
public enum AspectRatio: String, CaseIterable, Identifiable, Codable, Sendable {
    case portrait9_16 = "9:16"
    case square1_1 = "1:1"
    case portrait4_5 = "4:5"
    case landscape16_9 = "16:9"
    
    public var id: String { rawValue }
    
    public var ratio: CGFloat {
        switch self {
        case .portrait9_16: return 9.0 / 16.0
        case .square1_1: return 1.0 / 1.0
        case .portrait4_5: return 4.0 / 5.0
        case .landscape16_9: return 16.0 / 9.0
        }
    }
}

/// Extracted video metadata
public struct VideoMetadata: Codable, Equatable, Sendable {
    public var duration: TimeInterval
    public var resolution: CGSize
    public var isPortrait: Bool
    
    public init(duration: TimeInterval, resolution: CGSize, isPortrait: Bool) {
        self.duration = duration
        self.resolution = resolution
        self.isPortrait = isPortrait
    }
}

/// Project encompassing video source, segments, style, and aspect ratio
public struct Project: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var sourceVideoURL: URL
    public var segments: [CaptionSegment]
    public var style: CaptionStyle
    public var aspectRatio: AspectRatio
    public var metadata: VideoMetadata?
    
    public init(
        id: UUID = UUID(),
        sourceVideoURL: URL,
        segments: [CaptionSegment] = [],
        style: CaptionStyle = CaptionStyle(),
        aspectRatio: AspectRatio = .portrait9_16,
        metadata: VideoMetadata? = nil
    ) {
        self.id = id
        self.sourceVideoURL = sourceVideoURL
        self.segments = segments
        self.style = style
        self.aspectRatio = aspectRatio
        self.metadata = metadata
    }
}

// Backward-compatibility aliases
public typealias SubtitleWord = CaptionWord
public typealias SubtitleSegment = CaptionSegment
