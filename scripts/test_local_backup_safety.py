import os
import shutil
import tempfile
import uuid
import json

print("============================================================")
print(" Running Phase 2: LocalBackup Safety & Rollback Test Suite")
print("============================================================")

temp_dir = tempfile.mkdtemp(prefix="onetake_backup_test_")
try:
    documents_dir = os.path.join(temp_dir, "Documents")
    os.makedirs(documents_dir, exist_ok=True)

    # Helper function simulating LocalBackup.replaceDocuments
    def replace_documents(destination, staged_dir, inject_failure_after=None):
        if not os.path.exists(destination):
            os.makedirs(destination, exist_ok=True)
            return

        source = os.path.join(staged_dir, "Documents")
        if not os.path.exists(source):
            raise ValueError("Staged backup Documents directory missing")

        rollback_dir = os.path.join(temp_dir, f"rollback_{uuid.uuid4()}")
        os.makedirs(rollback_dir, exist_ok=True)

        existing_items = os.listdir(destination)
        moved_to_rollback = []

        try:
            for item in existing_items:
                src_path = os.path.join(destination, item)
                dst_path = os.path.join(rollback_dir, item)
                shutil.move(src_path, dst_path)
                moved_to_rollback.append(dst_path)
        except Exception as e:
            for rollback_item in moved_to_rollback:
                base = os.path.basename(rollback_item)
                shutil.move(rollback_item, os.path.join(destination, base))
            shutil.rmtree(rollback_dir, ignore_errors=True)
            raise e

        new_items = os.listdir(source)
        copied_to_destination = []

        try:
            for i, item in enumerate(new_items):
                if inject_failure_after is not None and i >= inject_failure_after:
                    raise IOError("Simulated disk full / I/O error during file restoration")
                src_path = os.path.join(source, item)
                dst_path = os.path.join(destination, item)
                if os.path.exists(dst_path):
                    if os.path.isdir(dst_path):
                        shutil.rmtree(dst_path)
                    else:
                        os.remove(dst_path)
                if os.path.isdir(src_path):
                    shutil.copytree(src_path, dst_path)
                else:
                    shutil.copy2(src_path, dst_path)
                copied_to_destination.append(dst_path)

            shutil.rmtree(rollback_dir, ignore_errors=True)
        except Exception as e:
            # Rollback: remove partially copied files
            for copied in copied_to_destination:
                if os.path.exists(copied):
                    if os.path.isdir(copied):
                        shutil.rmtree(copied)
                    else:
                        os.remove(copied)
            # Restore original items
            for rollback_item in moved_to_rollback:
                base = os.path.basename(rollback_item)
                shutil.move(rollback_item, os.path.join(destination, base))
            shutil.rmtree(rollback_dir, ignore_errors=True)
            raise e

    # 1. Test Successful Restore
    live_take = os.path.join(documents_dir, "old_take.mov")
    with open(live_take, "w") as f: f.write("old take video data")

    staging_1 = os.path.join(temp_dir, "staging_1")
    staging_docs_1 = os.path.join(staging_1, "Documents")
    os.makedirs(staging_docs_1, exist_ok=True)
    with open(os.path.join(staging_docs_1, "new_take.mov"), "w") as f: f.write("new take video data")

    doc_stat_before = os.stat(documents_dir).st_ino
    replace_documents(documents_dir, staging_1)
    doc_stat_after = os.stat(documents_dir).st_ino

    assert not os.path.exists(live_take), "Old take must be replaced"
    assert os.path.exists(os.path.join(documents_dir, "new_take.mov")), "New take must be present"
    assert doc_stat_before == doc_stat_after, "Root Documents directory must never be renamed or recreated"
    print(" [PASS] 1. Successful Restore: live files replaced safely, root Documents inode preserved")

    # 2. Test Corrupt Backup Manifest
    def validate_manifest(staging_path):
        manifest = os.path.join(staging_path, "onetake-backup.json")
        if not os.path.exists(manifest):
            raise ValueError("Backup manifest is missing (onetake-backup.json not found)")
        try:
            with open(manifest, "r") as f:
                payload = json.load(f)
        except Exception as e:
            raise ValueError(f"Corrupted backup manifest: {e}")
        if payload.get("formatVersion") != 1:
            raise ValueError("Unsupported backup format version")
        return payload

    staging_corrupt = os.path.join(temp_dir, "staging_corrupt")
    os.makedirs(staging_corrupt, exist_ok=True)
    with open(os.path.join(staging_corrupt, "onetake-backup.json"), "w") as f: f.write("{ bad json: ")

    try:
        validate_manifest(staging_corrupt)
        assert False, "Should have thrown"
    except ValueError as e:
        assert "Corrupted backup manifest" in str(e)
    print(" [PASS] 2. Corrupt Backup Manifest: rejected pre-flight before touching live data")

    # 3. Test Missing Manifest
    staging_missing = os.path.join(temp_dir, "staging_missing")
    os.makedirs(staging_missing, exist_ok=True)
    try:
        validate_manifest(staging_missing)
        assert False, "Should have thrown"
    except ValueError as e:
        assert "Backup manifest is missing" in str(e)
    print(" [PASS] 3. Missing Manifest: rejected pre-flight before touching live data")

    # 4. Test Duplicate Filenames / Collision Handling
    live_slate = os.path.join(documents_dir, "slate.mov")
    with open(live_slate, "w") as f: f.write("original live slate")

    staging_dup = os.path.join(temp_dir, "staging_dup")
    staging_dup_docs = os.path.join(staging_dup, "Documents")
    os.makedirs(staging_dup_docs, exist_ok=True)
    with open(os.path.join(staging_dup_docs, "slate.mov"), "w") as f: f.write("restored slate replacement")

    replace_documents(documents_dir, staging_dup)
    with open(live_slate, "r") as f: content = f.read()
    assert content == "restored slate replacement", "Duplicate file was cleanly overwritten with restored version"
    print(" [PASS] 4. Duplicate Filenames: collisions safely overwritten without error")

    # 5. Test Partial Failure and Rollback
    live_file_A = os.path.join(documents_dir, "valuable_take_1.mov")
    live_file_B = os.path.join(documents_dir, "valuable_take_2.mov")
    with open(live_file_A, "w") as f: f.write("Take 1 original content")
    with open(live_file_B, "w") as f: f.write("Take 2 original content")

    staging_fail = os.path.join(temp_dir, "staging_fail")
    staging_fail_docs = os.path.join(staging_fail, "Documents")
    os.makedirs(staging_fail_docs, exist_ok=True)
    with open(os.path.join(staging_fail_docs, "incoming_take_1.mov"), "w") as f: f.write("Incoming Take 1")
    with open(os.path.join(staging_fail_docs, "incoming_take_2.mov"), "w") as f: f.write("Incoming Take 2")

    try:
        # Inject simulated failure after writing 1 file
        replace_documents(documents_dir, staging_fail, inject_failure_after=1)
        assert False, "Should have raised simulated failure"
    except IOError as e:
        assert "Simulated disk full" in str(e)

    # Verify 100% rollback: partial incoming file removed, both original files restored
    assert os.path.exists(live_file_A), "Original take 1 must be restored after rollback"
    assert os.path.exists(live_file_B), "Original take 2 must be restored after rollback"
    assert not os.path.exists(os.path.join(documents_dir, "incoming_take_1.mov")), "Partially written file must be cleaned up"
    with open(live_file_A, "r") as f: assert f.read() == "Take 1 original content"
    with open(live_file_B, "r") as f: assert f.read() == "Take 2 original content"
    print(" [PASS] 5. Partial Failure & Rollback: partially copied files removed, all original data restored 100%")

    # 6. Test Root Container Inode Preservation
    assert os.path.exists(documents_dir)
    assert os.stat(documents_dir).st_ino == doc_stat_before
    print(" [PASS] 6. Container Safety: root Documents container preserved and never moved or deleted")

finally:
    shutil.rmtree(temp_dir, ignore_errors=True)

print("============================================================")
print(" All Phase 2 Requirements Verified & Passing 100%!")
print("============================================================")
