import SwiftUI

struct EmptyStateView: View {
    var onPickPhoto: () -> Void

    @State private var iconBounce: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        colorScheme == .dark
                            ? Color(red: 0.65, green: 0.55, blue: 1.0)
                            : Color(red: 0.45, green: 0.30, blue: 0.85)
                    )
                    .scaleEffect(iconBounce ? 1.06 : 1.0)
                    .offset(y: iconBounce ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: iconBounce
                    )

                VStack(spacing: 8) {
                    Text("Выберите фото")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("Загрузите изображение, чтобы начать шакализацию")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .glassBackground()

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            iconBounce = true
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.04, blue: 0.20),
                Color(red: 0.04, green: 0.06, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        EmptyStateView { }
    }
}
