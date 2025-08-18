import SwiftUI

struct EditorPane: View {
    @EnvironmentObject var coordinator: Coordinator

    var body: some View {
        VStack(spacing: 8) {
            SelectableTextEditor(text: $coordinator.text,
                                 selection: Binding(
                                     get: { coordinator.selectionRange },
                                     set: { coordinator.selectionRange = $0 }
                                 ))
                                 .overlay(alignment: .bottomTrailing) {
                                     if let range = coordinator.selectionRange {
                                         Text("Selected: \(coordinator.text[range].count) chars")
                                             .font(.caption2)
                                             .padding(4)
                                             .background(.thinMaterial)
                                             .clipShape(RoundedRectangle(cornerRadius: 4))
                                     }
                                 }
        }
        .padding()
    }
}
