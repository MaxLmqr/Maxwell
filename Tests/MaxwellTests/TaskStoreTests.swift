import Foundation
import Testing
@testable import Maxwell

@MainActor
@Suite("Tâches")
final class TaskStoreTests {
    private let url: URL
    private let store: TaskStore
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Mercredi 25 novembre 2026, midi.
    private static let wednesday = Date(timeIntervalSince1970: 1_795_608_000)

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("TaskStoreTests-\(UUID().uuidString).sqlite")
        store = TaskStore(db: try Database(url: url), calendar: calendar, clock: { Self.wednesday })
    }

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private var today: Day { store.today }
    private func titles(_ list: TaskList) -> [String] { store.tasks(in: list).map(\.title) }

    @Test func theClockIsAWednesday() {
        #expect(today == Day(year: 2026, month: 11, day: 25))
    }

    @Test func aTaskWithoutWhenLandsInTheInboxEvenInAProject() {
        store.add(text: "Acheter du pain")
        store.add(text: "Appeler Paul demain")
        store.add(text: "Devis #Ventes")
        #expect(titles(.inbox) == ["Devis", "Acheter du pain"])
        #expect(titles(.upcoming) == ["Appeler Paul"])
        #expect(titles(.project(store.projects[0].id)) == ["Devis"])
    }

    @Test func aTaskTypedInAListStaysInIt() {
        store.add(text: "Courses", in: .today)
        store.add(text: "Piano", in: .someday)
        let ventes = store.projectNamed("Ventes")
        store.add(text: "Devis", in: .project(ventes.id))
        #expect(titles(.today) == ["Courses"])
        #expect(titles(.someday) == ["Piano"])
        #expect(titles(.project(ventes.id)) == ["Devis"])
        #expect(titles(.inbox) == ["Devis"])
    }

    @Test func projectsAreFoundWhateverTheCase() {
        let ventes = store.projectNamed("Ventes Été")
        #expect(store.add(text: "Devis #ventesete")?.projectID == ventes.id)
        #expect(store.projects.count == 1)
    }

    @Test func aNewTaskComesFirst() {
        store.add(text: "Ancienne", in: .today)
        store.add(text: "Important !", in: .today)
        store.add(text: "Nouvelle", in: .today)
        // Même devant une Tâche avec Drapeau : ce qu'on vient de noter se voit tout de suite.
        #expect(titles(.today) == ["Nouvelle", "Important", "Ancienne"])
    }

    @Test func todayHoldsLateTasksAndDeadlines() {
        store.add(text: "Hier", in: nil)
        store.edit(store.tasks[0].id) { $0.when = .day(self.today.adding(-3, .day, calendar: self.calendar)) }
        store.add(text: "Rapport avant aujourd'hui")
        store.add(text: "Important aujourd'hui !")
        store.add(text: "Plus tard demain")
        #expect(titles(.today) == ["Important", "Rapport", "Hier"])
        #expect(store.tasks(in: .today)[2].daysLate(today: today) == 3)
    }

    @Test func aTaskTickedJustNowStaysVisibleUntilTheListCloses() {
        let task = store.add(text: "Courses", in: .today)!
        store.close(task.id)
        #expect(titles(.today).isEmpty)
        #expect(store.tasks(in: .today, keeping: [task.id]).map(\.title) == ["Courses"])
        #expect(titles(.history) == ["Courses"])
        store.reopen(task.id)
        #expect(titles(.today) == ["Courses"])
    }

    @Test func aTaskTickedYesterdayLeavesTheListEvenIfItStayedOpen() throws {
        var now = Self.wednesday
        let store = TaskStore(db: try Database(url: url), calendar: calendar, clock: { now })
        let task = store.add(text: "Supprimer la table", in: .today)!
        store.close(task.id)
        #expect(store.tasks(in: .today, keeping: [task.id]).map(\.title) == ["Supprimer la table"])
        now = now.addingTimeInterval(86400)
        #expect(store.tasks(in: .today, keeping: [task.id]).isEmpty)
    }

    @Test func cancelledTasksGoToHistoryToo() {
        let task = store.add(text: "Réunion annulée", in: .today)!
        store.close(task.id, as: .cancelled)
        #expect(store.tasks(in: .history).first?.state == .cancelled)
    }

    @Test func aRepeatingTaskComesBackAtTheNextFixedDate() {
        let task = store.add(TaskItem.Draft(title: "Compta", when: .day(today.adding(-14, .day, calendar: calendar)),
                                            repetition: Repetition(mode: .fixed, every: 1, unit: .week)))
        store.edit(task.id) { $0.checklist = [ChecklistItem(title: "Factures", done: true)] }
        store.close(task.id)
        let next = store.tasks(in: .upcoming).first!
        // Faite deux semaines en retard : la suivante est le prochain mercredi, jamais dans le passé.
        #expect(next.when == .day(today.adding(7, .day, calendar: calendar)))
        #expect(next.checklist.map(\.done) == [false])
        #expect(next.repetition == task.repetition)
    }

    @Test func afterCompletionCountsFromTheDayItWasDone() {
        let repetition = Repetition(mode: .afterCompletion, every: 2, unit: .week)
        let next = repetition.next(when: .day(Day(year: 2026, month: 11, day: 1)),
                                   deadline: Day(year: 2026, month: 11, day: 3),
                                   closedOn: today, calendar: calendar)
        #expect(next.when == .day(Day(year: 2026, month: 12, day: 9)))
        #expect(next.deadline == Day(year: 2026, month: 12, day: 11))
    }

    @Test func monthlyRepetitionKeepsTheDayOfMonth() {
        let repetition = Repetition(mode: .fixed, every: 1, unit: .month)
        let october31: When = .day(Day(year: 2026, month: 10, day: 31))
        let inNovember = repetition.next(when: october31, deadline: nil,
                                         closedOn: Day(year: 2026, month: 11, day: 2), calendar: calendar)
        #expect(inNovember.when == .day(Day(year: 2026, month: 11, day: 30)))
        // Comptée depuis le 31 octobre, pas depuis le 30 novembre : décembre retrouve son 31.
        let inDecember = repetition.next(when: october31, deadline: nil,
                                         closedOn: Day(year: 2026, month: 12, day: 1), calendar: calendar)
        #expect(inDecember.when == .day(Day(year: 2026, month: 12, day: 31)))
    }

    @Test func dragAndDropReorders() {
        let c = store.add(text: "C", in: .today)!
        let b = store.add(text: "B", in: .today)!
        let a = store.add(text: "A", in: .today)!
        #expect(titles(.today) == ["A", "B", "C"])
        store.move(c.id, before: a.id, in: .today)
        #expect(titles(.today) == ["C", "A", "B"])
        store.move(c.id, before: nil, in: .today)
        #expect(titles(.today) == ["A", "B", "C"])
        store.move(a.id, before: c.id, in: .today)
        #expect(titles(.today) == ["B", "A", "C"])
        _ = b
    }

    @Test func archivingAProjectKeepsItsOpenTasks() {
        let ventes = store.projectNamed("Ventes")
        store.add(text: "Devis", in: .project(ventes.id))
        store.archiveProject(ventes.id)
        #expect(store.projects.isEmpty)
        #expect(titles(.inbox) == ["Devis"])
    }

    @Test func tasksSurviveARestart() throws {
        store.add(text: "Appeler Paul demain avant vendredi #Ventes !")
        let reopened = TaskStore(db: try Database(url: url), calendar: calendar, clock: { Self.wednesday })
        let task = reopened.tasks.first!
        #expect(task.title == "Appeler Paul")
        #expect(task.when == .day(Day(year: 2026, month: 11, day: 26)))
        #expect(task.deadline == Day(year: 2026, month: 11, day: 27))
        #expect(task.flagged)
        #expect(reopened.project(task.projectID)?.name == "Ventes")
    }
}

@MainActor
@Suite("Suppression d'une Tâche")
final class TaskDeletionTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("TaskDeletionTests-\(UUID().uuidString).sqlite")

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    @Test func aTaskCreatedByMistakeDisappearsEvenFromHistory() throws {
        let store = TaskStore(db: try Database(url: url))
        let task = store.add(text: "Oups", in: .today)!
        store.delete(task.id)
        #expect(store.tasks.isEmpty)
        #expect(TaskStore(db: try Database(url: url)).tasks.isEmpty)
    }

    @Test func undoBringsItBackAsItWas() throws {
        let store = TaskStore(db: try Database(url: url))
        let task = store.add(text: "Relancer Paul demain #Ventes !")!
        store.edit(task.id) { $0.checklist = [ChecklistItem(title: "Appeler")] }
        let before = store.task(task.id)!
        store.delete(task.id)
        store.undoDelete()
        #expect(store.task(task.id) == before)
        #expect(store.lastDeleted == nil)
    }
}
