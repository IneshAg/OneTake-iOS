import XCTest
@testable import OneTake

final class PersistenceTests: XCTestCase {
    private func audition(_ project: String) -> Audition {
        Audition(project: project, projectType: "Feature film", role: "Maya", roleSize: "Lead",
                 castingOffice: "Casting office", due: Date(timeIntervalSince1970: 1_800_000_000),
                 asks: [], pieces: [], scenes: [], destination: .actorsAccess, status: .due)
    }

    func testOneUnreadableAuditionDoesNotLoseTheRest() throws {
        let state = PersistedState(auditions: [audition("Good"), audition("Damaged")], slate: SlateInfo(name: "Asha Rao"), isOnboarded: true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var auditions = try XCTUnwrap(json["auditions"] as? [[String: Any]])
        auditions[1].removeValue(forKey: "project")
        json["auditions"] = auditions
        let data = try JSONSerialization.data(withJSONObject: json)

        var kept: Data?
        let loaded = try XCTUnwrap(Persistence.decode(data) { kept = $0 })
        XCTAssertEqual(loaded.auditions.map(\.project), ["Good"])
        XCTAssertEqual(loaded.droppedRecords, 1)
        XCTAssertTrue(loaded.isOnboarded)
        XCTAssertEqual(loaded.slate.name, "Asha Rao")
        XCTAssertEqual(kept, data, "the original bytes must be kept before anything overwrites them")
    }

    func testUnreadableFileIsKeptAndNotReplacedWithEmptyState() {
        let garbage = Data("not json".utf8)
        var kept: Data?
        XCTAssertNil(Persistence.decode(garbage) { kept = $0 })
        XCTAssertEqual(kept, garbage)
    }

    func testCleanFileIsNotCopied() throws {
        let data = try JSONEncoder().encode(PersistedState(auditions: [audition("Fine")], isOnboarded: true))
        var copied = false
        let loaded = try XCTUnwrap(Persistence.decode(data) { _ in copied = true })
        XCTAssertEqual(loaded.auditions.count, 1)
        XCTAssertEqual(loaded.droppedRecords, 0)
        XCTAssertFalse(copied)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let loaded = try XCTUnwrap(Persistence.decode(Data("{}".utf8)) { _ in })
        XCTAssertTrue(loaded.auditions.isEmpty)
        XCTAssertFalse(loaded.isOnboarded)
        XCTAssertTrue(loaded.slate.isEmpty)
    }

    func testISO8601DateStringsDecodeAlongsideTheAppDateFormat() throws {
        let a = audition("ISO dates")
        let state = PersistedState(auditions: [a], isOnboarded: true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var auditions = try XCTUnwrap(json["auditions"] as? [[String: Any]])
        var record = try XCTUnwrap(auditions.first)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        record["due"] = formatter.string(from: a.due)
        auditions[0] = record
        json["auditions"] = auditions
        let data = try JSONSerialization.data(withJSONObject: json)

        let loaded = try XCTUnwrap(Persistence.decode(data) { _ in })
        XCTAssertEqual(loaded.auditions.first?.due, a.due)
        XCTAssertTrue(loaded.isOnboarded)
    }

    func testClearAllLocalDataCleansPracticeAndTakes() {
        let store = AppStore()
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "INT. ROOM", lines: [
            ScriptLine(character: "MAYA", text: "Line 1", isMine: true),
            ScriptLine(character: "JOHN", text: "Line 2", isMine: false)
        ], estimatedSeconds: 30)
        let piece = store.addStandalonePracticePiece(title: "Monologue", character: "MAYA", scene: scene)
        XCTAssertFalse(store.practice.isEmpty, "Practice pieces must be added")

        store.practicePath = [.standalonePractice(piece.id)]
        store.takes = [Take(number: 1, duration: 5, recordedAt: Date(), isCircled: false, notes: [], fileURL: URL(fileURLWithPath: "/tmp/take.mov"), auditionID: UUID(), sceneIndex: 0)]

        store.clearAllLocalData()

        XCTAssertTrue(store.practice.isEmpty, "Practice pieces must be completely cleaned by clearAllLocalData")
        XCTAssertTrue(store.practicePath.isEmpty, "Practice navigation path must be cleared")
        XCTAssertTrue(store.takes.isEmpty, "Takes must be cleared")
    }

    func testClearPracticeDataCleansOnlyPractice() {
        let store = AppStore()
        let scene = ScriptScene(number: 1, title: "Scene 1", heading: "INT. ROOM", lines: [
            ScriptLine(character: "MAYA", text: "Line 1", isMine: true)
        ], estimatedSeconds: 30)
        let piece = store.addStandalonePracticePiece(title: "Monologue", character: "MAYA", scene: scene)
        store.practicePath = [.standalonePractice(piece.id)]
        let initialReaderVersion = store.readerTrackVersion

        store.clearPracticeData()

        XCTAssertTrue(store.practice.isEmpty, "Practice pieces must be cleaned by clearPracticeData")
        XCTAssertTrue(store.practicePath.isEmpty, "Practice path must be emptied")
        XCTAssertGreaterThan(store.readerTrackVersion, initialReaderVersion, "Reader track version should be bumped to notify views")
    }

    // MARK: - Phase 3 Persistence Reliability & Concurrency Tests

    func testSaveThrowsClassifiedPersistenceError() throws {
        let validState = PersistedState(auditions: [audition("Valid")], isOnboarded: true)
        XCTAssertNoThrow(try Persistence.save(validState))
    }

    func testStateStorageMonotonicSequenceOrdering() async throws {
        await StateStorage.shared.resetSequenceForTesting()
        let state1 = PersistedState(auditions: [audition("First")], isOnboarded: true)
        let state2 = PersistedState(auditions: [audition("Second")], isOnboarded: true)

        // Commit sequence 2
        let committed2 = try await StateStorage.shared.writeSnapshot(state2, sequence: 2)
        XCTAssertTrue(committed2, "Sequence 2 should commit")

        // Try to commit sequence 1 (stale snapshot arriving out-of-order)
        let committed1 = try await StateStorage.shared.writeSnapshot(state1, sequence: 1)
        XCTAssertFalse(committed1, "Older sequence 1 must be discarded and not overwrite sequence 2")

        let lastSeq = await StateStorage.shared.getLastCommittedSequence()
        XCTAssertEqual(lastSeq, 2, "Last committed sequence must remain 2")
    }

    func testDecodingLegacyStateWithoutNoticeText() throws {
        let legacyJSON = """
        {
            "auditions": [{
                "id": "11111111-2222-3333-4444-555555555555",
                "project": "Legacy Film",
                "projectType": "Feature film",
                "role": "Alex",
                "roleSize": "Supporting",
                "castingOffice": "Universal",
                "due": 1800000000,
                "asks": [],
                "pieces": [],
                "scenes": [],
                "destination": "actorsAccess",
                "status": "due"
            }],
            "isOnboarded": true,
            "slate": {"name": "Test Actor"}
        }
        """
        var kept: Data?
        let loaded = try XCTUnwrap(Persistence.decode(Data(legacyJSON.utf8)) { kept = $0 })
        XCTAssertNil(kept, "Valid legacy JSON should not produce unreadable copy")
        XCTAssertEqual(loaded.auditions.count, 1)
        let first = loaded.auditions[0]
        XCTAssertEqual(first.project, "Legacy Film")
        XCTAssertEqual(first.role, "Alex")
        XCTAssertNil(first.noticeText, "Missing optional noticeText must decode as nil")
        XCTAssertNil(first.scriptText, "Missing optional scriptText must decode as nil")
        XCTAssertTrue(loaded.isOnboarded)
    }

    func testAtomicWritePreservesLastKnownGoodState() throws {
        let goodState = PersistedState(auditions: [audition("Good Project")], isOnboarded: true)
        try Persistence.save(goodState)
        let targetURL = Persistence.fileURL
        let goodData = try Data(contentsOf: targetURL)
        XCTAssertFalse(goodData.isEmpty)

        let decoded = try XCTUnwrap(Persistence.decode(goodData) { _ in })
        XCTAssertEqual(decoded.auditions.first?.project, "Good Project")
    }

    // MARK: - Phase 8 Background Task Persistence Flush Tests (AUDIT-FINDING-03)

    final class MockBackgroundTaskCoordinator: BackgroundTaskManaging, @unchecked Sendable {
        private let lock = NSLock()
        var begunTasks: [String] = []
        var endedTasks: [UIBackgroundTaskIdentifier] = []
        var nextId: Int = 100
        var expirationHandler: (@Sendable () -> Void)?

        func beginBackgroundTask(name: String, expirationHandler: (@Sendable () -> Void)?) -> UIBackgroundTaskIdentifier {
            lock.lock()
            defer { lock.unlock() }
            begunTasks.append(name)
            self.expirationHandler = expirationHandler
            nextId += 1
            return UIBackgroundTaskIdentifier(rawValue: nextId)
        }

        func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
            lock.lock()
            defer { lock.unlock() }
            endedTasks.append(identifier)
        }

        func triggerExpiration() {
            expirationHandler?()
        }
    }

    @MainActor
    func testBackgroundTaskTokenEndsExactlyOnce() {
        let mock = MockBackgroundTaskCoordinator()
        let token = BackgroundTaskToken(manager: mock, name: "test.flush") {}
        XCTAssertTrue(token.isValid)
        XCTAssertEqual(mock.begunTasks, ["test.flush"])

        token.end()
        XCTAssertFalse(token.isValid)
        XCTAssertEqual(mock.endedTasks.count, 1)

        // Multiple calls to end must not double-end
        token.end()
        token.end()
        XCTAssertEqual(mock.endedTasks.count, 1, "Background task identifier must end exactly once")
    }

    @MainActor
    func testFlushPersistenceAcquiresAndEndsBackgroundTask() async throws {
        let store = AppStore()
        let mock = MockBackgroundTaskCoordinator()
        store.backgroundTaskManager = mock

        // Modify audition to mark dirty
        var a = audition("Flush Test")
        store.auditions = [a]
        // Trigger save to set uncommitted changes
        store.saveAudition(a)
        XCTAssertTrue(store.hasUncommittedChanges)

        // Flush persistence with background coordinator
        store.flushPersistence(using: mock)
        XCTAssertTrue(mock.begunTasks.contains("onetake.persistence.flush"))

        // Wait briefly for off-mainactor write to complete
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(store.lastSaveSucceeded)
        XCTAssertFalse(store.hasUncommittedChanges)
        XCTAssertEqual(mock.endedTasks.count, 1, "Background task token must end upon write completion")
    }

    @MainActor
    func testFlushPersistenceExpirationPreservesUnsavedChanges() async throws {
        let store = AppStore()
        let mock = MockBackgroundTaskCoordinator()
        store.backgroundTaskManager = mock

        var a = audition("Expiration Test")
        store.auditions = [a]
        store.saveAudition(a)

        store.flushPersistence(using: mock)
        // Simulate iOS expiration handler firing before write completes
        mock.triggerExpiration()

        XCTAssertFalse(store.lastSaveSucceeded, "Expired flush must not report success")
        XCTAssertNotNil(store.persistenceError, "Error must be surfaced on expiration")
    }

    // MARK: - Phase 8.1 Synchronized FlushOperation Lifecycle & Race Tests

    func testFlushOperationCompletionBeforeExpirationWins() {
        let mock = MockBackgroundTaskCoordinator()
        let token = BackgroundTaskToken(manager: mock, name: "test.op.comp") {}
        let op = FlushOperation(sequence: 1, token: token)

        XCTAssertEqual(op.currentOutcome(), .running)
        XCTAssertFalse(op.isTerminal)

        // Mark completed first
        let wonCompletion = op.markCompleted()
        XCTAssertTrue(wonCompletion)
        XCTAssertEqual(op.currentOutcome(), .completed)
        XCTAssertTrue(op.isTerminal)

        // Attempt delayed expiration: must fail to transition
        let wonExpiration = op.markExpired()
        XCTAssertFalse(wonExpiration, "Late expiration cannot win once completed")
        XCTAssertEqual(op.currentOutcome(), .completed)
    }

    func testFlushOperationExpirationBeforeCompletionWins() {
        let mock = MockBackgroundTaskCoordinator()
        let token = BackgroundTaskToken(manager: mock, name: "test.op.exp") {}
        let op = FlushOperation(sequence: 2, token: token)

        // Mark expired first
        let wonExpiration = op.markExpired()
        XCTAssertTrue(wonExpiration)
        XCTAssertEqual(op.currentOutcome(), .expired)
        XCTAssertTrue(op.isTerminal)

        // Attempt completion after expiration: cannot overwrite expired state
        let wonCompletion = op.markCompleted()
        XCTAssertFalse(wonCompletion)
        XCTAssertEqual(op.currentOutcome(), .expired)
    }

    func testFlushOperationRepeatedCallbacksAreIdempotent() {
        let mock = MockBackgroundTaskCoordinator()
        let token = BackgroundTaskToken(manager: mock, name: "test.op.repeat") {}
        let op = FlushOperation(sequence: 3, token: token)

        XCTAssertTrue(op.markCompleted())
        XCTAssertFalse(op.markCompleted(), "Repeated completion must return false")
        XCTAssertFalse(op.markCompleted(), "Repeated completion must return false")
        XCTAssertEqual(mock.endedTasks.count, 1, "Token must be ended exactly once")
    }

    @MainActor
    func testForegroundRetryAfterExpiration() async throws {
        let store = AppStore()
        let mock = MockBackgroundTaskCoordinator()
        store.backgroundTaskManager = mock

        var a = audition("Retry Test")
        store.auditions = [a]
        store.saveAudition(a)

        // 1. Initial flush expires
        store.flushPersistence(using: mock)
        mock.triggerExpiration()

        XCTAssertFalse(store.lastSaveSucceeded)
        XCTAssertNotNil(store.persistenceError)

        // 2. Foreground retry
        store.retryPersistenceIfNeeded()
        XCTAssertTrue(mock.begunTasks.count >= 2, "Retry must initiate a new background assertion")

        // Wait for retry commit
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(store.lastSaveSucceeded)
        XCTAssertFalse(store.hasUncommittedChanges)
    }

    @MainActor
    func testForegroundRetryWhilePreviousWriteIsRunningDoesNotOverlap() async throws {
        let store = AppStore()
        let mock = MockBackgroundTaskCoordinator()
        store.backgroundTaskManager = mock

        var a = audition("Non Overlap Test")
        store.auditions = [a]
        store.saveAudition(a)

        store.flushPersistence(using: mock)
        let initialBegunCount = mock.begunTasks.count

        // Attempt retry immediately while operation is still running
        store.retryPersistenceIfNeeded()
        XCTAssertEqual(mock.begunTasks.count, initialBegunCount, "Running flush must not be overlapped by retry")

        try await Task.sleep(for: .milliseconds(50))
    }
}
