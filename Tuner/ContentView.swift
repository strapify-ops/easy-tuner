import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tuner: TunerEngine
    @AppStorage("headstock") private var headstock: HeadstockStyle = .threeAndThree
    @State private var showHelp = false

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            GeometryReader { geo in
                let wide = geo.size.width > geo.size.height * 1.15   // Duo open, landscape, iPad
                VStack(spacing: 0) {
                    header
                    if tuner.mic == .denied {
                        Spacer()
                        MicDeniedView()
                        Spacer()
                    } else if wide {
                        HStack(spacing: 24) {
                            meter(size: min(geo.size.height * 0.3, 200))
                                .frame(maxWidth: .infinity)
                            VStack {
                                Spacer(minLength: 8)
                                StringPicker()
                                Spacer(minLength: 8)
                            }
                            .frame(maxWidth: 460)
                        }
                        .padding(.horizontal, 12)
                    } else {
                        Spacer(minLength: 8)
                        meter(size: min(geo.size.width * 0.46, geo.size.height * 0.2, 210))
                        Spacer(minLength: 8)
                        StringPicker()
                            .padding(.bottom, 12)
                    }
                }
                .frame(maxWidth: wide ? .infinity : 600)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showHelp) { HelpView() }
    }

    private func meter(size: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                HeadstockView(size: size, style: headstock, tuning: tuner.tuning, target: tuner.target.number,
                              hearing: tuner.hearing, cents: tuner.cents, inTune: tuner.isInTune)
                NoteCircle(size: size * 0.72)
                    .offset(y: -size * 0.12)
            }
            Gauge(cents: tuner.cents, active: tuner.hearing, inTune: tuner.isInTune)
                .frame(maxWidth: 420)
                .frame(height: size * 0.7)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            Guidance()
                .padding(.top, 4)
        }
    }

    private var background: some View {
        LinearGradient(colors: tuner.isInTune
                       ? [Color(red: 0.05, green: 0.25, blue: 0.15), .black]
                       : [Color(red: 0.12, green: 0.12, blue: 0.16), .black],
                       startPoint: .top, endPoint: .bottom)
            .animation(.easeInOut(duration: 0.3), value: tuner.isInTune)
    }

    private var header: some View {
        HStack {
            Menu {
                Picker("Instrument", selection: $tuner.tuning) {
                    ForEach(Tuning.allCases) { t in
                        Text("\(t.rawValue)  (\(t.notes))").tag(t)
                    }
                }
                if tuner.tuning.isGuitar {
                    Picker("My guitar's pegs", selection: $headstock) {
                        ForEach(HeadstockStyle.allCases) { h in Text(h.label).tag(h) }
                    }
                    .pickerStyle(.menu)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(tuner.tuning.shortName).font(.headline)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.15)))
            }
            .accessibilityLabel("Instrument: \(tuner.tuning.rawValue)")
            Spacer()
            Button { showHelp = true } label: {
                Label("How to tune", systemImage: "questionmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.white)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Big note in a circle

struct NoteCircle: View {
    @EnvironmentObject var tuner: TunerEngine
    var size: CGFloat = 210

    var color: Color {
        guard tuner.hearing else { return .gray }
        if tuner.isInTune { return .green }
        return abs(tuner.cents) < 20 ? .yellow : .orange
    }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.18))
            Circle().stroke(color, lineWidth: 6)
            VStack(spacing: 0) {
                Text(tuner.target.name)
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                Text("String \(tuner.target.number)")
                    .font(.headline).opacity(0.7)
            }
            .foregroundStyle(.white)
            if tuner.isInTune {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green, .white)
                    .offset(x: size * 0.33, y: -size * 0.33)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.3), value: tuner.isInTune)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Needle gauge

struct Gauge: View {
    let cents: Double
    let active: Bool
    let inTune: Bool

    /// Square-root scale: the middle of the dial is stretched so a 1-2 cent nudge moves the
    /// needle visibly, while +-50 cents still fits at the edges.
    static func angle(_ c: Double) -> Double {
        let x = max(-50, min(50, c))
        return (x < 0 ? -1 : 1) * (abs(x) / 50).squareRoot() * 60
    }

    private let ticks: [Double] = [-50, -30, -20, -10, -5, -2, 0, 2, 5, 10, 20, 30, 50]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let center = CGPoint(x: w / 2, y: h)
            let radius = min(w / 2, h) - 6
            ZStack {
                Path { p in
                    p.addArc(center: center, radius: radius - 8,
                             startAngle: .degrees(-90 + Self.angle(-5)), endAngle: .degrees(-90 + Self.angle(5)), clockwise: false)
                }
                .stroke(Color.green.opacity(0.35), lineWidth: 16)

                ForEach(ticks, id: \.self) { t in
                    let big = t == 0 || abs(t) == 10 || abs(t) == 50
                    Capsule()
                        .fill(t == 0 ? Color.green : Color.white.opacity(abs(t) <= 5 ? 0.8 : 0.4))
                        .frame(width: big ? 4 : 2, height: big ? 22 : 12)
                        .offset(y: -radius + (big ? 11 : 6))
                        .rotationEffect(.degrees(Self.angle(t)))
                        .position(center)
                }
                Text("too low").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                    .position(x: w * 0.1, y: h - 8)
                Text("too high").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                    .position(x: w * 0.9, y: h - 8)

                Capsule()
                    .fill(active ? (inTune ? Color.green : Color.white) : Color.gray.opacity(0.5))
                    .frame(width: 5, height: radius)
                    .offset(y: -radius / 2)
                    .rotationEffect(.degrees(active ? Self.angle(cents) : 0))
                    .position(center)
                Circle().fill(.white).frame(width: 16, height: 16).position(center)

                if active {
                    Text(String(format: "%+.0f cents", cents.rounded()))
                        .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(inTune ? .green : .white.opacity(0.85))
                        .position(x: w / 2, y: h - radius * 0.42)
                }
            }
        }
        .accessibilityLabel(active ? "\(Int(cents.rounded())) cents" : "Waiting for a note")
    }
}

// MARK: - Plain-words instruction

struct Guidance: View {
    @EnvironmentObject var tuner: TunerEngine
    @AppStorage("headstock") private var headstock: HeadstockStyle = .threeAndThree

    /// Strings wrap round the inside of each post, so seen from the front a left-side peg
    /// tightens anticlockwise and a right-side peg clockwise.
    private func turnText(tighten: Bool) -> String {
        let left = HeadstockStyle.peg(for: tuner.target.number, tuning: tuner.tuning, style: headstock).left
        let cw = left != tighten
        return "Turn the orange peg \(cw ? "clockwise \u{21BB}" : "anticlockwise \u{21BA}") (looking at the front), a little at a time"
    }

    var body: some View {
        VStack(spacing: 6) {
            if tuner.isPlayingTone {
                line("speaker.wave.2.fill", "Listen to the note...", "Then pluck your \(tuner.target.nickname.lowercased())", .white)
            } else if !tuner.hearing {
                line("hand.point.up.left.fill",
                     tuner.lockedString == nil ? "Pluck one string" : "Pluck string \(tuner.target.number) (\(tuner.target.name))",
                     "Let it ring. Hold the phone near the guitar.", .white)
            } else if tuner.isInTune {
                line("checkmark.seal.fill", "Perfect!", allTunedText, .green)
            } else if tuner.cents < 0 {
                line("arrow.up.circle.fill", "Too low: tighten", turnText(tighten: true), .orange)
            } else {
                line("arrow.down.circle.fill", "Too high: loosen", turnText(tighten: false), .orange)
            }
        }
        .frame(height: 104)
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.2), value: tuner.isInTune)
    }

    private var allTunedText: String {
        tuner.tuned.count == tuner.tuning.strings.count ? "All \(tuner.tuning.strings.count) strings are in tune. Time to play!" : "Move on to the next string"
    }

    private func line(_ icon: String, _ title: String, _ detail: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(detail).font(.body).foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - String buttons

struct StringPicker: View {
    @EnvironmentObject var tuner: TunerEngine

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(tuner.lockedString == nil ? "Auto: I'll find the string for you" : "Tap a string to hear it")
                    .font(.footnote).foregroundStyle(.white.opacity(0.65))
                Spacer()
                if tuner.lockedString != nil {
                    Button("Auto") { tuner.select(nil) }
                        .font(.footnote.weight(.bold)).tint(.white)
                }
                if !tuner.tuned.isEmpty {
                    Button("Start over") { tuner.resetProgress() }
                        .font(.footnote.weight(.bold)).tint(.white)
                }
            }
            .padding(.horizontal, 20)

            HStack(spacing: 8) {
                ForEach(tuner.tuning.strings) { s in
                    Button { tuner.select(s) } label: { chip(s) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("String \(s.number), \(s.name). \(tuner.tuned.contains(s.number) ? "Tuned" : "")")
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func chip(_ s: GuitarString) -> some View {
        let selected = tuner.target == s && (tuner.hearing || tuner.lockedString == s)
        let done = tuner.tuned.contains(s.number)
        return VStack(spacing: 2) {
            Text(s.name).font(.system(size: 26, weight: .bold, design: .rounded))
            Text("\(s.number)").font(.caption2).opacity(0.7)
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.caption).foregroundStyle(done ? .green : .white.opacity(0.3))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(selected ? Color.white.opacity(0.25) : Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(tuner.lockedString == s ? Color.white : .clear, lineWidth: 2))
    }
}

// MARK: - Help + mic denied

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Tuning in 4 steps") {
                    step(1, "Find a quiet spot", "Hold your phone close to the guitar.")
                    step(2, "Pluck one string", "Start with the thickest one (string 6, low E). Let it ring.")
                    step(3, "Follow the arrow", "Too low? Tighten the peg. Too high? Loosen it. Small turns!")
                    step(4, "Wait for green", "When it says Perfect, move to the next string.")
                }
                Section("Good to know") {
                    Text("String 6 is the thickest string, nearest your face when you hold the guitar. String 1 is the thinnest.")
                    Text("Ukulele and banjo: pick them from the menu at the top left. The app shows each string's note and which peg to turn.")
                    Text("The turn arrow assumes the usual stringing (strings wrap round the inside of each post). For a guitar, pick 3 + 3 pegs or 6 in a line from the menu.")
                    Text("Not sure which way to turn? Turn a tiny bit and pluck again. If the needle moves the wrong way, turn the other way.")
                    Text("Drop D: only the thickest string changes. Tune it down from E to D (a little lower) for a heavier sound. Pick it from the menu at the top left.")
                    Text("Tap a string at the bottom to hear what it should sound like.")
                    Text("Way too high? Loosen a lot first, then tune up to the note. Tuning up is more stable than tuning down.")
                }
            }
            .navigationTitle("How to tune")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.title2.bold()).frame(width: 36, height: 36)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MicDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.fill").font(.system(size: 60)).foregroundStyle(.orange)
            Text("Easy Tuner needs the microphone").font(.title3.bold()).foregroundStyle(.white)
            Text("It listens to your guitar to tell you if it is in tune. Nothing is recorded.")
                .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
