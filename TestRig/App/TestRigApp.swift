import Analyzers
import CoreTypes
import SwiftUI

@main
struct TestRigApp: App {
    var body: some Scene {
        WindowGroup("ALR Test Rig") {
            ContentView()
                .frame(minWidth: 700, minHeight: 480)
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("ALR Test Rig")
                .font(.largeTitle)
            Text("Step 1: Project scaffold ready.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
