import SwiftUI

/// Custom rotary knob control inspired by Make Noise hardware
struct RotaryKnob: View {
    @Binding var value: Float  // 0.0 to 1.0
    let label: String
    let minValue: Float
    let maxValue: Float

    @State private var isDragging = false
    @State private var startValue: Float = 0.0

    private let knobSize: CGFloat = 60
    private let sensitivity: CGFloat = 0.005

    // Light color palette
    private let goldColor = Color(red: 0.75, green: 0.60, blue: 0.25)
    private let lightGray = Color(red: 0.90, green: 0.90, blue: 0.92)

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Knob background
                Circle()
                    .fill(lightGray)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

                // Knob indicator line
                Rectangle()
                    .fill(goldColor)
                    .frame(width: 3, height: knobSize * 0.35)
                    .offset(y: -knobSize * 0.25)
                    .rotationEffect(angleForValue())

                // Center dot
                Circle()
                    .fill(goldColor.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            startValue = value
                        }

                        // Vertical drag changes value
                        let delta = gesture.startLocation.y - gesture.location.y
                        let valueDelta = Float(delta * sensitivity)
                        let newValue = max(0.0, min(1.0, startValue + valueDelta))
                        value = newValue
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )

            // Label and value display
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                Text(String(format: "%.2fV", scaledValue()))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(goldColor)
            }
        }
    }

    private func angleForValue() -> Angle {
        // Map 0.0-1.0 to -135° to +135° (270° total range)
        let degrees = -135.0 + (Double(value) * 270.0)
        return Angle(degrees: degrees)
    }

    private func scaledValue() -> Float {
        return minValue + (value * (maxValue - minValue))
    }
}

#Preview {
    RotaryKnob(
        value: .constant(0.5),
        label: "PITCH",
        minValue: -5.0,
        maxValue: 5.0
    )
    .padding()
    .frame(width: 100, height: 100)
}
