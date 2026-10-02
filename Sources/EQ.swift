import CoreAudio
import Foundation

/// 5-полосный эквалайзер (peaking-фильтры) + громкость.
/// Работает прямо в аудио-колбэке, поэтому внутри только простая арифметика.
final class EQProcessor {
    static let frequencies: [Double] = [60, 250, 1000, 4000, 12000]
    static var bandCount: Int { frequencies.count }

    private static let slots = 64      // каналы × буферы
    private static let q = 1.0

    var gain: Float = 1

    private var sampleRate: Double = 48000
    private var lastGains: [Double] = []
    private var hasEQ = false
    private let coeffs: UnsafeMutablePointer<Double>   // на полосу: b0 b1 b2 a1 a2
    private let state: UnsafeMutablePointer<Double>    // на полосу: z1 z2

    init() {
        let n = Self.frequencies.count
        coeffs = .allocate(capacity: n * 5)
        coeffs.initialize(repeating: 0, count: n * 5)
        state = .allocate(capacity: Self.slots * n * 2)
        state.initialize(repeating: 0, count: Self.slots * n * 2)
        for b in 0..<n { coeffs[b * 5] = 1 }   // сквозной фильтр
    }

    deinit {
        coeffs.deallocate()
        state.deallocate()
    }

    func configure(sampleRate: Double, gains: [Double]) {
        self.sampleRate = sampleRate
        lastGains = []
        update(gains: gains)
    }

    /// gains: усиление каждой полосы в дБ.
    func update(gains: [Double]) {
        guard gains.count == Self.frequencies.count, gains != lastGains else { return }
        lastGains = gains

        for (b, db) in gains.enumerated() {
            let k = b * 5
            if abs(db) < 0.05 {
                coeffs[k] = 1; coeffs[k + 1] = 0; coeffs[k + 2] = 0; coeffs[k + 3] = 0; coeffs[k + 4] = 0
                continue
            }
            let A = pow(10, db / 40)
            let w0 = 2 * Double.pi * Self.frequencies[b] / sampleRate
            let alpha = sin(w0) / (2 * Self.q)
            let c = cos(w0)
            let a0 = 1 + alpha / A
            coeffs[k]     = (1 + alpha * A) / a0
            coeffs[k + 1] = (-2 * c) / a0
            coeffs[k + 2] = (1 - alpha * A) / a0
            coeffs[k + 3] = (-2 * c) / a0
            coeffs[k + 4] = (1 - alpha / A) / a0
        }
        hasEQ = gains.contains { abs($0) >= 0.05 }
    }

    func process(input: UnsafeMutableAudioBufferListPointer, output: UnsafeMutableAudioBufferListPointer) {
        let g = gain
        let eq = hasEQ
        let bands = Self.frequencies.count

        for i in 0..<min(input.count, output.count) {
            guard let src = input[i].mData, let dst = output[i].mData else { continue }
            let channels = max(1, Int(input[i].mNumberChannels))
            let bytes = Int(min(input[i].mDataByteSize, output[i].mDataByteSize))
            let frames = bytes / MemoryLayout<Float>.size / channels
            let s = src.assumingMemoryBound(to: Float.self)
            let d = dst.assumingMemoryBound(to: Float.self)

            for f in 0..<frames {
                for c in 0..<channels {
                    let idx = f * channels + c
                    var x = Double(s[idx])

                    if eq {
                        let slot = ((i * 8 + c) % Self.slots) * bands * 2
                        for b in 0..<bands {
                            let k = b * 5
                            let st = slot + b * 2
                            let y = coeffs[k] * x + state[st]
                            state[st] = coeffs[k + 1] * x - coeffs[k + 3] * y + state[st + 1]
                            state[st + 1] = coeffs[k + 2] * x - coeffs[k + 4] * y
                            x = y
                        }
                    }
                    d[idx] = min(max(Float(x) * g, -1), 1)
                }
            }
        }
    }
}
