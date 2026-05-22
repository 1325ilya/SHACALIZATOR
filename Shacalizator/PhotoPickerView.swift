import SwiftUI
import PhotosUI

struct PhotoPickerView: View {
    @Binding var selectedImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Label("Выбрать фото", systemImage: "photo.on.rectangle.angled")
                .font(.headline)
                .fontWeight(.semibold)
        }
        .onChange(of: selectedItem) { _, newValue in
            guard let item = newValue else { return }
            loadImage(from: item)
        }
    }

    private func loadImage(from item: PhotosPickerItem) {
        Task { @MainActor in
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let fullImage = UIImage(data: data) else {
                selectedImage = nil
                return
            }
            selectedImage = downsample(fullImage, maxDimension: 4096)
        }
    }

    private func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

#Preview {
    @Previewable @State var image: UIImage? = nil
    PhotoPickerView(selectedImage: $image)
}
