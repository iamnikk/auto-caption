import Foundation
import AVFoundation

/// Prompt 9: Background Music & Audio Mixing Engine
/// Supports importing audio from Files, volume balancing, loop-to-fit, and auto-ducking under spoken captions.
public struct BackgroundMusicService: Sendable {
    
    public struct AudioMixConfig: Codable, Equatable, Sendable {
        public var musicURL: URL?
        public var originalAudioVolume: Float = 1.0 // 0.0 - 1.0
        public var musicVolume: Float = 0.35        // 0.0 - 1.0
        public var autoDucking: Bool = true        // Ducks music volume during speech segments
        public var loopToFit: Bool = true
        
        public init(
            musicURL: URL? = nil,
            originalAudioVolume: Float = 1.0,
            musicVolume: Float = 0.35,
            autoDucking: Bool = true,
            loopToFit: Bool = true
        ) {
            self.musicURL = musicURL
            self.originalAudioVolume = originalAudioVolume
            self.musicVolume = musicVolume
            self.autoDucking = autoDucking
            self.loopToFit = loopToFit
        }
    }
    
    public init() {}
    
    /// Builds AVMutableAudioMix with auto-ducking volume ramps applied to the background music track.
    public func buildAudioMix(
        for composition: AVMutableComposition,
        musicTrack: AVMutableCompositionTrack?,
        speechSegments: [CaptionSegment],
        config: AudioMixConfig,
        totalDuration: CMTime
    ) -> AVAudioMix {
        let audioMix = AVMutableAudioMix()
        var inputParameters: [AVMutableAudioMixInputParameters] = []
        
        // 1. Configure original video audio tracks volume
        let videoAudioTracks = composition.tracks(withMediaType: .audio).filter { $0 != musicTrack }
        for track in videoAudioTracks {
            let params = AVMutableAudioMixInputParameters(track: track)
            params.setVolume(config.originalAudioVolume, at: .zero)
            inputParameters.append(params)
        }
        
        // 2. Configure background music track with auto-ducking
        if let musicTrack = musicTrack {
            let musicParams = AVMutableAudioMixInputParameters(track: musicTrack)
            let baseVolume = config.musicVolume
            let duckedVolume = baseVolume * 0.25 // Reduce to 25% when speaking
            
            if config.autoDucking && !speechSegments.isEmpty {
                musicParams.setVolume(baseVolume, at: .zero)
                
                for segment in speechSegments {
                    let speechStart = CMTime(seconds: max(0.0, segment.start - 0.15), preferredTimescale: 600)
                    let speechEnd = CMTime(seconds: segment.end + 0.15, preferredTimescale: 600)
                    let rampDuration = CMTime(seconds: 0.15, preferredTimescale: 600)
                    
                    // Duck down
                    let duckRange = CMTimeRange(start: speechStart, duration: rampDuration)
                    musicParams.setVolumeRamp(fromStartVolume: baseVolume, toEndVolume: duckedVolume, timeRange: duckRange)
                    
                    // Restore back up
                    let restoreRange = CMTimeRange(start: speechEnd, duration: rampDuration)
                    musicParams.setVolumeRamp(fromStartVolume: duckedVolume, toEndVolume: baseVolume, timeRange: restoreRange)
                }
            } else {
                musicParams.setVolume(baseVolume, at: .zero)
            }
            
            inputParameters.append(musicParams)
        }
        
        audioMix.inputParameters = inputParameters
        return audioMix
    }
}
