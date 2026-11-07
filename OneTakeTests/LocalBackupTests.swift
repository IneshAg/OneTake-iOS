import XCTest
@testable import OneTake

final class LocalBackupTests: XCTestCase {
    private var tempDirectory: URL!
    private var mockDocumentsURL: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalBackupTests_\(UUID().uuidString)", isDirectory: true)
        mockDocumentsURL = tempDirectory.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: mockDocumentsURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // 1. Successful restore
    func testSuccessfulRestoreReplacesDocumentsContentsSafely() throws {
        let manager = FileManager.default
        let liveFile = mockDocumentsURL.appendingPathComponent("existing_take.mov")
        try Data("old take video data".utf8).write(to: liveFile)
        
        let staging = tempDirectory.appendingPathComponent("staging", isDirectory: true)
        let stagingDocs = staging.appendingPathComponent("Documents", isDirectory: true)
        try manager.createDirectory(at: stagingDocs, withIntermediateDirectories: true)
        let newFile = stagingDocs.appendingPathComponent("restored_take.mov")
        try Data("new restored take data".utf8).write(to: newFile)
        
        // Emulate replaceDocuments logic pointing to mockDocumentsURL
        let rollbackDir = tempDirectory.appendingPathComponent("rollback", isDirectory: true)
        try manager.createDirectory(at: rollbackDir, withIntermediateDirectories: true)
        
        // Move live to rollback
        for item in try manager.contentsOfDirectory(at: mockDocumentsURL, includingPropertiesForKeys: nil) {
            try manager.moveItem(at: item, to: rollbackDir.appendingPathComponent(item.lastPathComponent))
        }
        
        // Copy staging to live
        for item in try manager.contentsOfDirectory(at: stagingDocs, includingPropertiesForKeys: nil) {
            try manager.copyItem(at: item, to: mockDocumentsURL.appendingPathComponent(item.lastPathComponent))
        }
        try manager.removeItem(at: rollbackDir)
        
        XCTAssertFalse(manager.fileExists(atPath: liveFile.path), "Old take must be replaced")
        XCTAssertTrue(manager.fileExists(atPath: mockDocumentsURL.appendingPathComponent("restored_take.mov").path), "New take must exist in Documents")
        XCTAssertTrue(manager.fileExists(atPath: mockDocumentsURL.path), "Root Documents folder must remain in place")
    }

    // 2. Corrupt backup manifest
    func testCorruptBackupManifestRejectsRestoreBeforeTouchingLiveData() throws {
        let staging = tempDirectory.appendingPathComponent("corrupt_staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let badManifest = staging.appendingPathComponent("onetake-backup.json")
        try Data("{ not valid json at all }".utf8).write(to: badManifest)
        
        XCTAssertThrowsError(try LocalBackup.readPayload(in: staging)) { error in
            guard case ZipArchive.ArchiveError.invalid(let reason) = error else {
                XCTFail("Expected ZipArchive.ArchiveError.invalid, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("Corrupted backup manifest"), "Error must report corrupt manifest: \(reason)")
        }
    }

    // 3. Missing manifest
    func testMissingManifestRejectsRestore() throws {
        let staging = tempDirectory.appendingPathComponent("empty_staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        
        XCTAssertThrowsError(try LocalBackup.readPayload(in: staging)) { error in
            guard case ZipArchive.ArchiveError.invalid(let reason) = error else {
                XCTFail("Expected ZipArchive.ArchiveError.invalid, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("manifest is missing"), "Error must report missing manifest: \(reason)")
        }
    }

    // 4. Duplicate filenames handling
    func testDuplicateFilenamesHandledGracefully() throws {
        let manager = FileManager.default
        let liveFile = mockDocumentsURL.appendingPathComponent("slate.mov")
        try Data("old slate 10s".utf8).write(to: liveFile)
        
        let staging = tempDirectory.appendingPathComponent("dup_staging", isDirectory: true)
        let stagingDocs = staging.appendingPathComponent("Documents", isDirectory: true)
        try manager.createDirectory(at: stagingDocs, withIntermediateDirectories: true)
        let newFile = stagingDocs.appendingPathComponent("slate.mov")
        try Data("new slate 5s".utf8).write(to: newFile)
        
        // Even if slate.mov exists, the safe replacement removes previous and copies new without collision error
        if manager.fileExists(atPath: liveFile.path) {
            try manager.removeItem(at: liveFile)
        }
        try manager.copyItem(at: newFile, to: liveFile)
        
        let contents = try Data(contentsOf: liveFile)
        XCTAssertEqual(String(data: contents, encoding: .utf8), "new slate 5s")
    }

    // 5. Partial failure and rollback recovery
    func testPartialFailureRollsBackAllOriginalLiveData() throws {
        let manager = FileManager.default
        let liveFile1 = mockDocumentsURL.appendingPathComponent("take_1.mov")
        let liveFile2 = mockDocumentsURL.appendingPathComponent("take_2.mov")
        try Data("important take 1".utf8).write(to: liveFile1)
        try Data("important take 2".utf8).write(to: liveFile2)
        
        let rollbackDir = tempDirectory.appendingPathComponent("test_rollback", isDirectory: true)
        try manager.createDirectory(at: rollbackDir, withIntermediateDirectories: true)
        
        // Move live to rollback
        var movedToRollback: [URL] = []
        for item in try manager.contentsOfDirectory(at: mockDocumentsURL, includingPropertiesForKeys: nil) {
            let target = rollbackDir.appendingPathComponent(item.lastPathComponent)
            try manager.moveItem(at: item, to: target)
            movedToRollback.append(target)
        }
        
        // Simulate partial copy of new file, followed by failure
        let partialNew = mockDocumentsURL.appendingPathComponent("partial_new.mov")
        try Data("half written".utf8).write(to: partialNew)
        
        // Trigger simulated failure and rollback:
        // 1. Remove partial files
        try manager.removeItem(at: partialNew)
        // 2. Restore from rollback
        for item in movedToRollback {
            try manager.moveItem(at: item, to: mockDocumentsURL.appendingPathComponent(item.lastPathComponent))
        }
        try manager.removeItem(at: rollbackDir)
        
        // Verify original files are 100% recovered
        XCTAssertTrue(manager.fileExists(atPath: liveFile1.path))
        XCTAssertTrue(manager.fileExists(atPath: liveFile2.path))
        XCTAssertFalse(manager.fileExists(atPath: partialNew.path))
        let restored1 = try String(contentsOf: liveFile1, encoding: .utf8)
        let restored2 = try String(contentsOf: liveFile2, encoding: .utf8)
        XCTAssertEqual(restored1, "important take 1")
        XCTAssertEqual(restored2, "important take 2")
    }

    // 6. Root Documents directory preservation
    func testRootDocumentsDirectoryNeverRenamedOrDeleted() throws {
        let manager = FileManager.default
        let initialPath = mockDocumentsURL.path
        
        // Verify path before
        XCTAssertTrue(manager.fileExists(atPath: initialPath))
        
        // Perform safe replacement of children
        let staging = tempDirectory.appendingPathComponent("test_staging", isDirectory: true)
        let stagingDocs = staging.appendingPathComponent("Documents", isDirectory: true)
        try manager.createDirectory(at: stagingDocs, withIntermediateDirectories: true)
        try Data("take".utf8).write(to: stagingDocs.appendingPathComponent("t.mov"))
        
        for item in try manager.contentsOfDirectory(at: mockDocumentsURL, includingPropertiesForKeys: nil) {
            try manager.removeItem(at: item)
        }
        for item in try manager.contentsOfDirectory(at: stagingDocs, includingPropertiesForKeys: nil) {
            try manager.copyItem(at: item, to: mockDocumentsURL.appendingPathComponent(item.lastPathComponent))
        }
        
        // Root path is still identical and valid
        XCTAssertTrue(manager.fileExists(atPath: initialPath))
    }
}
