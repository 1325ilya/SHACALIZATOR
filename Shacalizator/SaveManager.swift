import UIKit
import Photos

enum SaveError: LocalizedError {
    case noPermission
    case saveFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Нет разрешения на сохранение в фотоплёнку. Предоставьте доступ в настройках."
        case .saveFailed:
            return "Не удалось сохранить изображение. Попробуйте ещё раз."
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
            // Should not happen after explicit request, but treat as denied.
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

    /// Return an activity-items array suitable for `UIActivityViewController`.
    static func shareImage(_ image: UIImage) -> [Any] {
        var items: [Any] = [image]
        if let jpegData = image.jpegData(compressionQuality: 0.9) {
            items = [jpegData]
        }
        return items
    }
}
