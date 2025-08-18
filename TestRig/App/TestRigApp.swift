import Analyzers
import SwiftUI

@main
struct TestRigApp: App {
    @StateObject private var coordinator =
        Coordinator(registry: DefaultAlgorithmRegistry())

    var body: some Scene {
        WindowGroup("TestRig") {
            HSplitView {
                EditorPane()
                    .environmentObject(coordinator)
                    .frame(minWidth: 350)
                ResultsDashboard()
                    .environmentObject(coordinator)
                    .frame(minWidth: 350)
            }
            .toolbar {
                Button("Run All") {
                    coordinator.runAll()
                }
                .disabled(coordinator.isRunning || coordinator.text.isEmpty)

                Button("Cancel") {
                    coordinator.cancel()
                }
                .disabled(!coordinator.isRunning)
            }
        }
    }
}
