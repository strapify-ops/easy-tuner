import XCTest
@testable import EasyTuner

final class PitchTests: XCTestCase {
    /// A string-like test signal: fundamental plus strong overtones and a little noise.
    func pluck(_ f: Double, rate: Double = 48000, n: Int = 4096, fundamental: Double = 0.4) -> [Float] {
        (0..<n).map { i in
            let t = Double(i) / rate
            let p = 2 * Double.pi * f * t
            let v = fundamental * sin(p) + 0.5 * sin(2 * p) + 0.3 * sin(3 * p) + 0.15 * sin(4 * p)
            return Float(v * 0.3 + Double.random(in: -0.005...0.005))
        }
    }

    func testEveryStringIsFoundWithinTwoCents() {
        for s in GuitarString.standard {
            for rate in [44100.0, 48000.0] {
                let f = YIN.pitch(pluck(s.frequency, rate: rate), sampleRate: rate)
                XCTAssertNotNil(f, "\(s.name)\(s.octave) at \(rate)")
                XCTAssertLessThan(abs(cents(f!, s.frequency)), 2, "\(s.name)\(s.octave) at \(rate): got \(f!)")
            }
        }
    }

    func testDetuneDirection() {
        let low = YIN.pitch(pluck(108), sampleRate: 48000)!
        XCTAssertLessThan(cents(low, 110), -20)
        let high = YIN.pitch(pluck(112), sampleRate: 48000)!
        XCTAssertGreaterThan(cents(high, 110), 20)
    }

    func testNearestString() {
        XCTAssertEqual(GuitarString.nearest(to: 80).number, 6)
        XCTAssertEqual(GuitarString.nearest(to: 150).number, 4)
        XCTAssertEqual(GuitarString.nearest(to: 240).number, 2)
        XCTAssertEqual(GuitarString.nearest(to: 335).number, 1)
    }

    func testSilenceGivesNothing() {
        let noise = (0..<4096).map { _ in Float.random(in: -0.01...0.01) }
        XCTAssertNil(YIN.pitch(noise, sampleRate: 48000))
    }
}
