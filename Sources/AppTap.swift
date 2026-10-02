import CoreAudio
import Foundation

/// Перехватывает звук набора процессов, глушит оригинал и проигрывает его
/// на текущее устройство вывода через эквалайзер и громкость.
final class AppTap {
    let objects: [AudioObjectID]
    let outputUID: String

    private let processor = EQProcessor()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init?(objects: [AudioObjectID], outputUID: String, volume: Float, gains: [Double]) {
        self.objects = objects
        self.outputUID = outputUID
        processor.gain = volume

        let desc = CATapDescription(stereoMixdownOfProcesses: objects)
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true

        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return nil }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Hushel-\(desc.uuid.uuidString)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: desc.uuid.uuidString
                ]
            ]
        ]

        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggID) == noErr else {
            stop()
            return nil
        }

        processor.configure(sampleRate: Self.nominalRate(of: aggID), gains: gains)

        // Колбэк держит только processor, а не сам AppTap:
        // так AppTap никогда не освобождается внутри аудио-потока.
        let processor = self.processor
        let queue = DispatchQueue(label: "hushel.io", qos: .userInteractive)
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) { _, inData, _, outData, _ in
            processor.process(
                input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData)),
                output: UnsafeMutableAudioBufferListPointer(outData)
            )
        }

        guard status == noErr, let procID, AudioDeviceStart(aggID, procID) == noErr else {
            stop()
            return nil
        }
    }

    deinit { stop() }

    func update(volume: Float, gains: [Double]) {
        processor.gain = volume
        processor.update(gains: gains)
    }

    private static func nominalRate(of device: AudioObjectID) -> Double {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate)
        return status == noErr && rate > 0 ? rate : 48000
    }

    private func stop() {
        if let procID, aggID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggID, procID)
            AudioDeviceDestroyIOProcID(aggID, procID)
        }
        procID = nil
        if aggID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggID)
            aggID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
