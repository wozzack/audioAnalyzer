import SwiftUI

@main
struct MyApp: App {
    @StateObject private var micManager = MicManager(
        outputURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recording.caf")
    )
    
    var body: some Scene {
        WindowGroup {
            ContentView(micManager: micManager)
        }
    }
}
