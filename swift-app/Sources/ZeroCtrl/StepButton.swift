import SwiftUI

/// Step button with LED indicator, inspired by Make Noise hardware
struct StepButton: View {
    let stepNumber: Int
    @Binding var isActive: Bool
    let isCurrentStep: Bool

    private let buttonSize: CGFloat = 50
    private let goldColor = Color(red: 0.75, green: 0.60, blue: 0.25)
    private let lightGray = Color(red: 0.90, green: 0.90, blue: 0.92)
    private let darkText = Color(red: 0.20, green: 0.20, blue: 0.20)

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
                    .fill(isActive ? lightGray : lightGray.opacity(0.5))
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(
                        Circle()
                            .stroke(isActive ? goldColor : goldColor.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

                // Step number
                Text("\(stepNumber)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? darkText : darkText.opacity(0.4))
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
