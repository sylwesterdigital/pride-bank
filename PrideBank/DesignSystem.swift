import SwiftUI

enum PrideTheme {
    static let background = LinearGradient(
        colors: [Color(red: 0.08, green: 0.07, blue: 0.22), Color(red: 0.09, green: 0.17, blue: 0.31), .black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let card = Color.white.opacity(0.085)
    static let cardStrong = Color.white.opacity(0.13)
    static let secondary = Color.white.opacity(0.62)
}

struct BlockMark: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(.white)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(45))
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(Color.black.opacity(0.84))
                .frame(width: size * 0.42, height: size * 0.42)
                .rotationEffect(.degrees(45))
        }
        .frame(width: size * 1.25, height: size * 1.25)
        .accessibilityHidden(true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(.white.opacity(configuration.isPressed ? 0.76 : 0.96), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(PrideTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
    }
}
