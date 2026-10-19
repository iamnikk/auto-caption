import Foundation
import AVFoundation

/// Handles extracting audio from video files and converting to 16kHz 16-bit Mono PCM WAV (Whisper format).
public final class AudioExtractor {
    
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
                return "Failed to convert audio stream to Whisper compatible format."
            }
        }
    }
    
    /// Thread-safe context holder to safely coordinate AVFoundation reader/writer across GCD & Swift Concurrency boundaries.
    private final class ExtractionSession: @unchecked Sendable {
        let reader: AVAssetReader
        let trackOutput: AVAssetReaderTrackOutput
        let writer: AVAssetWriter
        let writerInput: AVAssetWriterInput
        let outputURL: URL
        
        init(reader: AVAssetReader, trackOutput: AVAssetReaderTrackOutput, writer: AVAssetWriter, writerInput: AVAssetWriterInput, outputURL: URL) {
            self.reader = reader
            self.trackOutput = trackOutput
            self.writer = writer
            self.writerInput = writerInput
            self.outputURL = outputURL
        }
    }
    
    public init() {}
    
    /// Extracts audio track from video URL to a 16kHz mono WAV file for Whisper.
    public func extractAudioForWhisper(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExtractionError.noAudioTrack
        }
        
        let outputDirectory = FileManager.default.temporaryDirectory
        let outputURL = outputDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        let reader = try AVAssetReader(asset: asset)
        
        // 16kHz Mono 16-bit Linear PCM Settings (Whisper's exact required format)
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
        
        let session = ExtractionSession(
            reader: reader,
            trackOutput: trackOutput,
            writer: writer,
            writerInput: writerInput,
            outputURL: outputURL
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.autocaption.audio.extraction")
            
            session.writerInput.requestMediaDataWhenReady(on: queue) {
                while session.writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = session.trackOutput.copyNextSampleBuffer() {
                        session.writerInput.append(sampleBuffer)
                    } else {
                        session.writerInput.markAsFinished()
                        session.writer.finishWriting {
                            if session.reader.status == .completed && session.writer.status == .completed {
                                continuation.resume(returning: session.outputURL)
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
