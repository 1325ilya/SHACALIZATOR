import SwiftUI
import PhotosUI
import Observation

@Observable
final class ContentViewModel {
    var selectedImage: UIImage?
    var processedImage: UIImage?
    var selectedPreset: ShacalPreset?
    var isProcessing: Bool = false
    var showingOriginal: Bool = false
    var toastMessage: String?
    var showToast: Bool = false

    var selectedPhotoItem: PhotosPickerItem? {
        didSet {
            guard let item = selectedPhotoItem else { return }
            loadImage(from: item)
        }
    }

    private func loadImage(from item: PhotosPickerItem) {
        Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }

            guard let data = try? await item.loadTransferable(type: Data.self),
                  let fullImage = UIImage(data: data) else {
                return
            }

            let downsampled = downsample(fullImage, maxDimension: 4096)
            selectedImage = downsampled
            processedImage = nil
            selectedPreset = nil
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

    func selectPreset(_ preset: ShacalPreset) {
        guard let sourceImage = selectedImage else { return }

        if selectedPreset == preset {
            selectedPreset = nil
            processedImage = nil
            return
        }

        selectedPreset = preset
        isProcessing = true

        Task { @MainActor in
            let result = await ImageProcessor.process(image: sourceImage, preset: preset)
            processedImage = result
            isProcessing = false
            showingOriginal = false
        }
    }

    func saveImage() {
        guard let image = processedImage else { return }

        Task { @MainActor in
            do {
                try await SaveManager.saveToPhotos(image)
                toastMessage = "Сохранено в Фото"
                showToast = true
            } catch {
                toastMessage = "Ошибка сохранения"
                showToast = true
            }
        }
    }

    func shareImage() -> UIImage? {
        processedImage
    }
}

struct ContentView: View {
    @State private var viewModel = ContentViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                mainContent

                if viewModel.showToast, let message = viewModel.toastMessage {
                    VStack {
                        ToastView(message: message)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.showToast = false
                            }
                        }
                    }
                }

                if viewModel.isProcessing {
                    processingOverlay
                }
            }
            .navigationTitle("Shacalizator")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: Binding(
                            get: { viewModel.selectedPhotoItem },
                            set: { viewModel.selectedPhotoItem = $0 }
                        ),
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.accent)
                    }
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.2), value: viewModel.showToast)
            .animation(.easeInOut(duration: 0.35), value: viewModel.selectedImage != nil)
            .animation(.easeInOut(duration: 0.3), value: viewModel.selectedPreset)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let selectedImage = viewModel.selectedImage {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    ImageComparisonView(
                        originalImage: selectedImage,
                        processedImage: viewModel.processedImage,
                        showingOriginal: Binding(
                            get: { viewModel.showingOriginal },
                            set: { viewModel.showingOriginal = $0 }
                        )
                    )
                    .padding(.horizontal, 16)

                    presetSection

                    if viewModel.processedImage != nil {
                        actionButtons
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 16)
            }
        } else {
            EmptyStateView {
                // PhotosPicker is in toolbar; this provides a secondary tap target
            }
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Пресеты шакализации")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ShacalPreset.allPresets) { preset in
                        PresetCardView(
                            preset: preset,
                            isSelected: viewModel.selectedPreset == preset
                        ) {
                            viewModel.selectPreset(preset)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.saveImage()
            } label: {
                Label("Сохранить", systemImage: "square.and.arrow.down")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            if let shareImage = viewModel.processedImage,
               let imageData = shareImage.jpegData(compressionQuality: 0.8) {
                ShareLink(
                    item: Image(uiImage: shareImage),
                    preview: SharePreview("Шакализированное фото", image: Image(uiImage: shareImage))
                ) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text("Шакализация...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .transition(.opacity)
    }

    private var backgroundGradient: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.04, blue: 0.20),
                        Color(red: 0.04, green: 0.06, blue: 0.18),
                        Color(red: 0.02, green: 0.02, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.92, green: 0.90, blue: 0.98),
                        Color(red: 0.96, green: 0.95, blue: 1.0),
                        Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

#Preview {
    ContentView()
}
