import Foundation
import Testing
@testable import Maxwell

@MainActor
@Suite("Sessions")
final class SessionRecorderTests {
    private let url: URL
    private let db: Database
    private let recorder: SessionRecorder
    private let xcode = SessionRecorder.App(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    private let slack = SessionRecorder.App(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    private let chrome = SessionRecorder.App(bundleID: ChromeTab.bundleID, name: "Google Chrome")
    private let loginWindow = SessionRecorder.App(bundleID: "com.apple.loginwindow", name: "loginwindow")

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("SessionRecorderTests-\(UUID().uuidString).sqlite")
        db = try Database(url: url)
        recorder = SessionRecorder(db: db, ignoredBundleIDs: ["com.apple.loginwindow"])
    }

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// `t` secondes après le début des tests.
    private func t(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_000_000 + seconds) }

    /// Les Sessions enregistrées : App, Site, début et fin en secondes.
    private var sessions: [(app: String, site: String?, start: TimeInterval, end: TimeInterval)] {
        db.visibleSessions(in: DateInterval(start: t(-1), end: t(100_000)))
            .sorted { $0.start < $1.start }
            .map { ($0.bundleID, $0.site, $0.start.timeIntervalSince(t(0)), $0.end.timeIntervalSince(t(0))) }
    }

    private func tick(at seconds: TimeInterval, idle: TimeInterval = 0, frontmost: SessionRecorder.App? = nil) {
        recorder.tick(idleSeconds: idle, frontmost: { frontmost }, at: t(seconds))
    }

    @Test func eachAppActivationClosesThePreviousSession() {
        recorder.start(with: xcode, at: t(0))
        tick(at: 5)
        recorder.activate(slack, at: t(60))
        tick(at: 65)

        #expect(sessions.map(\.app) == [xcode.bundleID, slack.bundleID])
        #expect(sessions.map(\.start) == [0, 60])
        #expect(sessions.map(\.end) == [60, 65])
        #expect(recorder.currentName == "Slack")
    }

    @Test func idlenessEndsTheSessionAtTheLastGesture() {
        recorder.start(with: xcode, at: t(0))
        tick(at: 300)
        tick(at: 600, idle: 200)

        #expect(recorder.isIdle)
        #expect(recorder.current == nil)
        #expect(sessions.map(\.end) == [400])

        // Une app activée pendant l'Inactivité ne compte pas ; le retour de Max ouvre une Session.
        #expect(!recorder.activate(slack, at: t(650)))
        tick(at: 700, idle: 2, frontmost: slack)

        #expect(!recorder.isIdle)
        #expect(sessions.map(\.app) == [xcode.bundleID, slack.bundleID])
        #expect(sessions.last?.start == 700)
    }

    @Test func idlenessJustBelowTheThresholdKeepsTheSession() {
        recorder.start(with: xcode, at: t(0))
        tick(at: 300, idle: SessionRecorder.idleThreshold - 1)

        #expect(!recorder.isIdle)
        #expect(sessions.map(\.end) == [300])
    }

    @Test func aPauseClosesTheSessionAndTheWakeOpensANewOne() {
        recorder.start(with: xcode, at: t(0))
        recorder.suspend(at: t(120))
        #expect(!tick(returning: 200))
        #expect(!recorder.activate(slack, at: t(300)))

        #expect(recorder.resume(with: slack, at: t(1_000)))
        #expect(!recorder.isSuspended)
        #expect(sessions.map(\.app) == [xcode.bundleID, slack.bundleID])
        #expect(sessions.map(\.start) == [0, 1_000])
        #expect(sessions.first?.end == 120)
    }

    private func tick(returning seconds: TimeInterval) -> Bool {
        recorder.tick(idleSeconds: 0, frontmost: { nil }, at: t(seconds))
    }

    @Test func ignoredAppsHaveNoSession() {
        recorder.start(with: loginWindow, at: t(0))
        tick(at: 5)

        #expect(recorder.current == nil)
        // Sans Session en cours, le tick suivant en ouvre une sur l'app au premier plan.
        tick(at: 10, frontmost: xcode)
        #expect(sessions.map(\.app) == [xcode.bundleID])
        #expect(sessions.first?.start == 10)
    }

    @Test func theFirstSiteReadingGivesItsSiteToTheCurrentSession() {
        recorder.start(with: chrome, at: t(0))
        let id = recorder.current!.id

        recorder.siteRead("github.com", sessionID: id, at: t(2))

        #expect(sessions.map(\.site) == ["github.com"])
        #expect(sessions.first?.start == 0)
        #expect(recorder.currentName == "github.com")
    }

    @Test func aSiteChangeStartsANewSession() {
        recorder.start(with: chrome, at: t(0))
        let id = recorder.current!.id
        recorder.siteRead("github.com", sessionID: id, at: t(2))
        recorder.siteRead("github.com", sessionID: id, at: t(4))
        recorder.siteRead("mail.google.com", sessionID: id, at: t(30))

        #expect(sessions.map(\.site) == ["github.com", "mail.google.com"])
        #expect(sessions.map(\.start) == [0, 30])
        #expect(sessions.first?.end == 30)
    }

    @Test func aLateSiteReadingForAnOldSessionIsIgnored() {
        recorder.start(with: chrome, at: t(0))
        let chromeSession = recorder.current!.id
        recorder.activate(xcode, at: t(10))

        recorder.siteRead("github.com", sessionID: chromeSession, at: t(11))

        #expect(sessions.map(\.site) == [nil, nil])
        #expect(recorder.currentName == "Xcode")
    }

    @Test func aSessionNeverEndsBeforeItStarts() {
        recorder.start(with: xcode, at: t(100))
        recorder.close(at: t(50))

        #expect(sessions.first?.start == 100)
        #expect(sessions.first?.end == 100)
    }

    @Test func everyNewAppSessionIsReported() {
        var began: [String] = []
        recorder.onAppBegan = { began.append($0) }
        recorder.start(with: chrome, at: t(0))
        let id = recorder.current!.id
        recorder.siteRead("github.com", sessionID: id, at: t(2))
        recorder.siteRead("mail.google.com", sessionID: id, at: t(30))
        recorder.activate(xcode, at: t(60))

        // Un changement de Site n'est pas une nouvelle App.
        #expect(began == [chrome.bundleID, xcode.bundleID])
    }
}
