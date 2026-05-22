import SwiftUI

struct ImageComparisonView: View {
    let originalImage: UIImage
    let processedImage: UIImage?
    @Binding var showingOriginal: Bool

    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @Environment(\.colorScheme) private var colorScheme

    private var displayedImage: UIImage {
        if showingOriginal || processedImage == nil {
            return originalImage
        }
        return processedImage ?? originalImage
    }

    var body: some View {
        VStack(spacing: 14) {
            // Segmented picker
            if processedImage != nil {
                Picker("Режим", selection: $showingOriginal) {
                    Text("Оригинал").tag(true)
                    Text("Результат").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 4)
            }

            // Image display
            GeometryReader { geo in
                Image(uiImage: displayedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                    .scaleEffect(currentScale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let delta = value.magnification / lastScale
                                lastScale = value.magnification
                                currentScale = min(max(currentScale * delta, 1.0), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                withAnimation(.spring(duration: 0.3)) {
                                    currentScale = 1.0
                                }
                            }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .frame(height: 360)
            .animation(.easeInOut(duration: 0.25), value: showingOriginal)

            // Size indicator
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int(displayedImage.size.width))×\(Int(displayedImage.size.height))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .glassBackground(cornerRadius: 20)
    }
}

#Preview {
    @Previewable @State var showing = false
    let img = UIImage(systemName: "photo.artframe")!

    ImageComparisonView(
        originalImage: img,
        processedImage: nil,
        showingOriginal: $showing
    )
    .padding()
    .background(Color.black)
}
