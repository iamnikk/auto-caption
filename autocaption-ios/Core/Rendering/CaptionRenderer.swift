import Foundation
import QuartzCore
import UIKit
import CoreGraphics
import AVFoundation

/// Prompt 5: Shared CaptionRenderer that constructs a CALayer tree for captions.
/// Used BOTH in live preview and in AVVideoCompositionCoreAnimationTool for 100% export parity.
public final class CaptionRenderer: @unchecked Sendable {
    
    public init() {}
    
    /// Builds the root CALayer containing all animated caption segments synchronized to video duration.
    public func buildCaptionLayerTree(
        for segments: [CaptionSegment],
        style: CaptionStyle,
        renderSize: CGSize,
        videoDuration: TimeInterval
    ) -> CALayer {
        let rootLayer = CALayer()
        rootLayer.frame = CGRect(origin: .zero, size: renderSize)
        rootLayer.masksToBounds = true
        rootLayer.backgroundColor = UIColor.clear.cgColor
        
        // Scale font proportionally according to export renderSize width (base 1080)
        let scaleFactor = renderSize.width / 390.0 // 390 is typical iPhone screen width
        let scaledFontSize = style.fontSize * scaleFactor
        let strokeWidth = style.strokeWidth * scaleFactor
        
        let fontName = style.fontName.isEmpty ? "HelveticaNeue-Black" : style.fontName
        let font = UIFont(name: fontName, size: scaledFontSize) ?? UIFont.systemFont(ofSize: scaledFontSize, weight: .bold)
        
        // Vertical positioning
        let yPos = renderSize.height * style.position.verticalOffsetPercentage
        
        for segment in segments {
            guard segment.end > segment.start else { continue }
            
            let segmentLayer = CALayer()
            segmentLayer.opacity = 0.0
            
            // Calculate total width and layout of words
            let fullText = segment.text
            let textSize = (fullText as NSString).size(withAttributes: [.font: font])
            let boxPaddingH: CGFloat = 24.0 * scaleFactor
            let boxPaddingV: CGFloat = 12.0 * scaleFactor
            
            let segmentWidth = min(textSize.width + (boxPaddingH * 2), renderSize.width * 0.92)
            let segmentHeight = textSize.height + (boxPaddingV * 2)
            
            let xPos = (renderSize.width - segmentWidth) * style.position.horizontalOffsetPercentage
            segmentLayer.frame = CGRect(x: xPos, y: yPos - (segmentHeight / 2), width: segmentWidth, height: segmentHeight)
            
            // Background box styling
            if let bgHex = style.backgroundColor {
                segmentLayer.backgroundColor = UIColor(hexString: bgHex).cgColor
                segmentLayer.cornerRadius = 14.0 * scaleFactor
            } else if style.preset == .boxed {
                segmentLayer.backgroundColor = UIColor.black.withAlphaComponent(0.6).cgColor
                segmentLayer.cornerRadius = 14.0 * scaleFactor
            }
            
            // Layout individual words horizontally inside the segment
            var currentX: CGFloat = boxPaddingH
            let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
            
            for word in segment.words {
                let wordText = (style.preset == .karaokeHighlight || style.preset == .boldPop || style.preset == .outline || style.preset == .boxed)
                    ? word.text.uppercased()
                    : word.text
                
                let wordSize = (wordText as NSString).size(withAttributes: [.font: font])
                
                let wordLayer = CATextLayer()
                wordLayer.frame = CGRect(x: currentX, y: (segmentHeight - wordSize.height) / 2, width: wordSize.width + 2, height: wordSize.height + 4)
                wordLayer.string = wordText
                wordLayer.font = font
                wordLayer.fontSize = scaledFontSize
                wordLayer.alignmentMode = .center
                wordLayer.contentsScale = 2.0
                
                let normalColor = UIColor(hexString: style.textColor)
                let activeColor = UIColor(hexString: style.highlightColor)
                
                // Base text color
                wordLayer.foregroundColor = (word.isHighlighted ? activeColor : normalColor).cgColor
                
                // Animate word highlight if karaoke or active styling
                if style.preset == .karaokeHighlight || style.preset == .boldPop || style.preset == .glow {
                    let colorAnim = CAKeyframeAnimation(keyPath: "foregroundColor")
                    colorAnim.beginTime = AVCoreAnimationBeginTimeAtZero + word.start
                    colorAnim.duration = max(word.end - word.start, 0.1)
                    colorAnim.values = [
                        activeColor.cgColor,
                        activeColor.cgColor,
                        normalColor.cgColor
                    ]
                    colorAnim.keyTimes = [0.0, 0.9, 1.0]
                    colorAnim.isRemovedOnCompletion = false
                    colorAnim.fillMode = .forwards
                    wordLayer.add(colorAnim, forKey: "wordHighlight")
                }
                
                // Add pop-scale animation for active word
                if style.preset == .boldPop || style.preset == .bounce {
                    let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
                    scaleAnim.beginTime = AVCoreAnimationBeginTimeAtZero + word.start
                    scaleAnim.duration = max(word.end - word.start, 0.1)
                    scaleAnim.values = [1.0, 1.25, 1.0]
                    scaleAnim.keyTimes = [0.0, 0.4, 1.0]
                    scaleAnim.isRemovedOnCompletion = false
                    scaleAnim.fillMode = .forwards
                    wordLayer.add(scaleAnim, forKey: "wordPop")
                }
                
                segmentLayer.addSublayer(wordLayer)
                currentX += wordSize.width + spaceWidth
            }
            
            // Segment entrance & exit visibility animation
            let visibilityAnim = CAKeyframeAnimation(keyPath: "opacity")
            visibilityAnim.beginTime = AVCoreAnimationBeginTimeAtZero + segment.start
            let duration = max(segment.end - segment.start, 0.1)
            visibilityAnim.duration = duration
            visibilityAnim.values = [1.0, 1.0, 0.0]
            visibilityAnim.keyTimes = [0.0, 0.95, 1.0]
            visibilityAnim.isRemovedOnCompletion = false
            visibilityAnim.fillMode = .both
            segmentLayer.add(visibilityAnim, forKey: "segmentOpacity")
            
            // Slide-up animation on entrance
            if style.animation == .slideUp {
                let slideAnim = CABasicAnimation(keyPath: "position.y")
                slideAnim.beginTime = AVCoreAnimationBeginTimeAtZero + segment.start
                slideAnim.duration = 0.2
                slideAnim.fromValue = segmentLayer.position.y + (20 * scaleFactor)
                slideAnim.toValue = segmentLayer.position.y
                slideAnim.isRemovedOnCompletion = false
                slideAnim.fillMode = .forwards
                segmentLayer.add(slideAnim, forKey: "slideUp")
            }
            
            rootLayer.addSublayer(segmentLayer)
        }
        
        return rootLayer
    }
}

// MARK: - UIColor Hex Extension for CoreGraphics / QuartzCore
public extension UIColor {
    convenience init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}
