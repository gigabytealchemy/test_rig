import CoreTypes
import SwiftUI

struct ResultsDashboard: View {
    @EnvironmentObject var coordinator: Coordinator

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(AlgorithmCategory.allCases, id: \.self) { category in
                    if let items = coordinator.resultsByCategory[category], !items.isEmpty {
                        Section(header: Text(category.rawValue.capitalized)
                            .font(.headline)) {
                            ForEach(items) { output in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(output.name)
                                            .font(.subheadline).bold()
                                        Spacer()
                                        Text("\(output.durationMS) ms")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Text(output.result)
                                        .font(.body)
                                        .textSelection(.enabled)
                                }
                                .padding(10)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.bottom, 6)
                    }
                }
                if coordinator.resultsByCategory.values.allSatisfy(\.isEmpty) {
                    Text("No results yet. Press \"Run All\".")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}
