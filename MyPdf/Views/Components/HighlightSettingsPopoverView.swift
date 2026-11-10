import SwiftUI

struct HighlightSettingsPopoverView: View {
    @Binding var selectedColor: HighlightColor
    @Binding var strength: Double
    @Binding var useFixedHeight: Bool
    @Binding var fixedHeight: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("Highlight Settings")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            // Colors
            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    ForEach(HighlightColor.allCases) { c in
                        Button {
                            selectedColor = c
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(c.color)
                                    .frame(width: 26, height: 26)
                                    .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)

                                if selectedColor == c {
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.65), lineWidth: 2)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color.black.opacity(0.75))
                                }
                            }
                            .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .help(c.rawValue)
                    }
                }
            }

            Divider()

            // Strength (Opacity)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Strength")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(round(strength * 100)))%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Slider(value: $strength, in: 0.15...0.90, step: 0.05)
            }

            Divider()

            // Fixed Height (Free Mode)
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $useFixedHeight) {
                    Text("Fixed Height")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.checkbox)

                if useFixedHeight {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Height")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(round(fixedHeight))) pt")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $fixedHeight, in: 10...50, step: 1)

                        Text("Drag left-to-right along text lines without vertical drift.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 18)
                }
            }

            Divider()

            // Live Preview
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .frame(height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )

                    Text("Highlight text sample")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selectedColor.color.opacity(strength))
                        .frame(width: 170, height: useFixedHeight ? min(CGFloat(fixedHeight), 32) : 20)
                }
            }
        }
        .padding(14)
        .frame(width: 250)
    }
}
