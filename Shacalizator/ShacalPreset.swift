import Foundation
import CoreGraphics

enum ShacalPreset: String, CaseIterable, Identifiable {
    case light
    case medium
    case hard
    case legendary
    case hellish

    var id: String { rawValue }

    var name: String {
        switch self {
        case .light:     return "Лёгкий шакал"
        case .medium:    return "Средний шакал"
        case .hard:      return "Жёсткий шакал"
        case .legendary: return "Легендарный шакал"
        case .hellish:   return "Адский шакал"
        }
    }

    var subtitle: String {
        switch self {
        case .light:     return "Слегка пожатое фото, почти не заметно"
        case .medium:    return "Ощутимая потеря качества, как из мессенджера"
        case .hard:      return "Жёсткие артефакты, пиксели и шумы"
        case .legendary: return "Легендарный уровень сжатия, еле разобрать"
        case .hellish:   return "Полное уничтожение качества, каша из пикселей"
        }
    }

    var icon: String {
        switch self {
        case .light:     return "sun.min"
        case .medium:    return "cloud"
        case .hard:      return "bolt.fill"
        case .legendary: return "flame.fill"
        case .hellish:   return "hurricane"
        }
    }

    var jpegQuality: ClosedRange<Float> {
        switch self {
        case .light:     return 0.55...0.65
        case .medium:    return 0.35...0.45
        case .hard:      return 0.18...0.25
        case .legendary: return 0.05...0.12
        case .hellish:   return 0.01...0.05
        }
    }

    var downscaleFactor: CGFloat {
        switch self {
        case .light:     return 0.85
        case .medium:    return 0.7
        case .hard:      return 0.5
        case .legendary: return 0.35
        case .hellish:   return 0.25
        }
    }

    var recompressionCount: Int {
        switch self {
        case .light:     return 1
        case .medium:    return 2
        case .hard:      return 3
        case .legendary: return 5
        case .hellish:   return 9
        }
    }

    var noiseIntensity: Float {
        switch self {
        case .light:     return 0.1
        case .medium:    return 0.2
        case .hard:      return 0.35
        case .legendary: return 0.5
        case .hellish:   return 0.7
        }
    }

    var blurRadius: CGFloat {
        switch self {
        case .light:     return 0
        case .medium:    return 1.5
        case .hard:      return 0
        case .legendary: return 2
        case .hellish:   return 3
        }
    }

    var pixelationScale: CGFloat {
        switch self {
        case .light:     return 0
        case .medium:    return 0
        case .hard:      return 4
        case .legendary: return 6
        case .hellish:   return 10
        }
    }

    var posterizeLevels: Int {
        switch self {
        case .light:     return 0
        case .medium:    return 0
        case .hard:      return 0
        case .legendary: return 8
        case .hellish:   return 4
        }
    }

    var applySharpenArtifacts: Bool {
        switch self {
        case .light:     return false
        case .medium:    return false
        case .hard:      return true
        case .legendary: return true
        case .hellish:   return true
        }
    }

    static var allPresets: [ShacalPreset] {
        Array(allCases)
    }
}
