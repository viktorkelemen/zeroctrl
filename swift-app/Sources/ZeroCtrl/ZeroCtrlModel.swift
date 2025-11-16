import Foundation
import Atomics

// MARK: - Step State

struct StepState {
    var pitchCv: Float      // -5V to +5V (10 octaves, 1V/oct standard)
    var timeCv: Float       // 0V to +5V (gate length modulation)
    var strengthCv: Float   // 0V to +5V (velocity/amplitude)
    var active: Bool        // Step on/off

    static let `default` = StepState(
        pitchCv: 0.0,
        timeCv: 2.5,      // Default to mid-range gate length
        strengthCv: 5.0,  // Default to full strength
        active: true
    )
}

// MARK: - Clock Generator

class ClockGenerator {
    enum ClockSource {
        case `internal`   // BPM-based internal clock
        case external     // Audio input clock sync
    }

    enum Direction {
        case forward
        case backward
        case random
        case pingPong
    }

    struct ClockEvent {
        let samplePosition: Int64
        let isClockTick: Bool
        let isReset: Bool
    }

    // Atomics for UI thread communication (using UInt64 bit pattern for Double)
    private let targetBpmBits = ManagedAtomic<UInt64>(120.0.bitPattern)
    private var clockSource: ClockSource = .internal
    private var direction: Direction = .forward
    private let resetRequested = ManagedAtomic<Bool>(false)

    private var targetBpm: Double {
        get { Double(bitPattern: targetBpmBits.load(ordering: .relaxed)) }
        set { targetBpmBits.store(newValue.bitPattern, ordering: .relaxed) }
    }

    // Audio thread state (not atomic - only accessed by audio thread)
    private var phase: Double = 0.0
    private var samplesPerClock: Double = 0.0
    private var totalSampleCount: Int64 = 0

    // External clock sync
    private var lastExternalValue: Float = 0.0
    private var lastClockSample: Int64 = 0
    private var measuredBpm: Double = 120.0

    private static let clockThreshold: Float = 0.5
    private static let minClockSamples: Int64 = 2400   // 50ms @ 48kHz
    private static let maxClockSamples: Int64 = 144000 // 3s @ 48kHz

    init() {
        updateSamplesPerClock(sampleRate: 48000.0)
    }

    // MARK: - UI Thread

    func setBpm(_ bpm: Double) {
        let clampedBpm = max(1.0, min(600.0, bpm))
        targetBpm = clampedBpm
    }
    
    func getBpm() -> Double {
        return targetBpm
    }

    func setClockSource(_ source: ClockSource) {
        clockSource = source
    }

    func setDirection(_ dir: Direction) {
        direction = dir
    }
    
    func getDirection() -> Direction {
        return direction
    }

    func reset() {
        resetRequested.store(true, ordering: .relaxed)
    }

    // MARK: - Audio Thread

    func processBlock(
        externalClockInput: UnsafePointer<Float>?,
        numSamples: Int,
        sampleRate: Double
    ) -> [ClockEvent] {
        var events: [ClockEvent] = []
        events.reserveCapacity(8) // Pre-allocate for worst case

        // Handle reset
        if resetRequested.load(ordering: .relaxed) {
            resetRequested.store(false, ordering: .relaxed)
            phase = 0.0
            events.append(ClockEvent(samplePosition: 0, isClockTick: false, isReset: true))
        }

        // Update samples per clock from BPM
        updateSamplesPerClock(sampleRate: sampleRate)

        // Process clock events
        if clockSource == .internal {
            events.append(contentsOf: updateInternalClock(numSamples: numSamples))
        } else if let input = externalClockInput {
            events.append(contentsOf: updateExternalClock(input: input, numSamples: numSamples, sampleRate: sampleRate))
        }

        totalSampleCount += Int64(numSamples)
        return events
    }

    // MARK: - Private Methods

    private func updateSamplesPerClock(sampleRate: Double) {
        let bpm = targetBpm
        let beatsPerSecond = bpm / 60.0
        let stepsPerSecond = beatsPerSecond * 2.0  // 8th notes (2 steps per beat)
        samplesPerClock = sampleRate / stepsPerSecond
    }

    private func updateInternalClock(numSamples: Int) -> [ClockEvent] {
        var events: [ClockEvent] = []

        for sample in 0..<numSamples {
            phase += 1.0 / samplesPerClock

            if phase >= 1.0 {
                phase -= 1.0
                events.append(ClockEvent(
                    samplePosition: Int64(sample),
                    isClockTick: true,
                    isReset: false
                ))
            }
        }

        return events
    }

    private func updateExternalClock(input: UnsafePointer<Float>, numSamples: Int, sampleRate: Double) -> [ClockEvent] {
        var events: [ClockEvent] = []

        for sample in 0..<numSamples {
            let value = input[sample]

            // Detect rising edge
            if lastExternalValue < Self.clockThreshold && value >= Self.clockThreshold {
                let samplesSinceLast = totalSampleCount + Int64(sample) - lastClockSample

                // Measure BPM from clock interval
                if samplesSinceLast >= Self.minClockSamples && samplesSinceLast <= Self.maxClockSamples {
                    let beatsPerSecond = sampleRate / Double(samplesSinceLast) / 2.0
                    measuredBpm = beatsPerSecond * 60.0
                }

                lastClockSample = totalSampleCount + Int64(sample)

                events.append(ClockEvent(
                    samplePosition: Int64(sample),
                    isClockTick: true,
                    isReset: false
                ))
            }

            lastExternalValue = value
        }

        return events
    }
}

// MARK: - Zero CTRL Model

class ZeroCtrlModel {
    // Components
    let clockGenerator = ClockGenerator()

    // State
    private let isRunning = ManagedAtomic<Bool>(false)
    private let sequenceLength = ManagedAtomic<Int>(8)
    private let resetRequested = ManagedAtomic<Bool>(false)

    // Step states (lock-free triple buffer would be better, but using simple array for now)
    private var steps: [StepState] = Array(repeating: .default, count: 8)
    private let stepsLock = NSLock()

    // Audio thread state (not atomic - only accessed by audio thread)
    private var currentStep: Int = 0
    private var pingPongDirection: Int = 1  // 1 for forward, -1 for backward

    init() {}

    // MARK: - UI Thread

    func start() {
        isRunning.store(true, ordering: .relaxed)
    }

    func stop() {
        isRunning.store(false, ordering: .relaxed)
        // Request reset on audio thread (don't directly modify audio thread state)
        resetRequested.store(true, ordering: .relaxed)
    }

    func getIsRunning() -> Bool {
        return isRunning.load(ordering: .relaxed)
    }

    func setBpm(_ bpm: Double) {
        clockGenerator.setBpm(bpm)
    }
    
    func getBpm() -> Double {
        return clockGenerator.getBpm()
    }

    func setDirection(_ direction: ClockGenerator.Direction) {
        clockGenerator.setDirection(direction)
        // Don't directly modify pingPongDirection - let audio thread handle it
        // The audio thread will naturally reset when direction changes
    }
    
    func getDirection() -> ClockGenerator.Direction {
        return clockGenerator.getDirection()
    }

    func setSequenceLength(_ length: Int) {
        let clamped = max(1, min(8, length))
        sequenceLength.store(clamped, ordering: .relaxed)
    }
    
    func getSequenceLength() -> Int {
        return sequenceLength.load(ordering: .relaxed)
    }

    func setStepState(stepIndex: Int, state: StepState) {
        guard stepIndex >= 0 && stepIndex < 8 else { return }

        stepsLock.lock()
        steps[stepIndex] = state
        stepsLock.unlock()
    }

    func setStepPitch(stepIndex: Int, pitchCv: Float) {
        guard stepIndex >= 0 && stepIndex < 8 else { return }

        stepsLock.lock()
        steps[stepIndex].pitchCv = pitchCv
        stepsLock.unlock()
    }

    func setStepTime(stepIndex: Int, timeCv: Float) {
        guard stepIndex >= 0 && stepIndex < 8 else { return }

        stepsLock.lock()
        steps[stepIndex].timeCv = timeCv
        stepsLock.unlock()
    }

    func setStepStrength(stepIndex: Int, strengthCv: Float) {
        guard stepIndex >= 0 && stepIndex < 8 else { return }

        stepsLock.lock()
        steps[stepIndex].strengthCv = strengthCv
        stepsLock.unlock()
    }

    func setStepActive(stepIndex: Int, active: Bool) {
        guard stepIndex >= 0 && stepIndex < 8 else { return }

        stepsLock.lock()
        steps[stepIndex].active = active
        stepsLock.unlock()
    }

    func getStepState(stepIndex: Int) -> StepState {
        guard stepIndex >= 0 && stepIndex < 8 else { return .default }

        stepsLock.lock()
        let state = steps[stepIndex]
        stepsLock.unlock()

        return state
    }

    func reset() {
        clockGenerator.reset()
        currentStep = 0
    }

    // MARK: - Audio Thread

    func processBlock(
        externalClockInput: UnsafePointer<Float>?,
        numSamples: Int,
        sampleRate: Double
    ) -> [(step: Int, state: StepState)] {
        // Handle reset request from UI thread
        if resetRequested.load(ordering: .relaxed) {
            resetRequested.store(false, ordering: .relaxed)
            currentStep = 0
            pingPongDirection = 1
        }
        
        guard isRunning.load(ordering: .relaxed) else {
            return []
        }

        let events = clockGenerator.processBlock(
            externalClockInput: externalClockInput,
            numSamples: numSamples,
            sampleRate: sampleRate
        )

        var stepChanges: [(step: Int, state: StepState)] = []

        for event in events {
            if event.isReset {
                currentStep = 0
            } else if event.isClockTick {
                advanceStep()
                stepChanges.append((step: currentStep, state: getCurrentStepState()))
            }
        }

        return stepChanges
    }

    func getCurrentStep() -> Int {
        return currentStep
    }

    func getCurrentStepState() -> StepState {
        guard currentStep >= 0 && currentStep < 8 else { return .default }

        // Audio thread read - should use lock-free structure in production
        stepsLock.lock()
        let state = steps[currentStep]
        stepsLock.unlock()

        return state
    }

    // MARK: - Private Methods

    private func advanceStep() {
        let length = sequenceLength.load(ordering: .relaxed)

        // Get direction from clock generator
        let direction = clockGenerator.getDirection()

        switch direction {
        case .forward:
            currentStep = (currentStep + 1) % length

        case .backward:
            currentStep = (currentStep - 1 + length) % length

        case .pingPong:
            currentStep += pingPongDirection
            if currentStep >= length {
                currentStep = length - 2
                pingPongDirection = -1
            } else if currentStep < 0 {
                currentStep = 1
                pingPongDirection = 1
            }

        case .random:
            currentStep = Int.random(in: 0..<length)
        }
    }
}
