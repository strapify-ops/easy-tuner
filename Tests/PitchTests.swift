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
                XCTAssertLessThan(abs(centsOff(f!, s.frequency)), 2, "\(s.name)\(s.octave) at \(rate): got \(f!)")
            }
        }
    }

    func testDetuneDirection() {
        let low = YIN.pitch(pluck(108), sampleRate: 48000)!
        XCTAssertLessThan(centsOff(low, 110), -20)
        let high = YIN.pitch(pluck(112), sampleRate: 48000)!
        XCTAssertGreaterThan(centsOff(high, 110), 20)
    }

    func testNearestString() {
        XCTAssertEqual(GuitarString.nearest(to: 80).number, 6)
        XCTAssertEqual(GuitarString.nearest(to: 150).number, 4)
        XCTAssertEqual(GuitarString.nearest(to: 240).number, 2)
        XCTAssertEqual(GuitarString.nearest(to: 335).number, 1)
    }

    func testDropD() {
        let low = Tuning.dropD.strings[0]
        XCTAssertEqual(low.name, "D")
        let f = YIN.pitch(pluck(low.frequency), sampleRate: 48000)!
        XCTAssertLessThan(abs(centsOff(f, 73.42)), 2, "got \(f)")
        XCTAssertEqual(GuitarString.nearest(to: 74, in: .dropD).name, "D")
        XCTAssertEqual(GuitarString.nearest(to: 74, in: .dropD).number, 6)
        XCTAssertEqual(GuitarString.nearest(to: 110, in: .dropD).number, 5)
        XCTAssertEqual(Tuning.dropD.notes, "D A D G B E")
    }

    func testUkuleleAndBanjo() {
        XCTAssertEqual(Tuning.ukulele.notes, "G C E A")
        XCTAssertEqual(Tuning.banjo.notes, "G D G B D")
        for t in [Tuning.ukulele, .banjo] {
            for s in t.strings {
                let f = YIN.pitch(pluck(s.frequency), sampleRate: 48000)!
                XCTAssertLessThan(abs(centsOff(f, s.frequency)), 2, "\(t) \(s.name): got \(f)")
                XCTAssertEqual(GuitarString.nearest(to: s.frequency * 1.005, in: t).number, s.number)
            }
        }
        XCTAssertEqual(HeadstockStyle.peg(for: 5, tuning: .banjo, style: .threeAndThree).slot, -1)
        XCTAssertTrue(HeadstockStyle.peg(for: 4, tuning: .ukulele, style: .sixInLine).left)
        XCTAssertFalse(HeadstockStyle.peg(for: 1, tuning: .ukulele, style: .sixInLine).left)
    }

    func testSilenceGivesNothing() {
        let noise = (0..<4096).map { _ in Float.random(in: -0.01...0.01) }
        XCTAssertNil(YIN.pitch(noise, sampleRate: 48000))
    }
}
