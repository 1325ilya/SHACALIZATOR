import UIKit
import Photos

enum SaveError: LocalizedError {
    case noPermission
    case saveFailed
    case saveVideoFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Нет разрешения на сохранение. Предоставьте доступ в настройках."
        case .saveFailed:
            return "Не удалось сохранить изображение. Попробуйте ещё раз."
        case .saveVideoFailed:
            return "Не удалось сохранить видео. Попробуйте ещё раз."
        case .unknown:
            return "Произошла неизвестная ошибка при сохранении."
        }
    }
}

enum SaveManager {

    /// Save `image` to the user's Photo Library.
    static func saveToPhotos(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

        switch status {
        case .authorized, .limited:
            break
        case .denied, .restricted:
            throw SaveError.noPermission
        case .notDetermined:
            throw SaveError.noPermission
        @unknown default:
            throw SaveError.noPermission
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let jpegData = image.jpegData(compressionQuality: 0.95) else {
                    return
                }
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: jpegData, options: nil)
            }
        } catch {
            throw SaveError.saveFailed
        }
    }

    /// Save `videoURL` to the user's Photo Library.
    static func saveVideoToPhotos(_ videoURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

        switch status {
        case .authorized, .limited:
            break
        case .denied, .restricted, .notDetermined:
            throw SaveError.noPermission
        @unknown default:
            throw SaveError.noPermission
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }
        } catch {
            throw SaveError.saveVideoFailed
        }
    }

    /// Return an activity-items array suitable for `UIActivityViewController`.
    static func shareImage(_ image: UIImage) -> [Any] {
        var items: [Any] = [image]
        if let jpegData = image.jpegData(compressionQuality: 0.9) {
            items = [jpegData]
        }
        return items
    }
}
