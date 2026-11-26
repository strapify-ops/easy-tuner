import Accelerate
import Foundation

/// One guitar string in standard tuning.
struct GuitarString: Identifiable, Hashable {
    let number: Int        // 6 = thickest (low E) ... 1 = thinnest (high E)
    let name: String       // "E", "A", ...
    let octave: Int
    let frequency: Double
    let nickname: String   // plain words for beginners

    var id: Int { number }

    static let standard: [GuitarString] = [
        GuitarString(number: 6, name: "E", octave: 2, frequency: 82.41,  nickname: "Thickest string"),
        GuitarString(number: 5, name: "A", octave: 2, frequency: 110.00, nickname: "5th string"),
        GuitarString(number: 4, name: "D", octave: 3, frequency: 146.83, nickname: "4th string"),
        GuitarString(number: 3, name: "G", octave: 3, frequency: 196.00, nickname: "3rd string"),
        GuitarString(number: 2, name: "B", octave: 3, frequency: 246.94, nickname: "2nd string"),
        GuitarString(number: 1, name: "E", octave: 4, frequency: 329.63, nickname: "Thinnest string"),
    ]

    /// The string whose note is closest to `frequency` (in musical distance, not Hz).
    static func nearest(to frequency: Double, in tuning: Tuning = .standard) -> GuitarString {
        tuning.strings.min { abs(centsOff(frequency, $0.frequency)) < abs(centsOff(frequency, $1.frequency)) }!
    }
}

/// The instruments and tunings a beginner can pick from.
enum Tuning: String, CaseIterable, Identifiable {
    case standard = "Guitar: Standard"
    case dropD = "Guitar: Drop D"
    case ukulele = "Ukulele"
    case banjo = "Banjo (5-string, open G)"

    var id: String { rawValue }

    var isGuitar: Bool { self == .standard || self == .dropD }

    /// Short name for the top bar.
    var shortName: String {
        switch self {
        case .standard: return "Guitar"
        case .dropD: return "Drop D"
        case .ukulele: return "Ukulele"
        case .banjo: return "Banjo"
        }
    }

    var strings: [GuitarString] {
        switch self {
        case .standard: return GuitarString.standard
        case .dropD:
            return [GuitarString(number: 6, name: "D", octave: 2, frequency: 73.42, nickname: "Thickest string")]
                + GuitarString.standard.dropFirst()
        case .ukulele:   // G C E A, re-entrant (the G is high)
            return [
                GuitarString(number: 4, name: "G", octave: 4, frequency: 392.00, nickname: "Top string, nearest your face"),
                GuitarString(number: 3, name: "C", octave: 4, frequency: 261.63, nickname: "3rd string (the lowest note)"),
                GuitarString(number: 2, name: "E", octave: 4, frequency: 329.63, nickname: "2nd string"),
                GuitarString(number: 1, name: "A", octave: 4, frequency: 440.00, nickname: "Bottom string"),
            ]
        case .banjo:     // g D G B D
            return [
                GuitarString(number: 5, name: "G", octave: 4, frequency: 392.00, nickname: "Short 5th string (peg on the neck)"),
                GuitarString(number: 4, name: "D", octave: 3, frequency: 146.83, nickname: "4th string"),
                GuitarString(number: 3, name: "G", octave: 3, frequency: 196.00, nickname: "3rd string"),
                GuitarString(number: 2, name: "B", octave: 3, frequency: 246.94, nickname: "2nd string"),
                GuitarString(number: 1, name: "D", octave: 4, frequency: 293.66, nickname: "Bottom string"),
            ]
        }
    }

    var notes: String { strings.map(\.name).joined(separator: " ") }
}

/// How far `f` is from `target`, in cents (100 cents = one semitone). Negative = too low.
func centsOff(_ f: Double, _ target: Double) -> Double { 1200 * log2(f / target) }

/// YIN pitch detector (de Cheveigné & Kawahara, 2002), tuned for guitar.
enum YIN {
    static func pitch(_ x: [Float], sampleRate: Double,
                      minFrequency: Double = 60, maxFrequency: Double = 1000,
                      threshold: Float = 0.15) -> Double? {
        let maxTau = min(Int(sampleRate / minFrequency), x.count / 2)
        let minTau = max(2, Int(sampleRate / maxFrequency))
        guard maxTau > minTau + 2 else { return nil }
        let window = x.count - maxTau

        // Difference function d(tau)
        var d = [Float](repeating: 0, count: maxTau + 1)
        x.withUnsafeBufferPointer { p in
            let base = p.baseAddress!
            for tau in 1...maxTau {
                var s: Float = 0
                vDSP_distancesq(base, 1, base + tau, 1, &s, vDSP_Length(window))
                d[tau] = s
            }
        }

        // Cumulative mean normalised difference
        var cmnd = [Float](repeating: 1, count: maxTau + 1)
        var running: Float = 0
        for tau in 1...maxTau {
            running += d[tau]
            cmnd[tau] = running > 0 ? d[tau] * Float(tau) / running : 1
        }

        // First dip under the threshold, then walk to its bottom
        var tau = minTau
        var found = -1
        while tau < maxTau {
            if cmnd[tau] < threshold {
                while tau + 1 < maxTau && cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                found = tau
                break
            }
            tau += 1
        }
        guard found > 0 else { return nil }

        // Parabolic interpolation for sub-sample accuracy
        var better = Double(found)
        if found > 1 && found < maxTau {
            let s0 = cmnd[found - 1], s1 = cmnd[found], s2 = cmnd[found + 1]
            let den = s0 + s2 - 2 * s1
            if den != 0 { better += Double((s0 - s2) / (2 * den)) }
        }
        return sampleRate / better
    }

    static func rms(_ x: [Float]) -> Float {
        var r: Float = 0
        vDSP_rmsqv(x, 1, &r, vDSP_Length(x.count))
        return r
    }
}
