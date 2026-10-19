import SwiftUI
import AVKit

/// High-performance animated caption overlay synchronized with video playback at 60fps.
public struct CaptionOverlayView: View {
    public let currentTime: TimeInterval
    public let segments: [SubtitleSegment]
    public let style: CaptionStyle
    
    public init(
        currentTime: TimeInterval,
        segments: [SubtitleSegment],
        style: CaptionStyle
    ) {
        self.currentTime = currentTime
        self.segments = segments
        self.style = style
    }
    
    /// Finds the currently active segment only when a person is actively speaking
    private var activeSegment: SubtitleSegment? {
        // 1. Exact match when words are being spoken
        if let direct = segments.first(where: { currentTime >= $0.start && currentTime <= $0.end }) {
            return direct
        }
        // 2. Micro-grace period (0.3s) between adjacent words in a sentence
        if let lingering = segments.last(where: { currentTime >= $0.end && (currentTime - $0.end) <= 0.3 }) {
            return lingering
        }
        // When there is music or silence: show nothing (just like TikTok/App Store app)
        return nil
    }
    
    public var body: some View {
        VStack {
            Spacer()
            if let segment = activeSegment {
                renderSegment(segment)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: segment.id)
            }
            Spacer()
                .frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func renderSegment(_ segment: SubtitleSegment) -> some View {
        HStack(spacing: 8) {
            ForEach(segment.words) { word in
                // Active if currentTime is in word range, or if it's the latest spoken word in the segment
                let isActive = currentTime >= word.start && currentTime <= word.end
                renderWord(word.word, isActive: isActive)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Group {
                if let bgHex = style.backgroundColorHex {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: bgHex))
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.35))
                }
            }
        )
    }
    
    @ViewBuilder
    private func renderWord(_ text: String, isActive: Bool) -> some View {
        switch style.preset {
        case .karaokeHighlight:
            Text(text.uppercased())
                .font(.system(size: style.fontSize, weight: .heavy, design: .rounded))
                .foregroundColor(isActive ? Color(hex: style.highlightColorHex) : Color(hex: style.textColorHex))
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 2)
                .scaleEffect(isActive ? 1.08 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isActive)
                
        case .boldPop:
            Text(text.uppercased())
                .font(.system(size: style.fontSize, weight: .black))
                .foregroundColor(isActive ? Color(hex: style.highlightColorHex) : Color(hex: style.textColorHex))
                .scaleEffect(isActive ? 1.25 : 1.0)
                .rotationEffect(.degrees(isActive ? -2 : 0))
                .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 2)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isActive)
                
        case .boxed:
            Text(text.uppercased())
                .font(.system(size: style.fontSize, weight: .bold))
                .foregroundColor(isActive ? .black : Color(hex: style.textColorHex))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isActive ? RoundedRectangle(cornerRadius: 8).fill(Color(hex: style.highlightColorHex)) : nil
                )
                
        case .outline, .minimal:
            Text(text)
                .font(.system(size: style.fontSize, weight: .bold))
                .foregroundColor(isActive ? Color(hex: style.highlightColorHex) : Color(hex: style.textColorHex))
                .shadow(color: .black, radius: 2, x: 1, y: 1)
                
        case .typewriter:
            Text(text)
                .font(.system(size: style.fontSize, weight: .medium, design: .monospaced))
                .foregroundColor(isActive ? Color(hex: style.highlightColorHex) : Color(hex: style.textColorHex))
                
        case .bounce:
            Text(text.uppercased())
                .font(.system(size: style.fontSize, weight: .heavy))
                .foregroundColor(isActive ? Color(hex: style.highlightColorHex) : Color(hex: style.textColorHex))
                .offset(y: isActive ? -6 : 0)
                .animation(.interpolatingSpring(stiffness: 300, damping: 10), value: isActive)
                
        case .glow:
            Text(text.uppercased())
                .font(.system(size: style.fontSize, weight: .heavy))
                .foregroundColor(isActive ? Color(hex: style.highlightColorHex) : Color(hex: style.textColorHex))
                .shadow(color: isActive ? Color(hex: style.highlightColorHex) : .clear, radius: 8)
                
        case .gradient:
            Text(text.uppercased())
                .font(.system(size: style.fontSize, weight: .black, design: .rounded))
                .foregroundColor(isActive ? Color(hex: style.highlightColorHex) : Color(hex: style.textColorHex))
                .shadow(color: .purple.opacity(0.5), radius: 3)
                
        case .handwritten:
            Text(text)
                .font(.system(size: style.fontSize, weight: .bold, design: .serif))
                .italic()
                .foregroundColor(isActive ? Color(hex: style.highlightColorHex) : Color(hex: style.textColorHex))
        }
    }
}


// MARK: - Live Animation Preview
#Preview("Animated Subtitles") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        CaptionOverlayView(
            currentTime: 1.2,
            segments: [
                SubtitleSegment(
                    words: [
                        SubtitleWord(word: "CREATE", start: 0.5, end: 0.9),
                        SubtitleWord(word: "VIRAL", start: 1.0, end: 1.4),
                        SubtitleWord(word: "CAPTIONS", start: 1.5, end: 2.0)
                    ],
                    start: 0.5,
                    end: 2.0
                )
            ],
            style: CaptionStyle(preset: .karaokeHighlight)
        )
    }
}
