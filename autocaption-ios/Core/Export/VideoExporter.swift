import Foundation
import AVFoundation
import Photos
import UIKit
import Combine

/// Prompt 6 & Prompt 7: Video Exporter
/// 1. Builds AVMutableComposition and AVVideoComposition.
/// 2. Integrates CaptionRenderer CALayer tree via AVVideoCompositionCoreAnimationTool.
/// 3. Applies Auto-Crop / Aspect-Ratio presets (9:16, 1:1, 4:5, 16:9) centered with transform scaling.
/// 4. Exports via AVAssetExportSession at source resolution preserving orientation.
/// 5. Saves to Photos with add-only permission and handles low-storage / cancellation errors.
@MainActor
public final class VideoExporter: ObservableObject {
    
    @Published public var isExporting: Bool = false
    @Published public var exportProgress: Double = 0.0
    @Published public var statusMessage: String = "Ready"
    @Published public var exportedVideoURL: URL?
    
    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?
    
    public enum ExportError: LocalizedError {
        case noVideoTrack
        case compositionFailed
        case exportFailed(String)
        case exportCancelled
        case lowDiskSpace
        case photoLibraryPermissionDenied
        
        public var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                return "The source media does not contain a video track."
            case .compositionFailed:
                return "Failed to build video composition."
            case .exportFailed(let msg):
                return "Export failed: \(msg)"
            case .exportCancelled:
                return "Video export was cancelled."
            case .lowDiskSpace:
                return "Not enough device storage to export this video. Please free up space and try again."
            case .photoLibraryPermissionDenied:
                return "Permission to save to Photos was denied."
            }
        }
    }
    
    public init() {}
    
    public func cancelExport() {
        exportSession?.cancelExport()
        stopProgressTimer()
        self.isExporting = false
        self.statusMessage = "Export cancelled"
    }
    
    /// Exports the project with burned-in animated captions, cropping, and audio mixing.
    public func export(project: Project) async throws -> URL {
        // 1. Storage space check (need at least 250MB free space)
        if !hasSufficientDiskSpace() {
            throw ExportError.lowDiskSpace
        }
        
        self.isExporting = true
        self.exportProgress = 0.05
        self.statusMessage = "Preparing composition..."
        
        let asset = AVURLAsset(url: project.sourceVideoURL)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        
        guard let sourceVideoTrack = videoTracks.first else {
            self.isExporting = false
            throw ExportError.noVideoTrack
        }
        
        // 2. Build AVMutableComposition
        let composition = AVMutableComposition()
        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack?.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
        
        // Add source audio track if present
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudioTrack = audioTracks.first {
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            try compositionAudioTrack?.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
        }
        
        // 3. Compute Auto-Crop & Render Size (Prompt 7)
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        
        // True physical dimensions considering video transform orientation
        let isPortrait = (preferredTransform.a == 0 && abs(preferredTransform.b) == 1)
        let sourceRealWidth = isPortrait ? naturalSize.height : naturalSize.width
        let sourceRealHeight = isPortrait ? naturalSize.width : naturalSize.height
        
        // Render size based on chosen AspectRatio preset
        let targetRatio = project.aspectRatio.ratio
        let renderSize: CGSize
        if isPortrait {
            let targetHeight = max(sourceRealHeight, 1920)
            renderSize = CGSize(width: targetHeight * targetRatio, height: targetHeight)
        } else {
            let targetHeight = max(sourceRealHeight, 1080)
            renderSize = CGSize(width: targetHeight * targetRatio, height: targetHeight)
        }
        
        // 4. Build AVVideoComposition & Layer Instructions
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack!)
        
        // Crop-to-fill centered transform
        let scaleX = renderSize.width / sourceRealWidth
        let scaleY = renderSize.height / sourceRealHeight
        let fillScale = max(scaleX, scaleY)
        
        let scaledWidth = sourceRealWidth * fillScale
        let scaledHeight = sourceRealHeight * fillScale
        let offsetX = (renderSize.width - scaledWidth) / 2.0
        let offsetY = (renderSize.height - scaledHeight) / 2.0
        
        var finalTransform = preferredTransform
            .concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
        
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // 5. Overlay CaptionRenderer CALayer Tree (Prompt 5 & Prompt 6)
        let renderer = CaptionRenderer()
        let captionLayer = renderer.buildCaptionLayerTree(
            for: project.segments,
            style: project.style,
            renderSize: renderSize,
            videoDuration: CMTimeGetSeconds(duration)
        )
        
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(captionLayer)
        
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        
        // 6. Setup Export Session
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoCaption_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            self.isExporting = false
            throw ExportError.compositionFailed
        }
        
        session.videoComposition = videoComposition
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        self.exportSession = session
        
        self.statusMessage = "Burning in captions..."
        startProgressTimer()
        
        return try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously { [weak self] in
                guard let self = self else { return }
                
                Task { @MainActor in
                    self.stopProgressTimer()
                    self.isExporting = false
                    
                    switch session.status {
                    case .completed:
                        self.exportProgress = 1.0
                        self.statusMessage = "Export Complete!"
                        self.exportedVideoURL = outputURL
                        
                        // Save to Photos (Prompt 6: add-only permission)
                        Task {
                            await self.saveToPhotoLibrary(fileURL: outputURL)
                        }
                        
                        continuation.resume(returning: outputURL)
                        
                    case .cancelled:
                        continuation.resume(throwing: ExportError.exportCancelled)
                        
                    case .failed:
                        let msg = session.error?.localizedDescription ?? "Unknown export error"
                        continuation.resume(throwing: ExportError.exportFailed(msg))
                        
                    default:
                        continuation.resume(throwing: ExportError.exportFailed("Session ended with status: \(session.status.rawValue)"))
                    }
                }
            }
        }
    }
    
    /// Prompt 6: Saves exported video into user's Photos library using add-only permission.
    public func saveToPhotoLibrary(fileURL: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            print("⚠️ Photos add-only permission not granted")
            return
        }
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
            print("✅ Successfully saved captioned video to Photos library.")
        } catch {
            print("⚠️ Failed to save video to Photos: \(error.localizedDescription)")
        }
    }
    
    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, let session = self.exportSession else { return }
            Task { @MainActor in
                self.exportProgress = Double(session.progress)
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func hasSufficientDiskSpace() -> Bool {
        do {
            let values = try FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return capacity > 250_000_000 // 250 MB
            }
        } catch {
            return true
        }
        return true
    }
}
