import SwiftUI

/// Step button with LED indicator, inspired by Make Noise hardware
struct StepButton: View {
    let stepNumber: Int
    @Binding var isActive: Bool
    let isCurrentStep: Bool

    private let buttonSize: CGFloat = 50
    private let goldColor = Color(red: 0.85, green: 0.75, blue: 0.45)
    private let darkGray = Color(red: 0.12, green: 0.12, blue: 0.12)
    private let creamColor = Color(red: 0.95, green: 0.92, blue: 0.85)

    var body: some View {
        Button(action: {
            isActive.toggle()
        }) {
            ZStack {
                // LED glow effect when current step (behind button)
                if isCurrentStep && isActive {
                    Circle()
                        .fill(goldColor)
                        .frame(width: buttonSize + 8, height: buttonSize + 8)
                        .opacity(0.4)
                        .blur(radius: 10)
                }
                
                // Button background
                Circle()
                    .fill(isActive ? darkGray : darkGray.opacity(0.5))
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(
                        Circle()
                            .stroke(isActive ? goldColor : goldColor.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)

                // Step number
                Text("\(stepNumber)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? creamColor : creamColor.opacity(0.4))
            }
            .frame(width: buttonSize + 8, height: buttonSize + 8) // Fixed frame to prevent layout shift
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: isCurrentStep && isActive)
    }
}

#Preview {
    HStack(spacing: 16) {
        StepButton(stepNumber: 1, isActive: .constant(true), isCurrentStep: true)
        StepButton(stepNumber: 2, isActive: .constant(true), isCurrentStep: false)
        StepButton(stepNumber: 3, isActive: .constant(false), isCurrentStep: false)
    }
    .padding()
}
