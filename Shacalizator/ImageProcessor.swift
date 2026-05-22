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

    // MARK: - Helpers

    /// Render a CIImage into a UIImage via the shared CIContext.
    private static func renderToUIImage(_ ciImage: CIImage, extent: CGRect, context: CIContext) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
