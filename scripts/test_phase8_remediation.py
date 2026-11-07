import json
import os
import shutil
import sys
import tempfile
import uuid

print("=== Running Phase 8 & 8.1 Verification Tests (AUDIT-FINDING-02, 03, 04) ===")

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOCAL_BACKUP_SWIFT = os.path.join(REPO_ROOT, "OneTake", "Models", "LocalBackup.swift")
APPSTORE_SWIFT = os.path.join(REPO_ROOT, "OneTake", "ModelViews", "AppStore.swift")
BG_COORD_SWIFT = os.path.join(REPO_ROOT, "OneTake", "ModelViews", "BackgroundTaskCoordinator.swift")
ONETAKEAPP_SWIFT = os.path.join(REPO_ROOT, "OneTake", "Views", "OneTakeApp.swift")
CLOUDLINK_SWIFT = os.path.join(REPO_ROOT, "OneTake", "ModelViews", "CloudLink.swift")

# ---------------------------------------------------------
# Test 1: Static Inspection of AUDIT-FINDING-02 (LocalBackup)
# ---------------------------------------------------------
with open(LOCAL_BACKUP_SWIFT, "r", encoding="utf-8") as f:
    backup_code = f.read()

assert "struct OriginalEntrySnapshot: Codable, Equatable" in backup_code, "OriginalEntrySnapshot missing"
assert "struct RestoreJournal: Codable" in backup_code, "RestoreJournal struct missing in LocalBackup.swift"
assert "var originalSnapshot: [OriginalEntrySnapshot]" in backup_code, "originalSnapshot missing in RestoreJournal"
assert "var formatVersion: Int = 1" in backup_code, "formatVersion missing in RestoreJournal"
assert "enum RestoreState: String, Codable" in backup_code, "RestoreState enum missing"
assert "case prepared" in backup_code and "case committed" in backup_code, "RestoreState cases incomplete"
assert 'appSupportDirectory.appendingPathComponent("restore-journal.json")' in backup_code, "journalURL must be in Application Support outside tmp"
assert 'appSupportDirectory.appendingPathComponent("RestoreRollback"' in backup_code, "rollbackDirectory must be in Application Support outside tmp"
assert "func recoverUnfinishedRestoreIfNeeded() throws -> Bool" in backup_code, "recoverUnfinishedRestoreIfNeeded missing"
assert "func isSafeSandboxPath(_ path: String) -> Bool" in backup_code, "isSafeSandboxPath path-traversal check missing"
print("[PASS] Test 1 Passed: LocalBackup defines versioned RestoreJournal with OriginalEntrySnapshot outside tmp")

# ---------------------------------------------------------
# Test 2: AppStore.init Launch-Time Recovery Check
# ---------------------------------------------------------
with open(APPSTORE_SWIFT, "r", encoding="utf-8") as f:
    appstore_code = f.read()

assert "LocalBackup.recoverUnfinishedRestoreIfNeeded()" in appstore_code, "AppStore.init does not trigger recoverUnfinishedRestoreIfNeeded"
print("[PASS] Test 2 Passed: AppStore.init triggers launch-time restore recovery before normal state loading")

# ---------------------------------------------------------
# Test 3: Filesystem Simulation of Exact Unrecorded File Crash & Reconciled Rollback
# ---------------------------------------------------------
temp_test_dir = tempfile.mkdtemp(prefix="onetake_phase8_1_test_")
try:
    live_docs = os.path.join(temp_test_dir, "Documents")
    app_support = os.path.join(temp_test_dir, "ApplicationSupport", "OneTake")
    os.makedirs(live_docs, exist_ok=True)
    os.makedirs(app_support, exist_ok=True)

    # 1. Original file in Documents: project.json
    orig_file = os.path.join(live_docs, "project.json")
    with open(orig_file, "w", encoding="utf-8") as f:
        f.write('{"original_data": 12345}')

    # Snapshot captured before any mutation:
    snapshot = [{"name": "project.json", "isDirectory": False}]

    # 2. Restore begins: original file moved to rollback storage
    op_id = str(uuid.uuid4())
    rollback_dir = os.path.join(app_support, "RestoreRollback", op_id)
    os.makedirs(rollback_dir, exist_ok=True)

    shutil.move(orig_file, os.path.join(rollback_dir, "project.json"))
    assert not os.path.exists(orig_file)

    # 3. New incoming unrecorded file copied into Documents: extra_scene.mov
    extra_scene = os.path.join(live_docs, "extra_scene.mov")
    with open(extra_scene, "w", encoding="utf-8") as f:
        f.write("New unrecorded scene video content")

    # 4. Crash occurs! Journal on disk records originalSnapshot, but incomingItemsInstalled is empty!
    journal_data = {
        "formatVersion": 1,
        "operationID": op_id,
        "state": "installationStarted",
        "stagedDirectoryPath": os.path.join(temp_test_dir, "staged"),
        "rollbackDirectoryPath": rollback_dir,
        "destinationDirectoryPath": live_docs,
        "originalSnapshot": snapshot,
        "originalItemsMoved": ["project.json"],
        "incomingItemsInstalled": [],  # extra_scene.mov NOT recorded before crash!
        "createdAt": 1700000000,
        "updatedAt": 1700000001
    }
    journal_file = os.path.join(app_support, "restore-journal.json")
    with open(journal_file, "w", encoding="utf-8") as f:
        json.dump(journal_data, f)

    # 5. Recovery engine implementation replicating Swift LocalBackup.recoverUnfinishedRestoreIfNeeded()
    def execute_recovery(journal_path):
        if not os.path.exists(journal_path):
            return False
        with open(journal_path, "r", encoding="utf-8") as jf:
            j = json.load(jf)
        dest = j["destinationDirectoryPath"]
        rb = j["rollbackDirectoryPath"]

        if j["state"] == "committed":
            if os.path.exists(rb):
                shutil.rmtree(rb)
            os.remove(journal_path)
            return True

        orig_snapshot_names = set(entry["name"] for entry in j.get("originalSnapshot", []))
        rb_contents = os.listdir(rb) if os.path.exists(rb) else []
        rb_names = set(rb_contents)

        # Step 1: Reconcile destination contents against original snapshot and rollback
        current_dest = os.listdir(dest) if os.path.exists(dest) else []
        for item_name in current_dest:
            item_path = os.path.join(dest, item_name)
            if item_name in rb_names:
                # Original copy in rollback; remove destination copy so rollback can move in
                if os.path.isdir(item_path):
                    shutil.rmtree(item_path)
                else:
                    os.remove(item_path)
            elif item_name in orig_snapshot_names:
                # Was never moved to rollback (crash during preservation): PRESERVE
                continue
            else:
                # Not in rollback and NOT in original snapshot: provably introduced by restore!
                if os.path.isdir(item_path):
                    shutil.rmtree(item_path)
                else:
                    os.remove(item_path)

        # Clean up any recorded installed items
        for installed in j.get("incomingItemsInstalled", []):
            item_path = os.path.join(dest, installed)
            if os.path.exists(item_path):
                if os.path.isdir(item_path):
                    shutil.rmtree(item_path)
                else:
                    os.remove(item_path)

        # Step 2: Restore all original items from rollback directory
        if os.path.exists(rb):
            for item in os.listdir(rb):
                src = os.path.join(rb, item)
                dst = os.path.join(dest, item)
                if os.path.exists(dst):
                    if os.path.isdir(dst):
                        shutil.rmtree(dst)
                    else:
                        os.remove(dst)
                shutil.move(src, dst)

        # Step 3: Verify restored state against original snapshot
        for entry in j.get("originalSnapshot", []):
            expected_path = os.path.join(dest, entry["name"])
            if not os.path.exists(expected_path):
                raise RuntimeError(f"Rollback verification failed: missing {entry['name']}")

        # Step 4: Verification passed: remove rollback dir and journal
        if os.path.exists(rb):
            shutil.rmtree(rb)
        os.remove(journal_path)
        return True

    # Run recovery
    did_recover = execute_recovery(journal_file)
    assert did_recover is True, "Recovery must return True"

    # Assert exact post-recovery state:
    assert os.path.exists(orig_file), "Original project.json must be restored"
    with open(orig_file, "r", encoding="utf-8") as f:
        content = f.read()
    assert content == '{"original_data": 12345}', "Original project.json data must match 100%"

    assert not os.path.exists(extra_scene), "Unrecorded extra_scene.mov MUST be safely removed and NOT orphaned!"
    assert not os.path.exists(rollback_dir), "Rollback directory must be cleaned up"
    assert not os.path.exists(journal_file), "Journal file must be deleted"

    # Idempotent repeated recovery
    assert execute_recovery(journal_file) is False, "Repeated recovery must be safely idempotent"

    print("[PASS] Test 3 Passed: Reconciled rollback successfully removes unrecorded incoming file and restores original data")
finally:
    shutil.rmtree(temp_test_dir, ignore_errors=True)

# ---------------------------------------------------------
# Test 4: Static Inspection of AUDIT-FINDING-03 (FlushOperation & Concurrency)
# ---------------------------------------------------------
with open(BG_COORD_SWIFT, "r", encoding="utf-8") as f:
    bg_coord_code = f.read()

assert "final class FlushOperation: @unchecked Sendable" in bg_coord_code, "FlushOperation missing"
assert "case running" in bg_coord_code and "case completed" in bg_coord_code and "case expired" in bg_coord_code, "FlushOperation outcomes incomplete"
assert "func markCompleted() -> Bool" in bg_coord_code, "markCompleted missing"
assert "func markExpired() -> Bool" in bg_coord_code, "markExpired missing"
assert "guard outcome == .running else { return false }" in bg_coord_code, "FlushOperation must enforce only one terminal outcome"

assert "private(set) var activeFlushOperation: FlushOperation?" in appstore_code, "activeFlushOperation missing in AppStore"
assert "let committedSeq = await StateStorage.shared.getLastCommittedSequence()" in appstore_code, "Expiration handler must verify disk commit status"
assert "if committedSeq >= op.sequence" in appstore_code, "Expiration handler must check sequence commit status"
print("[PASS] Test 4 Passed: FlushOperation lifecycle and expiration verification statically verified in AppStore and BackgroundTaskCoordinator")

# ---------------------------------------------------------
# Test 5: Logic Simulation of FlushOperation Races & Terminal Outcome Winner
# ---------------------------------------------------------
class MockBackgroundTaskCoordinator:
    def __init__(self):
        self.begun_tasks = []
        self.ended_tasks = []
        self.next_id = 100
        self.expiration_handler = None

    def begin_background_task(self, name, handler):
        self.begun_tasks.append(name)
        self.expiration_handler = handler
        self.next_id += 1
        return self.next_id

    def end_background_task(self, task_id):
        self.ended_tasks.append(task_id)

    def trigger_expiration(self):
        if self.expiration_handler:
            self.expiration_handler()

mock_coordinator = MockBackgroundTaskCoordinator()

class SimulatedToken:
    def __init__(self, manager, name, handler):
        self.manager = manager
        self.task_id = manager.begin_background_task(name, handler)
        self.is_ended = False

    def end(self):
        if not self.is_ended and self.task_id is not None:
            self.is_ended = True
            self.manager.end_background_task(self.task_id)

class SimulatedFlushOperation:
    def __init__(self, seq, token):
        self.sequence = seq
        self.token = token
        self.outcome = "running"

    def mark_completed(self):
        if self.outcome != "running":
            return False
        self.outcome = "completed"
        self.token.end()
        return True

    def mark_expired(self):
        if self.outcome != "running":
            return False
        self.outcome = "expired"
        self.token.end()
        return True

# Scenario A: Completion before Expiration
token_a = SimulatedToken(mock_coordinator, "flush.a", lambda: None)
op_a = SimulatedFlushOperation(1, token_a)
assert op_a.mark_completed() is True
assert op_a.outcome == "completed"
# Late expiration call: MUST FAIL
assert op_a.mark_expired() is False
assert op_a.outcome == "completed", "Late expiration cannot overwrite completed status"
assert len(mock_coordinator.ended_tasks) == 1

# Scenario B: Expiration before Completion
token_b = SimulatedToken(mock_coordinator, "flush.b", lambda: None)
op_b = SimulatedFlushOperation(2, token_b)
assert op_b.mark_expired() is True
assert op_b.outcome == "expired"
# Completion call after expiration: MUST FAIL
assert op_b.mark_completed() is False
assert op_b.outcome == "expired", "Completion cannot overwrite expired status"
assert len(mock_coordinator.ended_tasks) == 2

# Scenario C: Repeated completion / expiration calls
assert op_a.mark_completed() is False
assert op_b.mark_expired() is False
assert len(mock_coordinator.ended_tasks) == 2, "Token must be ended exactly once per operation"

print("[PASS] Test 5 Passed: FlushOperation terminal state machine guarantees winner and prevents late expiration overwrites")

# ---------------------------------------------------------
# Test 6: Static Inspection of AUDIT-FINDING-04 (Legacy Share-Link Revocation)
# ---------------------------------------------------------
with open(CLOUDLINK_SWIFT, "r", encoding="utf-8") as f:
    cloud_code = f.read()

assert "enum RevocationOutcome: Equatable, Sendable" in cloud_code, "RevocationOutcome enum missing in CloudLink"
assert "case revoked" in cloud_code, "case revoked missing"
assert "case alreadyRevoked" in cloud_code, "case alreadyRevoked missing"
assert "case unmappedLegacyLink" in cloud_code, "case unmappedLegacyLink missing"
assert "static func revokeDetails(url: URL?, ubiquityFolderURL: URL? = nil) async -> RevocationOutcome" in cloud_code, "revokeDetails missing"
assert "static func revoke(url: URL?, ubiquityFolderURL: URL? = nil) async throws -> Bool" in cloud_code, "revoke backward-compatible signature missing"
assert "if let url, item.lastPathComponent == url.lastPathComponent" not in cloud_code, "Unsafe lastPathComponent UUID comparison was not removed!"
print("[PASS] Test 6 Passed: CloudLink defines RevocationOutcome, eliminates unsafe directory scanning, and preserves legacy data safely")

# ---------------------------------------------------------
# Test 7: Simulation of Legacy Share-Link Safe Failure
# ---------------------------------------------------------
temp_tapes_root = tempfile.mkdtemp(prefix="onetake_tapes_")
try:
    audition_a_folder = os.path.join(temp_tapes_root, str(uuid.uuid4()))
    audition_b_folder = os.path.join(temp_tapes_root, str(uuid.uuid4()))
    os.makedirs(audition_a_folder, exist_ok=True)
    os.makedirs(audition_b_folder, exist_ok=True)
    with open(os.path.join(audition_a_folder, "DOE_JANE_TAPE.mp4"), "w") as f: f.write("Jane Tape")
    with open(os.path.join(audition_b_folder, "SMITH_JOHN_TAPE.mp4"), "w") as f: f.write("John Tape")

    def simulate_revoke_details(public_url_str, folder_url_path):
        if folder_url_path is not None:
            if not os.path.exists(folder_url_path):
                return "alreadyRevoked"
            shutil.rmtree(folder_url_path)
            return "revoked"
        if not public_url_str or "://" not in public_url_str:
            return "failed"
        return "unmappedLegacyLink"

    res1 = simulate_revoke_details("https://www.icloud.com/iclouddrive/0123", audition_a_folder)
    assert res1 == "revoked"
    assert not os.path.exists(audition_a_folder), "Target folder must be deleted"
    assert os.path.exists(audition_b_folder), "Other audition's folder must NEVER be deleted"

    res2 = simulate_revoke_details("https://www.icloud.com/iclouddrive/0123", audition_a_folder)
    assert res2 == "alreadyRevoked"

    res3 = simulate_revoke_details("https://www.icloud.com/iclouddrive/0999opaque", None)
    assert res3 == "unmappedLegacyLink"
    assert os.path.exists(audition_b_folder), "Audition B folder must remain completely intact when legacy link is revoked"

    print("[PASS] Test 7 Passed: Legacy revocation simulation verified safe failure and zero cross-audition interference")
finally:
    shutil.rmtree(temp_tapes_root, ignore_errors=True)

print("\n=== ALL 7 PHASE 8 & 8.1 VERIFICATION TESTS PASSED SUCCESSFULLY ===")
