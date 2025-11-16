import Foundation
import Atomics

// MARK: - Calibration Data

struct ChannelCalibration: Codable {
    var offsetVolts: Float
    var scaleVperOct: Float
    var isCalibrated: Bool

    static let `default` = ChannelCalibration(
        offsetVolts: 0.0,
        scaleVperOct: 1.0,
        isCalibrated: false
    )
}

struct CalibrationData: Codable {
    var channels: [ChannelCalibration]
    var calibratedAt: Date?

    static let `default` = CalibrationData(
        channels: Array(repeating: .default, count: 8),
        calibratedAt: nil
    )
}

// MARK: - Calibration Manager

class CalibrationManager {
    static let maxChannels = 8

    // Atomic access for audio thread (lock-free)
    // Use UInt32 bit pattern for Float atomics
    private var offsetsBits: [ManagedAtomic<UInt32>]
    private var scalesBits: [ManagedAtomic<UInt32>]
    private var calibrated: [ManagedAtomic<Bool>]

    // Cached data for UI thread
    private let lock = NSLock()
    private var cachedData: CalibrationData

    init() {
        // Initialize atomic arrays (using bit patterns for Float)
        self.offsetsBits = (0..<Self.maxChannels).map { _ in ManagedAtomic<UInt32>(Float(0.0).bitPattern) }
        self.scalesBits = (0..<Self.maxChannels).map { _ in ManagedAtomic<UInt32>(Float(1.0).bitPattern) }
        self.calibrated = (0..<Self.maxChannels).map { _ in ManagedAtomic<Bool>(false) }
        self.cachedData = .default
    }

    // MARK: - File I/O

    /// Get default calibration file path
    static func getDefaultCalibrationFile() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        let appDir = appSupport.appendingPathComponent("zero-ctrl", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: appDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return appDir.appendingPathComponent("calibration.json")
    }

    /// Load calibration from file
    func loadFromFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode(CalibrationData.self, from: data) else {
            print("Failed to load calibration from \(url.path)")
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        cachedData = loaded

        // Update atomic values for audio thread
        for (index, channel) in loaded.channels.enumerated() {
            guard index < Self.maxChannels else { break }
            offsetsBits[index].store(channel.offsetVolts.bitPattern, ordering: .relaxed)
            scalesBits[index].store(channel.scaleVperOct.bitPattern, ordering: .relaxed)
            calibrated[index].store(channel.isCalibrated, ordering: .relaxed)
        }

        print("Loaded calibration for \(loaded.channels.filter { $0.isCalibrated }.count) channels")
        return true
    }

    /// Save calibration to file
    func saveToFile(_ url: URL) -> Bool {
        lock.lock()
        let dataToSave = cachedData
        lock.unlock()

        guard let jsonData = try? JSONEncoder().encode(dataToSave) else {
            print("Failed to encode calibration data")
            return false
        }

        do {
            try jsonData.write(to: url, options: .atomic)
            print("Saved calibration to \(url.path)")
            return true
        } catch {
            print("Failed to save calibration: \(error)")
            return false
        }
    }

    // MARK: - Audio Thread (Lock-Free)

    /// Apply calibration to raw CV value (audio thread safe)
    func applyCalibratedCV(channel: Int, rawCV: Float) -> Float {
        guard channel >= 0 && channel < Self.maxChannels else {
            return rawCV
        }

        guard calibrated[channel].load(ordering: .relaxed) else {
            return rawCV
        }

        let offsetBits = offsetsBits[channel].load(ordering: .relaxed)
        let scaleBits = scalesBits[channel].load(ordering: .relaxed)
        let offset = Float(bitPattern: offsetBits)
        let scale = Float(bitPattern: scaleBits)

        return (rawCV * scale) + offset
    }

    // MARK: - UI Thread

    /// Update calibration for a specific channel
    func setChannelCalibration(channel: Int, offsetVolts: Float, scaleVperOct: Float) {
        guard channel >= 0 && channel < Self.maxChannels else { return }

        lock.lock()
        cachedData.channels[channel] = ChannelCalibration(
            offsetVolts: offsetVolts,
            scaleVperOct: scaleVperOct,
            isCalibrated: true
        )
        cachedData.calibratedAt = Date()
        lock.unlock()

        // Update atomic values for audio thread
        offsetsBits[channel].store(offsetVolts.bitPattern, ordering: .relaxed)
        scalesBits[channel].store(scaleVperOct.bitPattern, ordering: .relaxed)
        calibrated[channel].store(true, ordering: .relaxed)
    }

    /// Get current calibration data
    func getCalibrationData() -> CalibrationData {
        lock.lock()
        defer { lock.unlock() }
        return cachedData
    }

    /// Check if channel is calibrated
    func isCalibrated(channel: Int) -> Bool {
        guard channel >= 0 && channel < Self.maxChannels else { return false }
        return calibrated[channel].load(ordering: .relaxed)
    }
}
