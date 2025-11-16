import Foundation
import CoreAudio
import AVFoundation

/// Manages audio device detection and configuration for CV output
class AudioDeviceManager {

    // MARK: - Device Information

    struct DeviceInfo: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
        let outputChannels: Int
        let isES8: Bool

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool {
            return lhs.id == rhs.id
        }
    }

    // MARK: - Device Enumeration

    /// Get all available audio output devices
    static func getOutputDevices() -> [DeviceInfo] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            print("Failed to get device list size")
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            print("Failed to get device list")
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard let name = getDeviceName(deviceID) else { return nil }
            guard let channels = getOutputChannelCount(deviceID), channels > 0 else { return nil }

            let isES8 = name.contains("ES-8") || name.contains("Expert Sleepers")

            return DeviceInfo(
                id: deviceID,
                name: name,
                outputChannels: channels,
                isES8: isES8
            )
        }
    }

    /// Find the ES-8 device automatically
    static func findES8Device() -> DeviceInfo? {
        return getOutputDevices().first { $0.isES8 }
    }

    // MARK: - Device Properties

    private static func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceName: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let result = withUnsafeMutablePointer(to: &deviceName) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                pointer
            )
        }
        
        guard result == noErr, let name = deviceName else {
            return nil
        }

        return name as String
    }

    private static func getOutputChannelCount(_ deviceID: AudioDeviceID) -> Int? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return nil
        }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferListPointer
        ) == noErr else {
            return nil
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        var totalChannels = 0

        for buffer in bufferList {
            totalChannels += Int(buffer.mNumberChannels)
        }

        return totalChannels
    }

    /// Set the system default output device
    static func setSystemDefaultDevice(deviceID: AudioDeviceID) -> Bool {
        var deviceIDCopy = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let result = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDCopy
        )

        return result == noErr
    }
}
