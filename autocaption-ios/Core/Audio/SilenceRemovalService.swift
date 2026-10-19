import Foundation
import AVFoundation
import CoreMedia

/// Prompt 8: Silence Removal Service
/// Analyzes audio with AVAssetReader, computes RMS in 20ms windows,
/// detects silences below threshold lasting > 0.4s, and remaps caption timestamps.
public struct SilenceRemovalService: Sendable {
    
    public init() {}
    
    public struct SilenceRegion: Identifiable, Equatable, Sendable {
        public let id: UUID = UUID()
        public let start: TimeInterval
        public let end: TimeInterval
        public var duration: TimeInterval { end - start }
    }
    
    /// Detects silent intervals in an audio file using 20ms RMS windows.
    public func detectSilences(
        in audioURL: URL,
        silenceThresholdRMS: Float = 0.015,
        minSilenceDuration: TimeInterval = 0.4,
        padding: TimeInterval = 0.1
    ) async throws -> [SilenceRegion] {
        let asset = AVURLAsset(url: audioURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()
        
        var silenceRegions: [SilenceRegion] = []
        let windowDuration = 0.02 // 20ms
        let samplesPerWindow = Int(16000 * windowDuration)
        
        var currentSampleTime: TimeInterval = 0.0
        var silenceStart: TimeInterval? = nil
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>? = nil
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            
            guard let int16Pointer = dataPointer?.withMemoryRebound(to: Int16.self, capacity: length / 2, { $0 }) else { continue }
            let count = length / 2
            
            var index = 0
            while index + samplesPerWindow <= count {
                var sum: Float = 0.0
                for i in 0..<samplesPerWindow {
                    let sampleVal = Float(int16Pointer[index + i]) / 32768.0
                    sum += sampleVal * sampleVal
                }
                let rms = sqrt(sum / Float(samplesPerWindow))
                
                if rms < silenceThresholdRMS {
                    if silenceStart == nil {
                        silenceStart = currentSampleTime
                    }
                } else {
                    if let start = silenceStart {
                        let duration = currentSampleTime - start
                        if duration >= minSilenceDuration {
                            let paddedStart = start + padding
                            let paddedEnd = currentSampleTime - padding
                            if paddedEnd > paddedStart {
                                silenceRegions.append(SilenceRegion(start: paddedStart, end: paddedEnd))
                            }
                        }
                        silenceStart = nil
                    }
                }
                
                index += samplesPerWindow
                currentSampleTime += windowDuration
            }
        }
        
        return silenceRegions
    }
    
    /// Computes kept ranges from detected silences.
    public func computeKeptRanges(totalDuration: TimeInterval, silences: [SilenceRegion]) -> [CMTimeRange] {
        var kept: [CMTimeRange] = []
        var currentTime: TimeInterval = 0.0
        
        for silence in silences {
            if silence.start > currentTime {
                let rangeDuration = silence.start - currentTime
                kept.append(CMTimeRange(
                    start: CMTime(seconds: currentTime, preferredTimescale: 600),
                    duration: CMTime(seconds: rangeDuration, preferredTimescale: 600)
                ))
            }
            currentTime = max(currentTime, silence.end)
        }
        
        if currentTime < totalDuration {
            kept.append(CMTimeRange(
                start: CMTime(seconds: currentTime, preferredTimescale: 600),
                duration: CMTime(seconds: totalDuration - currentTime, preferredTimescale: 600)
            ))
        }
        
        return kept
    }
    
    /// Prompt 8 Unit-Testable Invariant: Remaps caption timestamps when silent sections are excised.
    public static func remapTimestamps(
        segments: [CaptionSegment],
        removedSilences: [SilenceRegion]
    ) -> [CaptionSegment] {
        return segments.compactMap { segment in
            var shiftStart: TimeInterval = 0.0
            var shiftEnd: TimeInterval = 0.0
            
            for silence in removedSilences {
                if silence.end <= segment.start {
                    shiftStart += silence.duration
                } else if silence.start < segment.start && silence.end > segment.start {
                    shiftStart += (segment.start - silence.start)
                }
                
                if silence.end <= segment.end {
                    shiftEnd += silence.duration
                } else if silence.start < segment.end && silence.end > segment.end {
                    shiftEnd += (segment.end - silence.start)
                }
            }
            
            let newStart = max(0.0, segment.start - shiftStart)
            let newEnd = max(newStart + 0.1, segment.end - shiftEnd)
            
            let remappedWords = segment.words.map { word -> CaptionWord in
                var wShift: TimeInterval = 0.0
                for silence in removedSilences where silence.end <= word.start {
                    wShift += silence.duration
                }
                return CaptionWord(
                    id: word.id,
                    text: word.text,
                    start: max(0.0, word.start - wShift),
                    end: max(0.1, word.end - wShift),
                    isHighlighted: word.isHighlighted,
                    confidence: word.confidence
                )
            }
            
            return CaptionSegment(
                id: segment.id,
                words: remappedWords,
                start: newStart,
                end: newEnd
            )
        }
    }
}
