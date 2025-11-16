import Foundation
import AVFoundation
import CoreAudio
import Atomics

/// Audio engine that generates CV signals via ES-8 or compatible DC-coupled interface
class CVAudioEngine: ObservableObject {

    // MARK: - Published Properties

    @Published var availableDevices: [AudioDeviceManager.DeviceInfo] = []
    @Published var selectedDevice: AudioDeviceManager.DeviceInfo?
    @Published var isRunning: Bool = false
    @Published var currentStep: Int = 0
    @Published var errorMessage: String?

    // MARK: - Audio Components

    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?

    private let model: ZeroCtrlModel
    private let router: CvOutputRouter
    private let calibrationManager: CalibrationManager

    // MARK: - Audio Thread State

    // Gate timing (audio thread only)
    private var gateRemainingSamples: Int = 0
    private var lastStep: Int = -1
    
    // Test tone generation for non-ES-8 devices
    private let isTestModeAtomic = ManagedAtomic<Bool>(false)
    private var testPhase: Double = 0.0  // Only accessed on audio thread

    // Atomics for UI thread communication
    private let currentStepAtomic = ManagedAtomic<Int>(0)

    // MARK: - Initialization

    init() {
        self.model = ZeroCtrlModel()
        self.router = CvOutputRouter()
        self.calibrationManager = CalibrationManager()

        // Load calibration
        let calibFile = CalibrationManager.getDefaultCalibrationFile()
        _ = calibrationManager.loadFromFile(calibFile)

        // Discover devices
        refreshDevices()

        // Start UI update timer
        startUITimer()
    }

    // MARK: - Device Management

    func refreshDevices() {
        availableDevices = AudioDeviceManager.getOutputDevices()

        // Auto-select ES-8 if available
        if selectedDevice == nil {
            selectedDevice = AudioDeviceManager.findES8Device()
                ?? availableDevices.first
        }
    }

    func selectDevice(_ device: AudioDeviceManager.DeviceInfo) {
        if isRunning {
            stop()
        }
        selectedDevice = device
    }

    // MARK: - Audio Engine Control

    func start() throws {
        print("🎵 CVAudioEngine.start() called")

        guard let device = selectedDevice else {
            print("❌ No device selected")
            throw CVAudioError.noDeviceSelected
        }

        print("✅ Selected device: \(device.name) (\(device.outputChannels) channels)")
        
        // Determine if we should use test mode (audible sine wave for non-ES-8 devices)
        let testMode = !device.isES8
        isTestModeAtomic.store(testMode, ordering: .relaxed)
        if testMode {
            print("🎵 Test mode enabled - will output audible sine waves for non-ES-8 device")
        } else {
            print("🎛️ ES-8 detected - outputting CV signals")
        }

        // Validate channel count
        guard device.outputChannels > 0 else {
            print("❌ Device has no output channels!")
            throw CVAudioError.invalidFormat
        }

        // Create audio engine
        let engine = AVAudioEngine()
        print("✅ AVAudioEngine created")

        // Determine sample rate and channel count
        // Try 96kHz first for better CV accuracy, fall back to 48kHz if not supported
        let preferredSampleRate: Double = 96000.0
        let fallbackSampleRate: Double = 48000.0
        
        // Ensure we have at least 2 channels (stereo minimum), cap at 8 for ES-8
        // Some audio devices don't support mono output via AVAudioEngine
        let channelCount = max(2, min(device.outputChannels, 8))

        print("🔍 Requesting format - sampleRate: \(preferredSampleRate), channels: \(channelCount)")

        // Try to create format with preferred sample rate
        var format = AVAudioFormat(
            standardFormatWithSampleRate: preferredSampleRate,
            channels: AVAudioChannelCount(channelCount)
        )
        
        // If that fails, try fallback sample rate
        if format == nil {
            print("⚠️ 96kHz not supported, trying 48kHz...")
            format = AVAudioFormat(
                standardFormatWithSampleRate: fallbackSampleRate,
                channels: AVAudioChannelCount(channelCount)
            )
        }
        
        // If still failing, try stereo as absolute fallback
        if format == nil && channelCount > 2 {
            print("⚠️ \(channelCount) channels not supported, trying stereo (2 channels)...")
            format = AVAudioFormat(
                standardFormatWithSampleRate: fallbackSampleRate,
                channels: 2
            )
        }
        
        guard let finalFormat = format else {
            print("❌ AVAudioFormat creation failed! Tried:")
            print("   - \(preferredSampleRate) Hz, \(channelCount) channels")
            print("   - \(fallbackSampleRate) Hz, \(channelCount) channels")
            print("   - \(fallbackSampleRate) Hz, 2 channels")
            throw CVAudioError.invalidFormat
        }

        let actualSampleRate = finalFormat.sampleRate
        let actualChannels = finalFormat.channelCount
        print("✅ Format created successfully: \(finalFormat)")
        print("📊 Using sample rate: \(actualSampleRate) Hz, channels: \(actualChannels)")

        // Create source node for CV generation
        let node = createSourceNode(format: finalFormat, sampleRate: actualSampleRate)

        // Connect nodes
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: finalFormat)
        
        // Set main mixer volume to full
        engine.mainMixerNode.volume = 1.0
        print("🔊 Main mixer volume set to 1.0")

        // Configure output device using Core Audio
        let deviceSetResult = AudioDeviceManager.setSystemDefaultDevice(deviceID: device.id)
        print("🔊 Set output device result: \(deviceSetResult ? "✅ Success" : "❌ Failed")")

        // Start engine
        print("🔄 Preparing audio engine...")
        engine.prepare()
        print("🔄 Starting audio engine...")
        try engine.start()
        print("✅ Audio engine started successfully!")
        print("🔊 Audio engine is running: \(engine.isRunning)")

        // Save references
        self.audioEngine = engine
        self.sourceNode = node

        // Start sequencer
        print("🔄 Starting sequencer...")
        model.start()
        print("✅ Sequencer started!")

        DispatchQueue.main.async {
            self.isRunning = true
            self.errorMessage = nil
            print("✅ UI updated - isRunning = true")
        }
    }

    func stop() {
        audioEngine?.stop()
        model.stop()

        DispatchQueue.main.async {
            self.isRunning = false
            self.currentStep = 0
        }
    }

    // MARK: - Model Access

    func getModel() -> ZeroCtrlModel {
        return model
    }

    func getRouter() -> CvOutputRouter {
        return router
    }

    func getCalibrationManager() -> CalibrationManager {
        return calibrationManager
    }

    // MARK: - Parameter Updates

    func setBPM(_ bpm: Double) {
        model.setBpm(bpm)
    }
    
    func getBPM() -> Double {
        return model.getBpm()
    }

    func setDirection(_ direction: ClockGenerator.Direction) {
        model.setDirection(direction)
    }
    
    func getDirection() -> ClockGenerator.Direction {
        return model.getDirection()
    }

    func setSequenceLength(_ length: Int) {
        model.setSequenceLength(length)
    }
    
    func getSequenceLength() -> Int {
        return model.getSequenceLength()
    }

    func setStepState(stepIndex: Int, state: StepState) {
        model.setStepState(stepIndex: stepIndex, state: state)
    }

    // MARK: - Audio Render Callback

    private func createSourceNode(format: AVAudioFormat, sampleRate: Double) -> AVAudioSourceNode {
        var renderCallCount = 0

        let node = AVAudioSourceNode(format: format) { [weak self] _, timestamp, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }

            // Debug: Log first few render calls
            renderCallCount += 1
            if renderCallCount <= 3 {
                print("🎵 Audio render callback #\(renderCallCount) - frameCount: \(frameCount)")
            }

            // Get buffer pointers
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            // Process sequencer model once for entire buffer
            let stepChanges = self.model.processBlock(
                externalClockInput: nil,
                numSamples: Int(frameCount),
                sampleRate: sampleRate
            )
            
            // Cache current state for this buffer (avoid repeated getCurrentStepState calls)
            let cachedCurrentState = self.model.getCurrentStepState()
            let cachedCurrentStep = self.model.getCurrentStep()
            
            // If there are step changes, use the first one for the entire buffer
            // (In practice, step changes happen infrequently relative to buffer size)
            if let firstChange = stepChanges.first {
                self.lastStep = firstChange.step
                self.currentStepAtomic.store(firstChange.step, ordering: .relaxed)

                // Calculate gate length from time CV
                let timeCv = firstChange.state.timeCv
                // Gate length: 0V = 10ms, 5V = 500ms (at 120 BPM, quarter note = 500ms)
                let gateLengthMs = 10.0 + (Double(timeCv) / 5.0) * 490.0
                let gateLengthSamples = Int((gateLengthMs / 1000.0) * sampleRate)
                self.gateRemainingSamples = gateLengthSamples
            }

            // Process each frame (sample)
            for frame in 0..<Int(frameCount) {

                // Determine gate state
                let gateActive = self.gateRemainingSamples > 0
                if self.gateRemainingSamples > 0 {
                    self.gateRemainingSamples -= 1
                }

                for channelIndex in 0..<ablPointer.count {
                    guard let channelData = ablPointer[channelIndex].mData?.assumingMemoryBound(to: Float.self) else {
                        continue
                    }

                    var outputSample: Float = 0.0
                    
                    if self.isTestModeAtomic.load(ordering: .relaxed) {
                        // TEST MODE: Generate audible sine wave based on pitch CV (use cached state)
                        
                        // Map pitch CV (-5V to +5V) to frequency (110 Hz to 880 Hz)
                        // -5V = 110 Hz (A2), 0V = 440 Hz (A4), +5V = 880 Hz (A5)
                        let baseFreq = 440.0
                        let octaves = Double(cachedCurrentState.pitchCv) // Use cached state
                        let frequency = baseFreq * pow(2.0, octaves / 5.0)
                        
                        // Generate sine wave with proper phase accumulation
                        let amplitude: Float = gateActive ? (cachedCurrentState.strengthCv / 5.0) * 0.3 : 0.0
                        outputSample = amplitude * Float(sin(self.testPhase))
                        
                        // Advance phase (in radians)
                        self.testPhase += 2.0 * .pi * frequency / sampleRate
                        // Wrap phase to prevent overflow (keep between 0 and 2π)
                        if self.testPhase >= 2.0 * .pi {
                            self.testPhase -= 2.0 * .pi
                        }
                        
                    } else {
                        // ES-8 MODE: Generate CV signals (use cached step)
                        // Get routed CV value
                        var cv = self.router.getChannelOutput(
                            channel: channelIndex,
                            model: self.model,
                            currentStep: cachedCurrentStep,
                            gateActive: gateActive
                        )

                        // Apply calibration
                        cv = self.calibrationManager.applyCalibratedCV(
                            channel: channelIndex,
                            rawCV: cv
                        )
                        
                        outputSample = cv
                    }

                    // Write to output
                    channelData[frame] = outputSample
                }
            }

            return noErr
        }

        return node
    }

    // MARK: - UI Update Timer

    private var uiTimer: Timer?

    private func startUITimer() {
        uiTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let step = self.currentStepAtomic.load(ordering: .relaxed)
            if self.currentStep != step {
                DispatchQueue.main.async {
                    self.currentStep = step
                }
            }
        }
    }
}

// MARK: - Errors

enum CVAudioError: LocalizedError {
    case noDeviceSelected
    case invalidFormat
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .noDeviceSelected:
            return "No audio device selected"
        case .invalidFormat:
            return "Invalid audio format"
        case .engineStartFailed:
            return "Failed to start audio engine"
        }
    }
}
