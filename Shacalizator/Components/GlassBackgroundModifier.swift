import SwiftUI

struct GlassBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat
    var material: Material

    func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func glassBackground(
        cornerRadius: CGFloat = 20,
        material: Material = .ultraThinMaterial
    ) -> some View {
        modifier(GlassBackgroundModifier(cornerRadius: cornerRadius, material: material))
    }
}
