import Foundation
import AVFoundation

/// Handles extracting audio from video files:
/// 1. AVAssetExportSession to .m4a (Prompt 2 standard format for Apple Speech)
/// 2. 16kHz 16-bit Mono PCM WAV (Whisper format)
public final class AudioExtractor: Sendable {
    
    public enum ExtractionError: LocalizedError {
        case noAudioTrack
        case readerFailed(String)
        case outputExportFailed
        
        public var errorDescription: String? {
            switch self {
            case .noAudioTrack:
                return "The selected video does not contain an audio track."
            case .readerFailed(let msg):
                return "Failed to read audio stream: \(msg)"
            case .outputExportFailed:
                return "Failed to export audio stream."
            }
        }
    }
    
    public init() {}
    
    /// Prompt 2: Extracts audio from the video asset using AVAssetExportSession to an .m4a container.
    public func extractAudioM4A(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw ExtractionError.noAudioTrack
        }
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExtractionError.outputExportFailed
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed:
                    let err = exportSession.error ?? ExtractionError.outputExportFailed
                    continuation.resume(throwing: err)
                case .cancelled:
                    continuation.resume(throwing: ExtractionError.outputExportFailed)
                default:
                    continuation.resume(throwing: ExtractionError.outputExportFailed)
                }
            }
        }
    }
    
    /// Extracts audio track from video URL to a 16kHz mono WAV file for Whisper.
    public func extractAudioForWhisper(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExtractionError.noAudioTrack
        }
        
        let outputDirectory = FileManager.default.temporaryDirectory
        let outputURL = outputDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try? FileManager.default.removeItem(at: outputURL)
        
        let reader = try AVAssetReader(asset: asset)
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(trackOutput)
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)
        
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.autocaption.audio.extraction")
            
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if reader.status == .completed && writer.status == .completed {
                                continuation.resume(returning: outputURL)
                            } else {
                                continuation.resume(throwing: ExtractionError.outputExportFailed)
                            }
                        }
                        break
                    }
                }
            }
        }
    }
}
