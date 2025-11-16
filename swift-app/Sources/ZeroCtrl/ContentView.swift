import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = CVAudioEngine()
    @State private var bpm: Double = 120.0
    @State private var direction: ClockGenerator.Direction = .forward
    @State private var sequenceLength: Int = 8

    // Step states (pitch, time, strength knobs)
    @State private var stepStates: [StepState] = Array(repeating: .default, count: 8)
    @State private var stepActive: [Bool] = Array(repeating: true, count: 8)

    // Make Noise 0-CTRL color palette
    private let goldColor = Color(red: 0.85, green: 0.75, blue: 0.45) // Warm gold
    private let darkGray = Color(red: 0.12, green: 0.12, blue: 0.12) // Deep black
    private let creamColor = Color(red: 0.95, green: 0.92, blue: 0.85) // Cream/off-white
    private let backgroundColor = Color(red: 0.08, green: 0.08, blue: 0.08) // Almost black
    private let panelColor = Color(red: 0.15, green: 0.15, blue: 0.15) // Charcoal

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                headerView

                // Device Selection
                deviceSelectionView
                
                // Error message display
                if let errorMessage = audioEngine.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        Spacer()
                        Button("Dismiss") {
                            audioEngine.errorMessage = nil
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(goldColor)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }

                // Transport Controls
                transportControlsView

                // Step Sequencer (8 columns)
                stepSequencerView

                // LED Meters
                ledMetersView

                Spacer()

                // Status Bar
                statusBarView
            }
            .padding(24)
        }
        .frame(width: 1300, height: 1000)
        .preferredColorScheme(.dark)
        .onAppear {
            // Sync UI state with audio engine on startup
            bpm = audioEngine.getBPM()
            direction = audioEngine.getDirection()
            sequenceLength = audioEngine.getSequenceLength()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("ZERO CTRL")
                .font(.system(size: 42, weight: .black, design: .monospaced))
                .foregroundColor(goldColor)

            Text("8-Step CV Sequencer")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(creamColor.opacity(0.7))
        }
    }

    // MARK: - Device Selection

    private var deviceSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUDIO DEVICE")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(goldColor)

            HStack {
                Picker("Device", selection: Binding(
                    get: { 
                        audioEngine.selectedDevice?.id ?? (audioEngine.availableDevices.first?.id ?? 0)
                    },
                    set: { deviceID in
                        if let device = audioEngine.availableDevices.first(where: { $0.id == deviceID }) {
                            audioEngine.selectDevice(device)
                        }
                    }
                )) {
                    ForEach(audioEngine.availableDevices) { device in
                        HStack {
                            Text(device.name)
                            if device.isES8 {
                                Text("⭐").foregroundColor(goldColor)
                            }
                            Text("(\(device.outputChannels) ch)")
                                .foregroundColor(creamColor.opacity(0.5))
                        }
                        .tag(device.id)
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: {
                    audioEngine.refreshDevices()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(goldColor)
                }
            }
        }
        .padding()
        .background(panelColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(goldColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Transport Controls

    private var transportControlsView: some View {
        HStack(spacing: 24) {
            // BPM Control
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TEMPO")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(goldColor)
                    Spacer()
                    Text("\(Int(bpm)) BPM")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(creamColor)
                }

                Slider(value: $bpm, in: 30...300, step: 1) {
                    Text("BPM")
                }
                .tint(goldColor)
                .onChange(of: bpm) { newValue in
                    audioEngine.setBPM(newValue)
                }
            }
            .frame(maxWidth: 300)

            // Play/Stop
            Button(action: {
                if audioEngine.isRunning {
                    audioEngine.stop()
                } else {
                    do {
                        try audioEngine.start()
                    } catch {
                        // Show error in UI
                        audioEngine.errorMessage = error.localizedDescription
                        print("❌ Failed to start: \(error)")
                    }
                }
            }) {
                HStack {
                    Image(systemName: audioEngine.isRunning ? "stop.fill" : "play.fill")
                    Text(audioEngine.isRunning ? "STOP" : "PLAY")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(audioEngine.isRunning ? creamColor : backgroundColor)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(audioEngine.isRunning ? Color.red.opacity(0.8) : goldColor)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Direction
            VStack(alignment: .leading, spacing: 8) {
                Text("DIRECTION")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(goldColor)

                Picker("Direction", selection: $direction) {
                    Text("▶").tag(ClockGenerator.Direction.forward)
                    Text("◀").tag(ClockGenerator.Direction.backward)
                    Text("⟷").tag(ClockGenerator.Direction.pingPong)
                }
                .pickerStyle(.segmented)
                .onChange(of: direction) { newValue in
                    audioEngine.setDirection(newValue)
                }
            }
            .frame(maxWidth: 200)

            // Length
            VStack(alignment: .leading, spacing: 8) {
                Text("LENGTH")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(goldColor)

                Picker("Length", selection: $sequenceLength) {
                    ForEach(1...8, id: \.self) { length in
                        Text("\(length)").tag(length)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: sequenceLength) { newValue in
                    audioEngine.setSequenceLength(newValue)
                }
            }
            .frame(maxWidth: 200)
            
            // Randomize
            Button(action: {
                randomizeAllKnobs()
            }) {
                HStack {
                    Image(systemName: "shuffle")
                    Text("RANDOMIZE")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(backgroundColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color(red: 0.7, green: 0.5, blue: 0.8))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // Quantize
            Button(action: {
                quantizeAllPitches()
            }) {
                HStack {
                    Image(systemName: "waveform.path")
                    Text("QUANTIZE")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(backgroundColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(panelColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(goldColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Step Sequencer (Vertical Columns)

    private var stepSequencerView: some View {
        HStack(spacing: 24) {
            ForEach(0..<8) { stepIndex in
                VStack(spacing: 12) {
                    // Step button at top
                    StepButton(
                        stepNumber: stepIndex + 1,
                        isActive: Binding(
                            get: { 
                                guard stepIndex < stepActive.count else { return false }
                                return stepActive[stepIndex] 
                            },
                            set: { newValue in
                                guard stepIndex < stepActive.count else { return }
                                stepActive[stepIndex] = newValue
                                updateStepState(stepIndex: stepIndex)
                            }
                        ),
                        isCurrentStep: audioEngine.currentStep == stepIndex && audioEngine.isRunning
                    )
                    
                    // Pitch knob
                    RotaryKnob(
                        value: Binding(
                            get: {
                                guard stepIndex < stepStates.count else { return 0.0 }
                                let value = stepStates[stepIndex].pitchCv
                                // Normalize -5.0...5.0 to 0.0...1.0
                                return (value + 5.0) / 10.0
                            },
                            set: { normalized in
                                guard stepIndex < stepStates.count else { return }
                                // Denormalize 0.0...1.0 to -5.0...5.0
                                let value = (normalized * 10.0) - 5.0
                                stepStates[stepIndex].pitchCv = value
                                updateStepState(stepIndex: stepIndex)
                            }
                        ),
                        label: "PITCH",
                        minValue: -5.0,
                        maxValue: 5.0
                    )
                    
                    // Time knob
                    RotaryKnob(
                        value: Binding(
                            get: {
                                guard stepIndex < stepStates.count else { return 0.0 }
                                let value = stepStates[stepIndex].timeCv
                                return value / 5.0
                            },
                            set: { normalized in
                                guard stepIndex < stepStates.count else { return }
                                let value = normalized * 5.0
                                stepStates[stepIndex].timeCv = value
                                updateStepState(stepIndex: stepIndex)
                            }
                        ),
                        label: "TIME",
                        minValue: 0.0,
                        maxValue: 5.0
                    )
                    
                    // Strength knob
                    RotaryKnob(
                        value: Binding(
                            get: {
                                guard stepIndex < stepStates.count else { return 0.0 }
                                let value = stepStates[stepIndex].strengthCv
                                return value / 5.0
                            },
                            set: { normalized in
                                guard stepIndex < stepStates.count else { return }
                                let value = normalized * 5.0
                                stepStates[stepIndex].strengthCv = value
                                updateStepState(stepIndex: stepIndex)
                            }
                        ),
                        label: "STRENGTH",
                        minValue: 0.0,
                        maxValue: 5.0
                    )
                }
                .padding(12)
                .background(darkGray)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(goldColor.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - LED Meters

    private var ledMetersView: some View {
        HStack(spacing: 32) {
            meterView(label: "PITCH CV", value: currentPitchCV)
            meterView(label: "GATE CV", value: currentGateCV)
            meterView(label: "TIME CV", value: currentTimeCV)
            meterView(label: "STRENGTH CV", value: currentStrengthCV)
        }
        .padding()
        .background(panelColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(goldColor.opacity(0.2), lineWidth: 1)
        )
    }

    private func meterView(label: String, value: Float) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(goldColor)

            LedMeter(value: value)
        }
    }

    // MARK: - Status Bar

    private var statusBarView: some View {
        HStack {
            if audioEngine.isRunning {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Running at 96kHz")
                        .font(.system(size: 10))
                        .foregroundColor(creamColor.opacity(0.7))
                }
            }

            Spacer()

            if let device = audioEngine.selectedDevice {
                HStack(spacing: 8) {
                    Text("\(device.name) • \(device.outputChannels) channels")
                        .font(.system(size: 10))
                        .foregroundColor(creamColor.opacity(0.7))
                    
                    // Show test mode indicator
                    if !device.isES8 && audioEngine.isRunning {
                        Text("•")
                            .foregroundColor(creamColor.opacity(0.5))
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 9))
                            Text("TEST MODE")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(Color.orange)
                    }
                }
            }

            Spacer()

            Text("🤖 Generated with Claude Code")
                .font(.system(size: 10))
                .foregroundColor(creamColor.opacity(0.5))
        }
        .padding(.horizontal)
    }

    // MARK: - Helper Methods
    
    private func randomizeAllKnobs() {
        for stepIndex in 0..<8 {
            // Randomize pitch: -5.0 to +5.0
            stepStates[stepIndex].pitchCv = Float.random(in: -5.0...5.0)
            
            // Randomize time: 0.0 to 5.0
            stepStates[stepIndex].timeCv = Float.random(in: 0.0...5.0)
            
            // Randomize strength: 0.0 to 5.0
            stepStates[stepIndex].strengthCv = Float.random(in: 0.0...5.0)
            
            // Update the audio engine with the new state
            updateStepState(stepIndex: stepIndex)
        }
    }
    
    private func quantizeAllPitches() {
        for stepIndex in 0..<8 {
            // Quantize pitch to nearest semitone
            // In 1V/octave standard: 1 semitone = 1/12 volt = 0.0833V
            let semitoneValue: Float = 1.0 / 12.0
            let currentPitch = stepStates[stepIndex].pitchCv
            
            // Round to nearest semitone
            let quantizedPitch = round(currentPitch / semitoneValue) * semitoneValue
            
            // Clamp to valid range
            stepStates[stepIndex].pitchCv = max(-5.0, min(5.0, quantizedPitch))
            
            // Update the audio engine with the quantized state
            updateStepState(stepIndex: stepIndex)
        }
    }

    private func updateStepState(stepIndex: Int) {
        guard stepIndex >= 0 && stepIndex < stepStates.count && stepIndex < stepActive.count else {
            return
        }
        var state = stepStates[stepIndex]
        state.active = stepActive[stepIndex]
        audioEngine.setStepState(stepIndex: stepIndex, state: state)
    }

    // Current CV values for display
    private var currentPitchCV: Float {
        let state = audioEngine.getModel().getCurrentStepState()
        return state.pitchCv
    }

    private var currentGateCV: Float {
        return audioEngine.isRunning ? 5.0 : 0.0
    }

    private var currentTimeCV: Float {
        let state = audioEngine.getModel().getCurrentStepState()
        return state.timeCv
    }

    private var currentStrengthCV: Float {
        let state = audioEngine.getModel().getCurrentStepState()
        return state.strengthCv
    }
}

#Preview {
    ContentView()
}
