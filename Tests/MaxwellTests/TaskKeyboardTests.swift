import Foundation
import Testing
@testable import Maxwell

@MainActor
@Suite("Clavier des Tâches")
final class TaskKeyboardTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("TaskKeyboardTests-\(UUID().uuidString).sqlite")
    private let store: TaskStore
    private let navigation = TaskNavigation()

    init() throws {
        store = TaskStore(db: try Database(url: url))
        // La dernière créée passe en tête : la liste se lit A, B, C.
        for title in ["C", "B", "A"] { store.add(text: title, in: .today) }
    }

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private var titles: [String] { navigation.visible(in: store).map(\.title) }
    private var selected: String? { navigation.selectedTask.flatMap(store.task)?.title }
    private func press(_ keys: TaskKey...) { keys.forEach { navigation.handle($0, store: store) } }

    @Test func arrowsChooseATask() {
        press(.down)
        #expect(selected == "A")
        press(.down, .down, .down)
        #expect(selected == "C")
        press(.up)
        #expect(selected == "B")
    }

    @Test func xTicksTheChosenTaskWhichStaysVisible() {
        press(.down, .character("x"))
        #expect(store.task(navigation.selectedTask!)?.state == .done)
        #expect(titles == ["A", "B", "C"])
        press(.character("x"))
        #expect(store.task(navigation.selectedTask!)?.isOpen == true)
    }

    @Test func dateKeysMoveTheTask() {
        press(.down, .character("d"))
        #expect(titles == ["B", "C"])
        press(.down, .character("s"))
        #expect(store.tasks(in: .someday).map(\.title) == ["B"])
    }

    @Test func letterKeysDoNothingWithoutAChosenTask() {
        #expect(!navigation.handle(.character("x"), store: store))
        let allOpen = store.tasks.allSatisfy { $0.isOpen }
        #expect(allOpen)
    }

    @Test func optionArrowsReorder() {
        press(.down, .moveDown)
        #expect(titles == ["B", "A", "C"])
        #expect(selected == "A")
    }

    @Test func deleteThenZBringsItBack() {
        press(.down, .delete)
        #expect(titles == ["B", "C"])
        #expect(selected == "B")
        press(.character("z"))
        #expect(titles == ["A", "B", "C"])
    }

    @Test func digitsChangeListAlsoOnAnAzertyKeyboard() {
        press(.character("2"))
        #expect(navigation.selection == .upcoming)
        press(.character("é"))
        #expect(navigation.selection == .upcoming)
        press(.character("&"))
        #expect(navigation.selection == .today)
    }

    @Test func returnOpensAndEscapeCloses() {
        press(.down, .open)
        #expect(navigation.expanded == navigation.selectedTask)
        press(.escape)
        #expect(navigation.expanded == nil)
        #expect(selected == "A")
        press(.escape)
        #expect(navigation.selectedTask == nil)
    }

    @Test func slashAsksForTheNewTaskField() {
        press(.character("/"))
        #expect(navigation.focusNewTask)
    }

    @Test func leftGoesToTheListsAndArrowsWalkThroughThemProjectsIncluded() {
        let ventes = store.projectNamed("Ventes")
        press(.down, .left)
        #expect(navigation.pane == .lists)
        press(.down)
        #expect(navigation.selection == .upcoming)
        press(.down, .down, .down, .down)
        #expect(navigation.selection == .project(ventes.id))
        press(.down)
        #expect(navigation.selection == .project(ventes.id))
        press(.up, .up, .up, .up, .up, .up)
        #expect(navigation.selection == .today)
    }

    @Test func rightComesBackToTheTasksWithOneChosen() {
        press(.left, .right)
        #expect(navigation.pane == .tasks)
        #expect(selected == "A")
        press(.character("x"))
        #expect(store.task(navigation.selectedTask!)?.state == .done)
    }

    @Test func taskLettersDoNothingWhileInTheLists() {
        press(.down, .left)
        #expect(!navigation.handle(.character("x"), store: store))
        let allOpen = store.tasks.allSatisfy { $0.isOpen }
        #expect(allOpen)
    }

    @Test func anEmptyListSendsTheArrowsToTheLists() {
        navigation.selection = .someday
        navigation.selectFirstIfNeeded(in: store)
        #expect(navigation.pane == .lists)
        press(.up, .up, .up)
        #expect(navigation.selection == .today)
    }

    @Test func upFromTheFirstTaskGoesToTheNewTaskField() {
        press(.down, .down, .up)
        #expect(selected == "A")
        #expect(!navigation.focusNewTask)
        press(.up)
        #expect(navigation.focusNewTask)
        #expect(selected == "A")
    }

    @Test func downFromTheNewTaskFieldChoosesTheFirstTask() {
        navigation.pane = .lists
        #expect(navigation.leaveNewTaskField(store: store))
        #expect(navigation.pane == .tasks)
        #expect(selected == "A")
        navigation.selection = .someday
        #expect(!navigation.leaveNewTaskField(store: store))
    }
}
