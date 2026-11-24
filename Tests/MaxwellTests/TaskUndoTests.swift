import Foundation
import Testing
@testable import Maxwell

@MainActor
@Suite("Annuler la dernière action")
final class TaskUndoTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("TaskUndoTests-\(UUID().uuidString).sqlite")
    private let store: TaskStore
    private let navigation = TaskNavigation()

    init() throws {
        store = TaskStore(db: try Database(url: url))
    }

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func titles(_ list: TaskList) -> [String] { store.tasks(in: list).map(\.title) }

    @Test func aDeletedTaskComesBackAsItWas() {
        let task = store.add(text: "Relancer Paul demain #Ventes !")!
        store.delete(task.id)
        #expect(store.undo()?.taskID == task.id)
        #expect(store.task(task.id) == task)
        #expect(store.lastDeleted == nil)
    }

    @Test func aTickedTaskIsOpenAgain() {
        let task = store.add(text: "Courses", in: .today)!
        store.close(task.id)
        store.undo()
        #expect(titles(.today) == ["Courses"])
        #expect(titles(.history).isEmpty)
    }

    @Test func undoingATickedRepeatingTaskRemovesTheNextOne() {
        let task = store.add(TaskItem.Draft(title: "Compta", when: .day(store.today),
                                            repetition: Repetition(mode: .fixed, every: 1, unit: .week)))
        store.close(task.id)
        #expect(store.tasks.count == 2)
        store.undo()
        #expect(store.tasks.map(\.id) == [task.id])
        #expect(store.task(task.id)?.isOpen == true)
    }

    @Test func actionsAreUndoneFromTheLastToTheFirst() {
        let a = store.add(text: "A", in: .today)!
        let b = store.add(text: "B", in: .today)!
        store.delete(a.id)
        store.edit(b.id) { $0.flagged = true }
        store.setWhen(b.id, .someday)
        store.undo()
        #expect(titles(.today) == ["B"])
        store.undo()
        #expect(store.task(b.id)?.flagged == false)
        store.undo()
        #expect(titles(.today) == ["B", "A"])
    }

    @Test func undoingACreationRemovesTheTask() {
        store.add(text: "Oups", in: .today)
        store.undo()
        #expect(store.tasks.isEmpty)
        #expect(store.undo() == nil)
    }

    @Test func typingInATaskIsUndoneInOneGo() {
        let task = store.add(text: "Titre", in: .today)!
        for title in ["Titre l", "Titre lo", "Titre long"] {
            store.edit(task.id) { $0.title = title }
        }
        store.undo()
        #expect(store.task(task.id)?.title == "Titre")
    }

    @Test func uUndoesFromTheKeyboardAndChoosesTheTaskBack() {
        store.add(text: "B", in: .today)
        let a = store.add(text: "A", in: .today)!
        navigation.handle(.down, store: store)
        navigation.handle(.delete, store: store)
        #expect(titles(.today) == ["B"])
        #expect(navigation.handle(.character("u"), store: store))
        #expect(titles(.today) == ["A", "B"])
        #expect(navigation.selectedTask == a.id)
        #expect(store.notice == "Annulé : suppression de « A »")
    }
}
