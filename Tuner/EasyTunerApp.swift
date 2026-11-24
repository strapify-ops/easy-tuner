import SwiftUI

@main
struct EasyTunerApp: App {
    @StateObject private var tuner = TunerEngine()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tuner)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true   // screen stays on while tuning
                    tuner.start()
                }
                .onChange(of: phase) { _, p in
                    if p == .active { tuner.start() } else if p == .background { tuner.stop() }
                }
        }
    }
}
