import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum ImageProcessor {

    private static let maxInputDimension: CGFloat = 4096

    static func process(image: UIImage, preset: ShacalPreset) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            processSync(image: image, preset: preset)
        }.value
    }

    static func processSyncForVideo(image: UIImage, preset: ShacalPreset) -> UIImage? {
        processSync(image: image, preset: preset)
    }

    // MARK: - Pipeline

    private static func processSync(image: UIImage, preset: ShacalPreset) -> UIImage? {
        let context = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: false,
            .cacheIntermediates: false
        ])

        var current: UIImage? = image

        // Cap oversized inputs before any processing
        current = autoreleasepool { () -> UIImage? in
            guard let img = current else { return nil }
            return downsampleIfNeeded(img)
        }

        // Step 1 – Downscale
        current = autoreleasepool { () -> UIImage? in
            guard let img = current else { return nil }
            return downscale(img, factor: preset.downscaleFactor)
        }

        // Custom Deep-fry and sticker overlays for megasupershacal
        if preset == .megasupershacal {
            current = autoreleasepool { () -> UIImage? in
                guard let img = current else { return nil }
                guard let fried = applyDeepFry(to: img, context: context) else { return img }
                return applyStickerOverlays(to: fried)
            }
        }

        // Step 2 – JPEG recompression passes
        for pass in 0..<preset.recompressionCount {
            current = autoreleasepool { () -> UIImage? in
                guard let img = current else { return nil }
                let range = preset.jpegQuality
                let fraction = preset.recompressionCount > 1
                    ? Float(pass) / Float(preset.recompressionCount - 1)
                    : 0.5
                let quality = CGFloat(range.lowerBound + (range.upperBound - range.lowerBound) * fraction)
                return recompress(img, quality: quality)
            }
        }

        // Step 3 – Noise
        if preset.noiseIntensity > 0 {
            current = autoreleasepool { () -> UIImage? in
                guard let img = current else { return nil }
                return addNoise(to: img, intensity: preset.noiseIntensity, context: context)
            }
        }

        // Step 4 – Pixelation
        if preset.pixelationScale > 0 {
            current = autoreleasepool { () -> UIImage? in
                guard let img = current else { return nil }
                return applyPixelation(to: img, scale: preset.pixelationScale, context: context)
            }
        }

        // Step 5 – Blur
        if preset.blurRadius > 0 {
            current = autoreleasepool { () -> UIImage? in
                guard let img = current else { return nil }
                return applyBlur(to: img, radius: preset.blurRadius, context: context)
            }
        }

        // Step 6 – Posterization
        if preset.posterizeLevels > 0 {
            current = autoreleasepool { () -> UIImage? in
                guard let img = current else { return nil }
                return applyPosterize(to: img, levels: preset.posterizeLevels, context: context)
            }
        }

        // Step 7 – Sharpen artifacts
        if preset.applySharpenArtifacts {
            current = autoreleasepool { () -> UIImage? in
                guard let img = current else { return nil }
                return applySharpen(to: img, context: context)
            }
        }

        // Step 8 – Final JPEG pass at the low end of the quality range
        current = autoreleasepool { () -> UIImage? in
            guard let img = current else { return nil }
            return recompress(img, quality: CGFloat(preset.jpegQuality.lowerBound))
        }

        return current
    }

    // MARK: - Step implementations

    /// Cap images larger than `maxInputDimension` on either side.
    private static func downsampleIfNeeded(_ image: UIImage) -> UIImage {
        let size = image.size
        let scale = image.scale
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let maxDim = max(pixelWidth, pixelHeight)
        guard maxDim > maxInputDimension else { return image }
        let ratio = maxInputDimension / maxDim
        return downscale(image, factor: ratio)
    }

    /// Resize using low-quality interpolation to encourage artifacts.
    private static func downscale(_ image: UIImage, factor: CGFloat) -> UIImage {
        let newSize = CGSize(
            width: round(image.size.width * factor),
            height: round(image.size.height * factor)
        )
        guard newSize.width >= 1, newSize.height >= 1 else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .low
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Compress to JPEG and reload to introduce real compression artifacts.
    private static func recompress(_ image: UIImage, quality: CGFloat) -> UIImage? {
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        return UIImage(data: data)
    }

    /// Overlay random luminance noise blended with the original image.
    private static func addNoise(to image: UIImage, intensity: Float, context: CIContext) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        // Generate random noise tile
        let noiseGenerator = CIFilter.randomGenerator()
        guard let noiseOutput = noiseGenerator.outputImage else { return nil }

        // Desaturate noise to get luminance-only grain
        let desaturate = CIFilter.colorControls()
        desaturate.inputImage = noiseOutput
        desaturate.saturation = 0
        desaturate.brightness = 0
        desaturate.contrast = 1
        guard let grayNoise = desaturate.outputImage?.cropped(to: extent) else { return nil }

        // Blend noise into the source image using sourceOver with reduced opacity
        let alphaAdjust = CIFilter.colorMatrix()
        alphaAdjust.inputImage = grayNoise
        alphaAdjust.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(intensity))
        guard let adjustedNoise = alphaAdjust.outputImage else { return nil }

        let composite = CIFilter.sourceOverCompositing()
        composite.inputImage = adjustedNoise
        composite.backgroundImage = ciImage
        guard let composited = composite.outputImage else { return nil }

        return renderToUIImage(composited, extent: extent, context: context)
    }

    /// Apply CIPixellate filter.
    private static func applyPixelation(to image: UIImage, scale: CGFloat, context: CIContext) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        let pixellate = CIFilter.pixellate()
        pixellate.inputImage = ciImage
        pixellate.scale = Float(scale)
        pixellate.center = CGPoint(x: extent.midX, y: extent.midY)
        guard let output = pixellate.outputImage?.cropped(to: extent) else { return nil }

        return renderToUIImage(output, extent: extent, context: context)
    }

    /// Apply Gaussian blur.
    private static func applyBlur(to image: UIImage, radius: CGFloat, context: CIContext) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = ciImage
        blur.radius = Float(radius)
        // Crop to original extent to remove edge expansion from blur
        guard let output = blur.outputImage?.cropped(to: extent) else { return nil }

        return renderToUIImage(output, extent: extent, context: context)
    }

    /// Reduce color palette via CIColorPosterize.
    private static func applyPosterize(to image: UIImage, levels: Int, context: CIContext) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        let posterize = CIFilter.colorPosterize()
        posterize.inputImage = ciImage
        posterize.levels = Float(levels)
        guard let output = posterize.outputImage else { return nil }

        return renderToUIImage(output, extent: extent, context: context)
    }

    /// Aggressive unsharp-mask to create halo/edge artifacts.
    private static func applySharpen(to image: UIImage, context: CIContext) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        let unsharp = CIFilter.unsharpMask()
        unsharp.inputImage = ciImage
        unsharp.radius = 3.0
        unsharp.intensity = 2.5
        guard let output = unsharp.outputImage?.cropped(to: extent) else { return nil }

        return renderToUIImage(output, extent: extent, context: context)
    }

    /// Apply extreme deep fry (massive saturation and contrast boost)
    private static func applyDeepFry(to image: UIImage, context: CIContext) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        let controls = CIFilter.colorControls()
        controls.inputImage = ciImage
        controls.saturation = 3.0
        controls.contrast = 2.8
        controls.brightness = 0.02
        guard let output = controls.outputImage?.cropped(to: extent) else { return nil }

        return renderToUIImage(output, extent: extent, context: context)
    }

    /// Render toxic stickers and scratch paths on top of the image to recreate megasupershacal look
    private static func applyStickerOverlays(to image: UIImage) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            // Draw original image first
            image.draw(in: CGRect(origin: .zero, size: size))

            let cg = ctx.cgContext

            // 1. Draw scratch stars/scribbles in the top-right corner
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(max(2, size.width * 0.005))
            
            // Draw white scratch star 1
            let trX = size.width * 0.8
            let trY = size.height * 0.15
            let r = size.width * 0.08
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4.0
                let start = CGPoint(x: trX, y: trY)
                let end = CGPoint(x: trX + cos(angle) * r, y: trY + sin(angle) * r)
                cg.move(to: start)
                cg.addLine(to: end)
            }
            cg.strokePath()

            // 2. Draw pink dead face sticker in top-left
            let pinkColor = UIColor(red: 1.0, green: 0.07, blue: 0.57, alpha: 0.8)
            cg.setStrokeColor(pinkColor.cgColor)
            cg.setLineWidth(max(3, size.width * 0.008))
            
            let tlX = size.width * 0.15
            let tlY = size.height * 0.15
            let tlR = size.width * 0.09
            
            // Draw circle
            cg.addArc(center: CGPoint(x: tlX, y: tlY), radius: tlR, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            cg.strokePath()
            
            // Draw cross eyes
            let eyeOffset = tlR * 0.35
            // Left eye cross
            cg.move(to: CGPoint(x: tlX - eyeOffset - eyeOffset/2, y: tlY - eyeOffset - eyeOffset/2))
            cg.addLine(to: CGPoint(x: tlX - eyeOffset + eyeOffset/2, y: tlY - eyeOffset + eyeOffset/2))
            cg.move(to: CGPoint(x: tlX - eyeOffset + eyeOffset/2, y: tlY - eyeOffset - eyeOffset/2))
            cg.addLine(to: CGPoint(x: tlX - eyeOffset - eyeOffset/2, y: tlY - eyeOffset + eyeOffset/2))
            
            // Right eye cross
            cg.move(to: CGPoint(x: tlX + eyeOffset - eyeOffset/2, y: tlY - eyeOffset - eyeOffset/2))
            cg.addLine(to: CGPoint(x: tlX + eyeOffset + eyeOffset/2, y: tlY - eyeOffset + eyeOffset/2))
            cg.move(to: CGPoint(x: tlX + eyeOffset + eyeOffset/2, y: tlY - eyeOffset - eyeOffset/2))
            cg.addLine(to: CGPoint(x: tlX + eyeOffset - eyeOffset/2, y: tlY - eyeOffset + eyeOffset/2))
            
            // Mouth
            cg.move(to: CGPoint(x: tlX - eyeOffset, y: tlY + eyeOffset))
            cg.addLine(to: CGPoint(x: tlX + eyeOffset, y: tlY + eyeOffset))
            cg.strokePath()

            // 3. Draw a toxic skull emoji in bottom-right
            let skullFontSize = size.width * 0.15
            let font = UIFont.systemFont(ofSize: skullFontSize)
            let skullString = "💀" as NSString
            let skullRect = CGRect(
                x: size.width * 0.78,
                y: size.height * 0.78,
                width: skullFontSize * 1.2,
                height: skullFontSize * 1.2
            )
            skullString.draw(in: skullRect, withAttributes: [.font: font])

            // Draw a green radioactive symbol in bottom-right corner as well
            let bioString = "☣️" as NSString
            let bioRect = CGRect(
                x: size.width * 0.65,
                y: size.height * 0.82,
                width: skullFontSize * 0.8,
                height: skullFontSize * 0.8
            )
            bioString.draw(in: bioRect, withAttributes: [.font: UIFont.systemFont(ofSize: skullFontSize * 0.8)])

            // 4. Draw pixelated glitch blocks in bottom-left
            let blockColor = UIColor(red: 0.0, green: 1.0, blue: 0.9, alpha: 0.7)
            cg.setFillColor(blockColor.cgColor)
            let gbSize = size.width * 0.08
            cg.fill(CGRect(x: size.width * 0.05, y: size.height * 0.8, width: gbSize * 2, height: gbSize * 0.4))
            
            cg.setFillColor(UIColor.red.withAlphaComponent(0.6).cgColor)
            cg.fill(CGRect(x: size.width * 0.1, y: size.height * 0.83, width: gbSize * 1.5, height: gbSize * 0.3))
        }
    }

    // MARK: - Helpers

    /// Render a CIImage into a UIImage via the shared CIContext.
    private static func renderToUIImage(_ ciImage: CIImage, extent: CGRect, context: CIContext) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
