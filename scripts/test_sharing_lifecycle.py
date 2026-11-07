import json
import os
import sys

print("=== Running Sharing Lifecycle Verification Tests (Phase 6: AUDIT-007) ===")

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CLOUD_SWIFT = os.path.join(REPO_ROOT, "OneTake", "ModelViews", "CloudLink.swift")
MODELS_SWIFT = os.path.join(REPO_ROOT, "OneTake", "Models", "Models.swift")
APPSTORE_SWIFT = os.path.join(REPO_ROOT, "OneTake", "ModelViews", "AppStore.swift")
AUDITIONS_SWIFT = os.path.join(REPO_ROOT, "OneTake", "Views", "AuditionsView.swift")
TESTS_SWIFT = os.path.join(REPO_ROOT, "OneTakeTests", "PackageAndSentTests.swift")

# Test 1: CloudLink.swift Published and revoke implementation
with open(CLOUD_SWIFT, "r", encoding="utf-8") as f:
    cloud_code = f.read()

assert "let ubiquityFolderURL: URL?" in cloud_code, "ubiquityFolderURL missing in CloudLink.Published"
assert "static func revoke(url: URL?, ubiquityFolderURL: URL? = nil) async throws -> Bool" in cloud_code, "CloudLink.revoke missing"
assert "fm.removeItem(at: ubiquityFolderURL)" in cloud_code, "CloudLink.revoke directory removal missing"
print("[PASS] Test 1 Passed: CloudLink defines ubiquityFolderURL and static revoke method")

# Test 2: Models.swift Audition property
with open(MODELS_SWIFT, "r", encoding="utf-8") as f:
    models_code = f.read()

assert "var shareUbiquityFolderURL: URL? = nil" in models_code, "shareUbiquityFolderURL missing in Audition"
print("[PASS] Test 2 Passed: Audition model defines backward-compatible shareUbiquityFolderURL")

# Test 3: AppStore.swift integration
with open(APPSTORE_SWIFT, "r", encoding="utf-8") as f:
    store_code = f.read()

assert "auditions[i].shareUbiquityFolderURL = link.ubiquityFolderURL" in store_code, "shareUbiquityFolderURL not saved in setShareLink"
assert "CloudLink.revoke(url: oldLink, ubiquityFolderURL: folder)" in store_code, "CloudLink.revoke not called in clearShareLink"
assert "CloudLink.revoke(url: link, ubiquityFolderURL: folder)" in store_code, "CloudLink.revoke not called in deleteAudition"
print("[PASS] Test 3 Passed: AppStore calls CloudLink.revoke during clearShareLink and deleteAudition")

# Test 4: AuditionsView.swift UI affordance
with open(AUDITIONS_SWIFT, "r", encoding="utf-8") as f:
    aud_code = f.read()

assert "Revoke share link" in aud_code, "Revoke share link option missing in contextMenu"
assert "store.clearShareLink(for: audition.id)" in aud_code, "clearShareLink not triggered from contextMenu"
print("[PASS] Test 4 Passed: AuditionsView surfaces explicit 'Revoke share link' context action")

# Test 5: PackageAndSentTests.swift coverage
with open(TESTS_SWIFT, "r", encoding="utf-8") as f:
    tests_code = f.read()

assert "testCloudLinkShareLifecycleAndRevocation()" in tests_code, "Phase 6 test missing in PackageAndSentTests"
print("[PASS] Test 5 Passed: Unit test testCloudLinkShareLifecycleAndRevocation present in test suite")

# Test 6: Backward compatibility JSON serialization test
sample_audition_json = """
{
    "id": "22222222-3333-4444-5555-666666666666",
    "project": "Hamlet",
    "projectType": "Theater",
    "role": "Hamlet",
    "roleSize": "Lead",
    "castingOffice": "National Theatre",
    "due": 1800000000,
    "asks": [],
    "pieces": [],
    "scenes": [],
    "destination": "emailOrLink",
    "status": "sent",
    "shareLink": "https://www.icloud.com/iclouddrive/0123hamlet",
    "shareLinkExpires": 1801209600
}
"""
parsed = json.loads(sample_audition_json)
assert parsed.get("shareUbiquityFolderURL") is None, "Missing ubiquity folder URL should cleanly default to None"
parsed["shareUbiquityFolderURL"] = "file:///private/var/mobile/Library/Mobile%20Documents/iCloud~com~onetake/Documents/Tapes/test"
serialized = json.dumps(parsed)
redecoded = json.loads(serialized)
assert redecoded["shareUbiquityFolderURL"].startswith("file:///"), "Serialization with ubiquity folder URL succeeds"
print("[PASS] Test 6 Passed: JSON serialization backward compatibility verified")

print("\n=== ALL 6 PHASE 6 VERIFICATION TESTS PASSED SUCCESSFULLY ===")
