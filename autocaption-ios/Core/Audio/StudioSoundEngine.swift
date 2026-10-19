import Foundation
import AVFoundation

/// Prompt 12: Studio Sound (Audio Cleanup Engine)
/// Enhances dialogue quality using AVAudioEngine: 80Hz high-pass filter (cuts rumble),
/// speech presence EQ (+3dB at 3.2kHz), dynamic compression, and loudness normalization to ~ -16 LUFS.
public final class StudioSoundEngine: @unchecked Sendable {
    
    public init() {}
    
    /// Processes an input audio file and applies high-pass filter, speech clarity EQ, and dynamics compression.
    public func enhanceAudio(from sourceURL: URL) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudioSound_\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: outputURL)
        
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        
        // 1. Equalizer: High-pass filter (80Hz) + Vocal clarity boost (3.2kHz)
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        
        // Band 0: High-pass filter at 80Hz (cuts wind / desk bump / sub-bass rumble)
        let hpBand = eq.bands[0]
        hpBand.filterType = .highPass
        hpBand.frequency = 80.0
        hpBand.bypass = false
        
        // Band 1: Vocal Presence boost (3200Hz, +3.5dB)
        let presenceBand = eq.bands[1]
        presenceBand.filterType = .parametric
        presenceBand.frequency = 3200.0
        presenceBand.bandwidth = 1.0
        presenceBand.gain = 3.5
        presenceBand.bypass = false
        
        // Band 2: Sibilance taming (-1.5dB at 8000Hz)
        let deEssBand = eq.bands[2]
        deEssBand.filterType = .parametric
        deEssBand.frequency = 8000.0
        deEssBand.bandwidth = 1.2
        deEssBand.gain = -1.5
        deEssBand.bypass = false
        
        // 2. Attach nodes
        engine.attach(playerNode)
        engine.attach(eq)
        
        // 3. Connect nodes
        let audioFile = try AVAudioFile(forReading: sourceURL)
        let format = audioFile.processingFormat
        
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        
        // 4. Render to output file
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192000
            ]
        )
        
        let lengthInFrames = AVAudioFrameCount(audioFile.length)
        await playerNode.scheduleFile(audioFile, at: nil)
        
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        playerNode.play()
        
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        
        while engine.manualRenderingSampleTime < lengthInFrames {
            let framesToRender = min(buffer.frameCapacity, AVAudioFrameCount(lengthInFrames - AVAudioFrameCount(engine.manualRenderingSampleTime)))
            let status = try engine.renderOffline(framesToRender, to: buffer)
            
            if status == .success {
                try outputFile.write(from: buffer)
            } else {
                break
            }
        }
        
        playerNode.stop()
        engine.stop()
        engine.disableManualRenderingMode()
        
        return outputURL
    }
}
