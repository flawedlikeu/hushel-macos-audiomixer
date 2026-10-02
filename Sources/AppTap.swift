import CoreAudio
import Foundation

/// Перехватывает звук набора процессов, глушит оригинал и
/// проигрывает его на текущее устройство вывода с коэффициентом `volume`.
final class AppTap {
    let objects: [AudioObjectID]
    let outputUID: String
    var volume: Float

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init?(objects: [AudioObjectID], outputUID: String, volume: Float) {
        self.objects = objects
        self.outputUID = outputUID
        self.volume = volume

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

        let queue = DispatchQueue(label: "volumemixer.io", qos: .userInteractive)
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) {
            [weak self] _, inData, _, outData, _ in
            guard let self else { return }
            let gain = self.volume
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            let output = UnsafeMutableAudioBufferListPointer(outData)

            for i in 0..<min(input.count, output.count) {
                guard let src = input[i].mData, let dst = output[i].mData else { continue }
                let bytes = Int(min(input[i].mDataByteSize, output[i].mDataByteSize))
                let count = bytes / MemoryLayout<Float>.size
                let s = src.assumingMemoryBound(to: Float.self)
                let d = dst.assumingMemoryBound(to: Float.self)
                for j in 0..<count {
                    d[j] = s[j] * gain
                }
            }
        }

        guard status == noErr, let procID, AudioDeviceStart(aggID, procID) == noErr else {
            stop()
            return nil
        }
    }

    deinit { stop() }

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
