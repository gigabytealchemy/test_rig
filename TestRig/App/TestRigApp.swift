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
                Button("Open") {
                    FileOpenSave.presentOpen { loaded in
                        coordinator.text = loaded
                        coordinator.selectionRange = nil
                    }
                }

                Button("Save") {
                    FileOpenSave.presentSave(text: coordinator.text)
                }

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
