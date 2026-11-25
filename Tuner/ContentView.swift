import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tuner: TunerEngine
    @State private var showHelp = false

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                if tuner.mic == .denied {
                    MicDeniedView()
                } else {
                    NoteCircle()
                    Gauge(cents: tuner.cents, active: tuner.hearing, inTune: tuner.isInTune)
                        .frame(height: 150)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                    Guidance()
                        .padding(.top, 4)
                }
                Spacer(minLength: 8)
                StringPicker()
                    .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showHelp) { HelpView() }
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
                Picker("Tuning", selection: $tuner.tuning) {
                    ForEach(Tuning.allCases) { t in
                        Text("\(t.rawValue)  (\(t.notes))").tag(t)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(tuner.tuning.rawValue).font(.headline)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.15)))
            }
            .accessibilityLabel("Tuning: \(tuner.tuning.rawValue)")
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
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                Text("String \(tuner.target.number)")
                    .font(.headline).opacity(0.7)
            }
            .foregroundStyle(.white)
            if tuner.isInTune {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green, .white)
                    .offset(x: 70, y: -70)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 210, height: 210)
        .animation(.spring(duration: 0.3), value: tuner.isInTune)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Needle gauge

struct Gauge: View {
    let cents: Double
    let active: Bool
    let inTune: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let center = CGPoint(x: w / 2, y: h)
            let radius = min(w / 2, h) - 6
            ZStack {
                // Arc: red edges, green middle
                ForEach(-10...10, id: \.self) { i in
                    let angle = Angle.degrees(Double(i) * 6)   // -60...60 degrees
                    let big = i % 5 == 0
                    Capsule()
                        .fill(i == 0 ? Color.green : (abs(i) <= 1 ? Color.green.opacity(0.7) : Color.white.opacity(0.35)))
                        .frame(width: big ? 4 : 2, height: big ? 22 : 12)
                        .offset(y: -radius + (big ? 11 : 6))
                        .rotationEffect(angle)
                        .position(center)
                }
                Text("too low").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                    .position(x: w * 0.12, y: h - 8)
                Text("too high").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                    .position(x: w * 0.88, y: h - 8)

                // Needle
                Capsule()
                    .fill(active ? (inTune ? Color.green : Color.white) : Color.gray.opacity(0.5))
                    .frame(width: 5, height: radius)
                    .offset(y: -radius / 2)
                    .rotationEffect(.degrees(active ? cents / 50 * 60 : 0))
                    .position(center)
                Circle().fill(.white).frame(width: 16, height: 16).position(center)
            }
        }
        .accessibilityLabel(active ? "\(Int(cents.rounded())) cents" : "Waiting for a note")
    }
}

// MARK: - Plain-words instruction

struct Guidance: View {
    @EnvironmentObject var tuner: TunerEngine

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
                line("arrow.up.circle.fill", "Too low: tighten", "Turn the peg slowly to raise the note", .orange)
            } else {
                line("arrow.down.circle.fill", "Too high: loosen", "Turn the peg slowly to lower the note", .orange)
            }
        }
        .frame(height: 90)
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.2), value: tuner.isInTune)
    }

    private var allTunedText: String {
        tuner.tuned.count == 6 ? "All 6 strings are in tune. Time to play!" : "Move on to the next string"
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
