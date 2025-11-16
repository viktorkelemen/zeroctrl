import SwiftUI

/// LED meter display for visualizing CV voltages
struct LedMeter: View {
    let value: Float  // -5.0 to +5.0 volts
    let segments: Int = 12

    private let goldColor = Color(red: 0.85, green: 0.75, blue: 0.45)
    private let darkGray = Color(red: 0.15, green: 0.15, blue: 0.15)

    var body: some View {
        VStack(spacing: 2) {
            // Segments
            HStack(spacing: 3) {
                ForEach(0..<segments, id: \.self) { index in
                    segmentView(index: index)
                }
            }

            // Value label
            Text(String(format: "%.2fV", value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(goldColor)
        }
    }

    private func segmentView(index: Int) -> some View {
        let segmentValue = Float(index) / Float(segments - 1)  // 0.0 to 1.0
        let normalizedValue = (value + 5.0) / 10.0  // -5V to +5V -> 0.0 to 1.0

        let isLit = normalizedValue >= segmentValue

        return Rectangle()
            .fill(isLit ? goldColor : darkGray)
            .frame(width: 8, height: 20)
            .cornerRadius(2)
            .shadow(color: isLit ? goldColor.opacity(0.5) : .clear, radius: 2)
    }
}

#Preview {
    VStack(spacing: 20) {
        LedMeter(value: -5.0)
        LedMeter(value: 0.0)
        LedMeter(value: 2.5)
        LedMeter(value: 5.0)
    }
    .padding()
}
