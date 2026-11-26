import SwiftUI

/// Where the tuning pegs sit. Which way a peg tightens depends on this, so the app asks.
enum HeadstockStyle: String, CaseIterable, Identifiable {
    case threeAndThree = "3 + 3"
    case sixInLine = "6 in a line"

    var id: String { rawValue }
    var label: String { self == .threeAndThree ? "3 + 3 (pegs on both sides)" : "6 in a line (all on one side)" }

    /// Which side of the headstock (front view, headstock pointing up) and how far from the nut (0 = nearest).
    func peg(for string: Int) -> (left: Bool, slot: Int) {
        switch self {
        case .threeAndThree: return string >= 4 ? (true, 6 - string) : (false, string - 1)
        case .sixInLine: return (true, 6 - string)
        }
    }

    /// Strings wrap round the inside of the posts, so, looking at the FRONT of the headstock,
    /// a left-side post tightens anticlockwise and a right-side post clockwise.
    func tightensClockwise(_ string: Int) -> Bool { !peg(for: string).left }

    /// Peg position for any instrument: guitars use the chosen style, ukulele and banjo are 2 + 2.
    /// Banjo's short 5th string has its peg on the neck (slot -1, drawn below the nut on the left).
    static func peg(for string: Int, tuning: Tuning, style: HeadstockStyle) -> (left: Bool, slot: Int) {
        switch tuning {
        case .standard, .dropD: return style.peg(for: string)
        case .ukulele, .banjo:
            if string == 5 { return (true, -1) }
            return string >= 3 ? (true, 4 - string) : (false, string - 1)
        }
    }
}

/// A front-on guitar headstock drawn behind the note, with the peg to turn lit up and a
/// spinning arrow showing which way to turn it.
struct HeadstockView: View {
    let size: CGFloat
    let style: HeadstockStyle
    let tuning: Tuning
    let target: Int          // string number being tuned
    let hearing: Bool
    let cents: Double
    let inTune: Bool

    private var w: CGFloat { size * 2 }
    private var h: CGFloat { size * 1.6 }
    private var sixInLine: Bool { tuning.isGuitar && style == .sixInLine }
    private var bodyLeft: CGFloat { sixInLine ? w * 0.25 : w * 0.27 }
    private var bodyRight: CGFloat { sixInLine ? w * 0.66 : w * 0.73 }
    private var numbers: [Int] { tuning.strings.map(\.number) }
    private func peg(_ n: Int) -> (left: Bool, slot: Int) { HeadstockStyle.peg(for: n, tuning: tuning, style: style) }
    private var nutY: CGFloat { h * 0.95 }

    private func postPoint(_ n: Int) -> CGPoint {
        let p = peg(n)
        let gap: CGFloat = sixInLine ? 0.15 : (tuning.isGuitar ? 0.27 : 0.36)
        let first: CGFloat = sixInLine ? 0.84 : (tuning.isGuitar ? 0.74 : 0.66)
        let y = p.slot < 0 ? nutY - h * 0.02 : h * (first - CGFloat(p.slot) * gap)
        return CGPoint(x: p.left ? bodyLeft + size * 0.12 : bodyRight - size * 0.12, y: y)
    }

    private func buttonPoint(_ n: Int) -> CGPoint {
        let post = postPoint(n)
        let left = peg(n).left
        return CGPoint(x: left ? bodyLeft - size * 0.2 : bodyRight + size * 0.2, y: post.y)
    }

    private func nutPoint(_ n: Int) -> CGPoint {
        let spread = size * (tuning.isGuitar ? 0.62 : 0.5)
        let top = numbers.max() ?? 6, count = CGFloat(max(numbers.count - 1, 1))
        let x = w / 2 - spread / 2 + spread * CGFloat(top - n) / count
        return CGPoint(x: x, y: nutY)
    }

    private var needsTurn: Bool { hearing && !inTune }
    private var turnClockwise: Bool {
        let tight = !peg(target).left
        return cents < 0 ? tight : !tight
    }

    var body: some View {
        ZStack {
            // Headstock body
            Path { p in
                p.addRoundedRect(in: CGRect(x: bodyLeft, y: h * 0.02, width: bodyRight - bodyLeft, height: nutY - h * 0.02),
                                 cornerSize: CGSize(width: size * 0.18, height: size * 0.18))
            }
            .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.22, blue: 0.12), Color(red: 0.22, green: 0.13, blue: 0.07)],
                                 startPoint: .top, endPoint: .bottom))
            // Nut
            Rectangle().fill(Color(white: 0.92))
                .frame(width: bodyRight - bodyLeft - size * 0.1, height: size * 0.04)
                .position(x: w / 2, y: nutY)

            // Strings, pegs
            ForEach(numbers, id: \.self) { n in
                let active = n == target
                Path { p in p.move(to: nutPoint(n)); p.addLine(to: postPoint(n)) }
                    .stroke(active ? Color.white : Color.white.opacity(0.35),
                            lineWidth: active ? 2.5 : CGFloat(7 - n) * 0.25 + 0.6)
                Path { p in p.move(to: postPoint(n)); p.addLine(to: buttonPoint(n)) }
                    .stroke(Color(white: 0.75), lineWidth: size * 0.035)
                Circle().fill(Color(white: 0.85)).frame(width: size * 0.07).position(postPoint(n))
                Capsule()
                    .fill(active ? (inTune && hearing ? Color.green : Color.orange) : Color(white: 0.8))
                    .frame(width: size * 0.15, height: size * 0.1)
                    .position(buttonPoint(n))
                    .shadow(color: active ? .orange.opacity(0.8) : .clear, radius: 8)
            }

            if needsTurn {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Image(systemName: turnClockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                        .font(.system(size: size * 0.24, weight: .heavy))
                        .foregroundStyle(.orange)
                        .rotationEffect(.degrees((t * 140).truncatingRemainder(dividingBy: 360) * (turnClockwise ? 1 : -1)))
                        .position(buttonPoint(target))
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: h)
        .accessibilityHidden(true)
    }
}
