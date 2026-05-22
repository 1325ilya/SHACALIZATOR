import SwiftUI

struct PresetCardView: View {
    let preset: ShacalPreset
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.49, green: 0.23, blue: 0.93),
                Color(red: 0.65, green: 0.35, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? AnyShapeStyle(accentGradient)
                                : AnyShapeStyle(Color.secondary.opacity(0.15))
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: preset.icon)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? .white : .secondary)
                }

                VStack(spacing: 4) {
                    Text(preset.name)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(preset.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 130, height: 150)
            .glassBackground(cornerRadius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected
                            ? Color.purple.opacity(0.7)
                            : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white, .purple)
                        .offset(x: -8, y: 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isSelected ? 1.03 : 1.0)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack {
        PresetCardView(preset: .light, isSelected: false) { }
        PresetCardView(preset: .hard, isSelected: true) { }
    }
    .padding()
    .background(Color.black)
}
