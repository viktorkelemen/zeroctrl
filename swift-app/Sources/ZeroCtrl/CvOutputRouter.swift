import Foundation
import Atomics

class CvOutputRouter {
    enum SignalSource: Int, Codable, CaseIterable {
        case none = 0
        case sequencerPitch      // Main sequence pitch CV
        case sequencerGate       // Main sequence gate
        case sequencerTime       // Time/length CV
        case sequencerStrength   // Strength/velocity CV
        case masterClock         // Clock output
        case stepGate1           // Individual step gates
        case stepGate2
        case stepGate3
        case stepGate4
        case stepGate5
        case stepGate6
        case stepGate7
        case stepGate8

        var name: String {
            switch self {
            case .none: return "None"
            case .sequencerPitch: return "Pitch CV"
            case .sequencerGate: return "Gate"
            case .sequencerTime: return "Time CV"
            case .sequencerStrength: return "Strength CV"
            case .masterClock: return "Clock"
            case .stepGate1: return "Step 1 Gate"
            case .stepGate2: return "Step 2 Gate"
            case .stepGate3: return "Step 3 Gate"
            case .stepGate4: return "Step 4 Gate"
            case .stepGate5: return "Step 5 Gate"
            case .stepGate6: return "Step 6 Gate"
            case .stepGate7: return "Step 7 Gate"
            case .stepGate8: return "Step 8 Gate"
            }
        }
    }

    struct ChannelConfig: Codable {
        var source: SignalSource
        var gain: Float          // Output gain (0.0 - 2.0)
        var offset: Float        // DC offset (-5V to +5V)
        var inverted: Bool       // Invert signal

        static let `default` = ChannelConfig(
            source: .none,
            gain: 1.0,
            offset: 0.0,
            inverted: false
        )
    }

    private static let maxChannels = 8

    // Store each config field separately as atomics for lock-free access
    // Use UInt32 bit pattern for Float atomics
    private var sources: [ManagedAtomic<Int>]
    private var gainsBits: [ManagedAtomic<UInt32>]
    private var offsetsBits: [ManagedAtomic<UInt32>]
    private var inverted: [ManagedAtomic<Bool>]

    init() {
        // Initialize atomic arrays with default values
        self.sources = (0..<Self.maxChannels).map { channel in
            // Default routing: Ch0=Pitch, Ch1=Gate, Ch2=Time, Ch3=Strength
            let defaultSource: SignalSource
            switch channel {
            case 0: defaultSource = .sequencerPitch
            case 1: defaultSource = .sequencerGate
            case 2: defaultSource = .sequencerTime
            case 3: defaultSource = .sequencerStrength
            default: defaultSource = .none
            }
            return ManagedAtomic<Int>(defaultSource.rawValue)
        }

        self.gainsBits = (0..<Self.maxChannels).map { _ in ManagedAtomic<UInt32>(Float(1.0).bitPattern) }
        self.offsetsBits = (0..<Self.maxChannels).map { _ in ManagedAtomic<UInt32>(Float(0.0).bitPattern) }
        self.inverted = (0..<Self.maxChannels).map { _ in ManagedAtomic<Bool>(false) }
    }

    // MARK: - UI Thread

    func setChannelConfig(channel: Int, config: ChannelConfig) {
        guard channel >= 0 && channel < Self.maxChannels else { return }

        sources[channel].store(config.source.rawValue, ordering: .relaxed)
        gainsBits[channel].store(config.gain.bitPattern, ordering: .relaxed)
        offsetsBits[channel].store(config.offset.bitPattern, ordering: .relaxed)
        inverted[channel].store(config.inverted, ordering: .relaxed)
    }

    func getChannelConfig(channel: Int) -> ChannelConfig {
        guard channel >= 0 && channel < Self.maxChannels else { return .default }

        let sourceRaw = sources[channel].load(ordering: .relaxed)
        let source = SignalSource(rawValue: sourceRaw) ?? .none
        let gainBits = gainsBits[channel].load(ordering: .relaxed)
        let offsetBits = offsetsBits[channel].load(ordering: .relaxed)

        return ChannelConfig(
            source: source,
            gain: Float(bitPattern: gainBits),
            offset: Float(bitPattern: offsetBits),
            inverted: inverted[channel].load(ordering: .relaxed)
        )
    }

    // MARK: - Audio Thread (Lock-Free)

    func getChannelOutput(
        channel: Int,
        model: ZeroCtrlModel,
        currentStep: Int,
        gateActive: Bool
    ) -> Float {
        guard channel >= 0 && channel < Self.maxChannels else { return 0.0 }

        // Get configuration
        let sourceRaw = sources[channel].load(ordering: .relaxed)
        guard let source = SignalSource(rawValue: sourceRaw) else { return 0.0 }

        let gainBits = gainsBits[channel].load(ordering: .relaxed)
        let offsetBits = offsetsBits[channel].load(ordering: .relaxed)
        let gain = Float(bitPattern: gainBits)
        let offset = Float(bitPattern: offsetBits)
        let isInverted = inverted[channel].load(ordering: .relaxed)

        // Get signal value
        var value = getSignalValue(
            source: source,
            model: model,
            currentStep: currentStep,
            gateActive: gateActive
        )

        // Apply gain and offset
        value = (value * gain) + offset

        // Apply inversion
        if isInverted {
            value = -value
        }

        // Clamp to ±5V
        return max(-5.0, min(5.0, value))
    }

    // MARK: - Private Methods

    private func getSignalValue(
        source: SignalSource,
        model: ZeroCtrlModel,
        currentStep: Int,
        gateActive: Bool
    ) -> Float {
        let stepState = model.getCurrentStepState()

        switch source {
        case .none:
            return 0.0

        case .sequencerPitch:
            return stepState.pitchCv

        case .sequencerGate:
            return gateActive ? 5.0 : 0.0

        case .sequencerTime:
            return stepState.timeCv

        case .sequencerStrength:
            return stepState.strengthCv

        case .masterClock:
            // Simple clock pulse (would need gate timing)
            return gateActive ? 5.0 : 0.0

        case .stepGate1, .stepGate2, .stepGate3, .stepGate4,
             .stepGate5, .stepGate6, .stepGate7, .stepGate8:
            let stepIndex = source.rawValue - SignalSource.stepGate1.rawValue
            return (currentStep == stepIndex && gateActive) ? 5.0 : 0.0
        }
    }

    // MARK: - Persistence

    func saveToJSON() -> String? {
        var configs: [ChannelConfig] = []

        for channel in 0..<Self.maxChannels {
            configs.append(getChannelConfig(channel: channel))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        guard let data = try? encoder.encode(configs),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return json
    }

    func loadFromJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let configs = try? JSONDecoder().decode([ChannelConfig].self, from: data) else {
            return false
        }

        for (channel, config) in configs.enumerated() {
            guard channel < Self.maxChannels else { break }
            setChannelConfig(channel: channel, config: config)
        }

        return true
    }
}
