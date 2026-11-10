import SwiftUI

struct LiquidGlassSegmentContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(2)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
        )
    }
}

struct LiquidGlassButton: View {
    let icon: String
    let tooltip: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: 28, height: 22)
                .background(backgroundView)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isSelected {
            if isEnabled {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.30),
                                    Color.accentColor.opacity(0.18)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.50),
                                    Color.accentColor.opacity(0.30)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                }
                .shadow(color: Color.accentColor.opacity(0.22), radius: 2, x: 0, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        } else if isHovered && isEnabled {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        } else {
            Color.clear
        }
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return .secondary.opacity(0.5)
        }
        if isSelected {
            return .accentColor
        }
        return isHovered ? .primary : .secondary
    }
}
