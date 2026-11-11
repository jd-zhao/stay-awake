import SwiftUI

enum UtilityLayout {
    static let width: CGFloat = 328
    static let height: CGFloat = 304
    static let labelWidth: CGFloat = 72
    static let columnSpacing: CGFloat = 10
}

struct Palette {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var background: Color { Color(nsColor: .windowBackgroundColor) }
    var foreground: Color { Color(nsColor: .labelColor) }
    var secondary: Color { Color(nsColor: .secondaryLabelColor) }
    var buttonText: Color { dark ? .black : .white }
}

struct FormRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: UtilityLayout.columnSpacing) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: UtilityLayout.labelWidth, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: 26)
    }
}

struct UtilityButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let p = Palette(scheme)
        configuration.label.font(.system(size: 12, weight: .medium))
            .frame(height: 28).frame(minWidth: 72)
            .foregroundStyle(prominent ? p.buttonText : p.foreground)
            .background(prominent ? p.foreground : Color(nsColor: .controlColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(prominent ? .clear : Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5))
            .opacity(!enabled ? 0.35 : configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SmallIconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary).frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}
