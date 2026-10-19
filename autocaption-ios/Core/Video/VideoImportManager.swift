import Foundation
import SwiftUI
import PhotosUI
import CoreTransferable
import AVFoundation
import Combine

/// Handles video importing, permissions, sandbox staging, metadata reading, and duration validation.
@MainActor
public final class VideoImportManager: ObservableObject {
    
    public enum VideoImportError: LocalizedError {
        case videoTooLong(duration: TimeInterval)
        case noVideoTrackFound
        case permissionDenied
        case fileTransferFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .videoTooLong(let duration):
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                return "The selected video is \(minutes)m \(seconds)s long. AutoCaption supports videos up to 5 minutes (300 seconds) for fast, 100% on-device processing."
            case .noVideoTrackFound:
                return "The selected media does not appear to contain a valid video track."
            case .permissionDenied:
                return "Photo library access was restricted or denied. Please enable Photo access in Settings to import videos."
            case .fileTransferFailed(let msg):
                return "Failed to import video: \(msg)"
            }
        }
    }
    
    public struct ImportedVideo: Sendable {
        public let localURL: URL
        public let metadata: VideoMetadata
        public let durationCMTime: CMTime
        
        public init(localURL: URL, metadata: VideoMetadata, durationCMTime: CMTime) {
            self.localURL = localURL
            self.metadata = metadata
            self.durationCMTime = durationCMTime
        }
    }
    
    public init() {}
    
    /// Checks photo library authorization, handling limited-library mode gracefully
    public func checkPhotoLibraryAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    /// Imports a video from PhotosPickerItem, verifies length <= 5 minutes, copies to temp dir, and extracts metadata.
    public func importVideo(from item: PhotosPickerItem) async throws -> ImportedVideo {
        // 1. Check permissions
        let hasAccess = await checkPhotoLibraryAuthorization()
        guard hasAccess else {
            throw VideoImportError.permissionDenied
        }
        
        // 2. Load transferable file representation
        guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
            throw VideoImportError.fileTransferFailed("Could not read video data from Photos.")
        }
        
        // 3. Process and validate the local video file
        return try await processLocalVideo(at: movie.tempURL)
    }
    
    /// Processes a local file URL (e.g. from file picker or document picker)
    public func processLocalVideo(at sourceURL: URL) async throws -> ImportedVideo {
        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + sourceURL.lastPathComponent)
        
        // Staging to temp dir if needed
        if sourceURL != tempDestination {
            try? FileManager.default.removeItem(at: tempDestination)
            try FileManager.default.copyItem(at: sourceURL, to: tempDestination)
        }
        
        let asset = AVURLAsset(url: tempDestination)
        
        // 4. Load duration asynchronously
        let durationTime = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(durationTime)
        
        // 5. Reject videos longer than 5 minutes (300 seconds)
        guard durationSeconds <= 300.0 else {
            try? FileManager.default.removeItem(at: tempDestination)
            throw VideoImportError.videoTooLong(duration: durationSeconds)
        }
        
        // 6. Read tracks, resolution, and orientation
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let firstTrack = videoTracks.first else {
            try? FileManager.default.removeItem(at: tempDestination)
            throw VideoImportError.noVideoTrackFound
        }
        
        let naturalSize = try await firstTrack.load(.naturalSize)
        let transform = try await firstTrack.load(.preferredTransform)
        
        // Detect portrait orientation from affine transform or aspect ratio
        let isPortrait = (transform.a == 0 && abs(transform.b) == 1) || (naturalSize.height > naturalSize.width)
        let realResolution: CGSize
        if isPortrait {
            realResolution = CGSize(width: min(naturalSize.width, naturalSize.height), height: max(naturalSize.width, naturalSize.height))
        } else {
            realResolution = CGSize(width: max(naturalSize.width, naturalSize.height), height: min(naturalSize.width, naturalSize.height))
        }
        
        let metadata = VideoMetadata(
            duration: durationSeconds,
            resolution: realResolution,
            isPortrait: isPortrait
        )
        
        return ImportedVideo(
            localURL: tempDestination,
            metadata: metadata,
            durationCMTime: durationTime
        )
    }
    
    /// Generates a quick thumbnail image from the video asset for preview
    public func generateThumbnail(for videoURL: URL) async -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: time)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}

/// Transferable representation for PhotosPicker video import
public struct VideoTransferable: Transferable {
    public let tempURL: URL
    
    public init(tempURL: URL) {
        self.tempURL = tempURL
    }
    
    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.tempURL)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mov")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(tempURL: destination)
        }
    }
}
