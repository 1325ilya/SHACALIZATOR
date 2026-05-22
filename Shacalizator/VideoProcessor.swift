import Foundation
import AVFoundation
import UIKit

enum VideoProcessor {
    
    enum VideoError: LocalizedError {
        case invalidTrack
        case readerFailed
        case writerFailed
        case unknown
        
        var errorDescription: String? {
            switch self {
            case .invalidTrack: return "Не удалось прочитать видео-трек"
            case .readerFailed: return "Ошибка чтения видео-кадров"
            case .writerFailed: return "Ошибка записи видео"
            case .unknown: return "Неизвестная ошибка при обработке видео"
            }
        }
    }
    
    static func process(videoURL: URL, preset: ShacalPreset, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoError.invalidTrack
        }
        
        let size = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Output dimensions: apply the preset's downscale factor
        let factor = preset.downscaleFactor
        let targetWidth = max(32, Int(round(size.width * factor) / 2) * 2) // Ensure even dimension
        let targetHeight = max(32, Int(round(size.height * factor) / 2) * 2)
        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        // Set up AVAssetReader
        let reader = try AVAssetReader(asset: asset)
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        reader.add(readerOutput)
        
        // Set up AVAssetWriter
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        // Video compression settings - extremely low bitrate for that real shacal look!
        let baseBitrate: Double
        switch preset {
        case .light: baseBitrate = 300_000
        case .medium: baseBitrate = 150_000
        case .hard: baseBitrate = 70_000
        case .legendary: baseBitrate = 30_000
        case .hellish: baseBitrate = 15_000
        case .megasupershacal: baseBitrate = 8_000
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: baseBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
            ] as [String : Any]
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: targetWidth,
                kCVPixelBufferHeightKey as String: targetHeight
            ]
        )
        
        writer.add(writerInput)
        
        // Also handle audio track to downsample/distort it natively!
        var audioReaderOutput: AVAssetReaderTrackOutput? = nil
        var audioWriterInput: AVAssetWriterInput? = nil
        
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let audioReaderSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioReaderSettings)
            reader.add(audioReaderOutput!)
            
            // Audio compression settings: mono, standard low quality (11.025kHz, 24kbps) for fully supported high-distortion quality!
            var acl = AudioChannelLayout()
            acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
            let aclData = Data(bytes: &acl, count: MemoryLayout<AudioChannelLayout>.size)
            
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 11025.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 24000,
                AVChannelLayoutKey: aclData
            ]
            
            audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            writer.add(audioWriterInput!)
        }
        
        // Start reading and writing
        guard reader.startReading() else { throw VideoError.readerFailed }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        // Thread-safe queues for reader/writer processing
        let videoQueue = DispatchQueue(label: "com.vonexl.shacalizator.video_processing")
        let audioQueue = DispatchQueue(label: "com.vonexl.shacalizator.audio_processing")
        
        let group = DispatchGroup()
        let frameContext = CIContext()
        
        // Process Video track
        group.enter()
        writerInput.requestMediaDataWhenReady(on: videoQueue) {
            while writerInput.isReadyForMoreMediaData {
                if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    
                    // Convert frame to UIImage, process it, and write it back!
                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                        if let cgImage = frameContext.createCGImage(ciImage, from: ciImage.extent) {
                            let uiImage = UIImage(cgImage: cgImage)
                            
                            // Process frame through the standard ImageProcessor pipeline!
                            if let processedUIImage = ImageProcessor.processSyncForVideo(image: uiImage, preset: preset) {
                                // Write the processed frame to the pixel buffer adaptor
                                if let processedPixelBuffer = createPixelBuffer(from: processedUIImage, size: targetSize) {
                                    adaptor.append(processedPixelBuffer, withPresentationTime: presentationTime)
                                }
                            } else {
                                // Fallback to writing original frame
                                adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                            }
                        }
                    }
                    
                    let progress = CMTimeGetSeconds(presentationTime) / durationSeconds
                    progressHandler(min(0.95, progress))
                } else {
                    writerInput.markAsFinished()
                    group.leave()
                    break
                }
            }
        }
        
        // Process Audio track (just copy sample buffers so it passes through the low-bitrate encoder)
        if let audioWriterInput = audioWriterInput, let audioReaderOutput = audioReaderOutput {
            group.enter()
            audioWriterInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioWriterInput.isReadyForMoreMediaData {
                    if let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() {
                        audioWriterInput.append(sampleBuffer)
                    } else {
                        audioWriterInput.markAsFinished()
                        group.leave()
                        break
                    }
                }
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            group.notify(queue: .main) {
                let readerError = reader.error
                let writerError = writer.error
                
                reader.cancelReading()
                writer.finishWriting {
                    if writer.status == .completed {
                        progressHandler(1.0)
                        continuation.resume(returning: outputURL)
                    } else {
                        progressHandler(1.0)
                        let error = writerError ?? readerError ?? VideoError.writerFailed
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    private static func createPixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer? = nil
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height)
        ] as [CFString : Any]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        
        guard let cg = context else {
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
            return nil
        }
        
        UIGraphicsPushContext(cg)
        image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        UIGraphicsPopContext()
        
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        return buffer
    }
}
