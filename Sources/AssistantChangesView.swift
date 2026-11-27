import SwiftUI

struct AssistantChangesView: View {
    @EnvironmentObject var model: AppModel
    let game: UUID
    @State private var failure: String? = nil

    var body: some View {
        let _ = model.assistantChangeRevision
        let rows = AssistantChangeLog(url: model.assistantChangeLogURL(game)).rows
        if !rows.isEmpty, let g = model.game(game) {
            Section {
                ForEach(rows, id: \.first!.id) { row in
                    let change = row[0]
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.map { model.assistantChangeSummary($0, game: g) }.joined(separator: "; "))
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Text(change.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(change.date, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Undo") { undo { try model.undoAssistantChange(change.id) } }
                    }
                }
                HStack {
                    Spacer()
                    Button("Undo All") { undo { try model.undoAllAssistantChanges(game: game) } }
                }
            } header: {
                Text("Changes by the assistant")
            } footer: {
                Text("Undo puts back the setting or file as it was. One changed since the assistant changed it is left as it is.")
            }
            .alert("Some changes weren't undone", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private func undo(_ action: () throws -> Void) {
        do { try action() } catch { failure = (error as? AssistantFailure)?.message ?? error.localizedDescription }
    }
}
