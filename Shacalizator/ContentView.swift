import SwiftUI
import PhotosUI
import Observation
import AVKit
import UniformTypeIdentifiers

struct VideoTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { exporting in
            SentTransferredFile(exporting.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mp4" : received.file.pathExtension)
            
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            
            try FileManager.default.copyItem(at: received.file, to: copy)
            return VideoTransferable(url: copy)
        }
    }
}

@Observable
final class ContentViewModel {
    var selectedImage: UIImage?
    var processedImage: UIImage?
    var selectedVideoURL: URL?
    var processedVideoURL: URL?
    var isVideo: Bool = false
    var isProcessing: Bool = false
    var processingProgress: Double = 0.0
    var showingOriginal: Bool = false
    var toastMessage: String?
    var showToast: Bool = false

    var selectedPhotoItem: PhotosPickerItem? {
        didSet {
            guard let item = selectedPhotoItem else { return }
            loadMedia(from: item)
        }
    }

    private func loadMedia(from item: PhotosPickerItem) {
        Task { @MainActor in
            isProcessing = true
            processingProgress = 0.0

            // Reset old state
            selectedImage = nil
            processedImage = nil
            selectedVideoURL = nil
            processedVideoURL = nil
            selectedPreset = nil
            isVideo = false

            // Check if it conforms to video/movie
            let isMovie = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) })
            if isMovie {
                do {
                    if let videoTrans = try await item.loadTransferable(type: VideoTransferable.self) {
                        self.selectedVideoURL = videoTrans.url
                        self.isVideo = true
                    } else {
                        self.toastMessage = "Не удалось загрузить видео"
                        self.showToast = true
                    }
                } catch {
                    self.toastMessage = "Не удалось загрузить видео: \(error.localizedDescription)"
                    self.showToast = true
                }
                self.isProcessing = false
            } else {
                // Load as image
                defer { isProcessing = false }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let fullImage = UIImage(data: data) {
                    let downsampled = downsample(fullImage, maxDimension: 4096)
                    selectedImage = downsampled
                    isVideo = false
                } else {
                    toastMessage = "Не удалось загрузить фото"
                    showToast = true
                }
            }
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

    var selectedPreset: ShacalPreset?

    func selectPreset(_ preset: ShacalPreset) {
        if isVideo {
            guard let sourceURL = selectedVideoURL else { return }
            
            if selectedPreset == preset {
                selectedPreset = nil
                processedVideoURL = nil
                return
            }
            
            selectedPreset = preset
            isProcessing = true
            processingProgress = 0.0
            
            Task { @MainActor in
                do {
                    let result = try await VideoProcessor.process(videoURL: sourceURL, preset: preset) { progress in
                        Task { @MainActor in
                            self.processingProgress = progress
                        }
                    }
                    processedVideoURL = result
                    isProcessing = false
                    showingOriginal = false
                } catch {
                    isProcessing = false
                    toastMessage = "Ошибка обработки видео: \(error.localizedDescription)"
                    showToast = true
                }
            }
        } else {
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
    }

    func saveProcessedMedia() {
        if isVideo {
            guard let url = processedVideoURL else { return }
            isProcessing = true
            processingProgress = 1.0
            
            Task { @MainActor in
                defer { isProcessing = false }
                do {
                    try await SaveManager.saveVideoToPhotos(url)
                    toastMessage = "Видео сохранено в Фото"
                    showToast = true
                } catch {
                    toastMessage = error.localizedDescription
                    showToast = true
                }
            }
        } else {
            guard let image = processedImage else { return }
            isProcessing = true
            
            Task { @MainActor in
                defer { isProcessing = false }
                do {
                    try await SaveManager.saveToPhotos(image)
                    toastMessage = "Фото сохранено в Фото"
                    showToast = true
                } catch {
                    toastMessage = error.localizedDescription
                    showToast = true
                }
            }
        }
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
                        matching: .any(of: [.images, .videos]),
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
            .animation(.easeInOut(duration: 0.35), value: viewModel.selectedImage != nil || viewModel.selectedVideoURL != nil)
            .animation(.easeInOut(duration: 0.3), value: viewModel.selectedPreset)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.selectedImage != nil || viewModel.selectedVideoURL != nil {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    if viewModel.isVideo {
                        if let originalURL = viewModel.selectedVideoURL {
                            VideoComparisonView(
                                originalURL: originalURL,
                                processedURL: viewModel.processedVideoURL,
                                showingOriginal: Binding(
                                    get: { viewModel.showingOriginal },
                                    set: { viewModel.showingOriginal = $0 }
                                )
                            )
                            .padding(.horizontal, 16)
                        }
                    } else {
                        if let selectedImage = viewModel.selectedImage {
                            ImageComparisonView(
                                originalImage: selectedImage,
                                processedImage: viewModel.processedImage,
                                showingOriginal: Binding(
                                    get: { viewModel.showingOriginal },
                                    set: { viewModel.showingOriginal = $0 }
                                )
                            )
                            .padding(.horizontal, 16)
                        }
                    }

                    presetSection

                    if viewModel.processedImage != nil || viewModel.processedVideoURL != nil {
                        actionButtons
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 16)
            }
        } else {
            PhotosPicker(
                selection: Binding(
                    get: { viewModel.selectedPhotoItem },
                    set: { viewModel.selectedPhotoItem = $0 }
                ),
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                EmptyStateView { }
            }
            .buttonStyle(.plain)
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
                viewModel.saveProcessedMedia()
            } label: {
                Label("Сохранить", systemImage: "square.and.arrow.down")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            if viewModel.isVideo {
                if let processedVideoURL = viewModel.processedVideoURL {
                    ShareLink(
                        item: processedVideoURL,
                        preview: SharePreview("Шакализированное видео", icon: Image(systemName: "video.fill"))
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
            } else {
                if let shareImage = viewModel.processedImage {
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

                if viewModel.isVideo {
                    Text("Шакализация... \(Int(viewModel.processingProgress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                } else {
                    Text("Шакализация...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                }
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

// MARK: - Video Comparison Component

struct VideoComparisonView: View {
    let originalURL: URL
    let processedURL: URL?
    @Binding var showingOriginal: Bool

    @State private var player = AVPlayer()
    @State private var isPlaying = true

    var body: some View {
        VStack(spacing: 14) {
            // Segmented picker
            if processedURL != nil {
                Picker("Режим", selection: $showingOriginal) {
                    Text("Оригинал").tag(true)
                    Text("Результат").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 4)
            }

            // Video Player Display with Play/Pause overlay
            ZStack {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(height: 360)

                // Optional custom overlay
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            if isPlaying {
                                player.pause()
                                isPlaying = false
                            } else {
                                player.play()
                                isPlaying = true
                            }
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.black.opacity(0.4), in: Circle())
                        }
                        .padding(12)
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Size and File Size info
            let activeURL = (showingOriginal || processedURL == nil) ? originalURL : processedURL
            if let activeURL = activeURL {
                HStack(spacing: 8) {
                    Image(systemName: "video")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(getFileSizeString(url: activeURL))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(14)
        .glassBackground(cornerRadius: 20)
        .onAppear {
            setupPlayer()
        }
        .onChange(of: showingOriginal) { _, _ in
            setupPlayer()
        }
        .onChange(of: processedURL) { _, _ in
            setupPlayer()
        }
        .onDisappear {
            player.pause()
        }
    }

    private func setupPlayer() {
        let activeURL = (showingOriginal || processedURL == nil) ? originalURL : processedURL!
        player.pause()
        
        let playerItem = AVPlayerItem(url: activeURL)
        player.replaceCurrentItem(with: playerItem)
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        player.play()
        isPlaying = true
    }

    private func getFileSizeString(url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return ""
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

#Preview {
    ContentView()
}
