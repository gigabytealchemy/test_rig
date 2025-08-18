import Analyzers
import SwiftUI

@main
struct TestRigApp: App {
    @StateObject private var coordinator =
        Coordinator(registry: DefaultAlgorithmRegistry())

    var body: some Scene {
        WindowGroup("TestRig") {
            ZStack(alignment: .top) {
                HSplitView {
                    EditorPane()
                        .environmentObject(coordinator)
                        .frame(minWidth: 350)
                    ResultsDashboard()
                        .environmentObject(coordinator)
                        .frame(minWidth: 350)
                }
                if let err = coordinator.lastError {
                    Text(err)
                        .font(.caption)
                        .padding(8)
                        .background(.red.opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.5)))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
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
