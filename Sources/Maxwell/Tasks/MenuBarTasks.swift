import SwiftUI

/// Les Tâches d'Aujourd'hui en haut du menu, avec un champ pour en ajouter une.
struct MenuBarTasks: View {
    @EnvironmentObject private var store: TaskStore
    @State private var justClosed: Set<TaskID> = []
    private let limit = 7

    var body: some View {
        let tasks = store.tasks(in: .today, keeping: justClosed)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tâches du jour")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                let inbox = store.count(of: .inbox)
                if inbox > 0 {
                    Button { Windows.showTasks(.inbox) } label: {
                        Label("\(inbox) à ranger", systemImage: "tray")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Ouvrir la Boîte de réception")
                }
            }

            NewTaskField(list: .today, placeholder: "Nouvelle tâche pour aujourd'hui")
                .padding(.top, 10)

            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tasks.prefix(limit)) { task in
                        TaskRow(task: task, hoverHighlight: true, compact: true, onToggle: toggle)
                            .contextMenu { TaskContextMenu(task: task) }
                    }
                }
                .padding(.top, 8)
                if tasks.count > limit {
                    Button { Windows.showTasks(.today) } label: {
                        Text("\(tasks.count - limit) autre\(tasks.count - limit > 1 ? "s" : "")…")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 25)
                    .padding(.top, 2)
                }
            }
        }
        .overlay(alignment: .bottom) { DeletedBanner().offset(y: 8) }
        .onDisappear {
            justClosed = []
            store.forgetDeletion()
        }
    }

    private func toggle(_ task: TaskItem) {
        if task.isOpen {
            store.close(task.id)
            justClosed.insert(task.id)
        } else {
            store.reopen(task.id)
            justClosed.remove(task.id)
        }
    }
}
