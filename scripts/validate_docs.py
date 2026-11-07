import os
import re
import sys

repo_root = r"C:\Users\inesh\Downloads\OneTake-iOS"
docs_dir = os.path.join(repo_root, "docs")

canonical_docs = [
    os.path.join(repo_root, "README.md"),
    os.path.join(docs_dir, "INDEX.md"),
    os.path.join(docs_dir, "PROJECT_OVERVIEW.md"),
    os.path.join(docs_dir, "PRODUCT_SPECIFICATION.md"),
    os.path.join(docs_dir, "USER_FLOWS.md"),
    os.path.join(docs_dir, "ARCHITECTURE.md"),
    os.path.join(docs_dir, "CODEBASE_MAP.md"),
    os.path.join(docs_dir, "DATA_MODELS.md"),
    os.path.join(docs_dir, "PERSISTENCE_AND_BACKUP.md"),
    os.path.join(docs_dir, "RECORDING_AND_MEDIA.md"),
    os.path.join(docs_dir, "IMPORT_AND_DOCUMENT_PARSING.md"),
    os.path.join(docs_dir, "EXPORT_AND_SHARING.md"),
    os.path.join(docs_dir, "TESTING.md"),
    os.path.join(docs_dir, "DEVELOPMENT_SETUP.md"),
    os.path.join(docs_dir, "ENGINEERING_DECISIONS.md"),
    os.path.join(docs_dir, "AUDIT_AND_REMEDIATION_HISTORY.md"),
    os.path.join(docs_dir, "KNOWN_ISSUES.md"),
    os.path.join(docs_dir, "ROADMAP.md"),
    os.path.join(docs_dir, "CONTRIBUTING.md"),
    os.path.join(docs_dir, "AI_AGENT_GUIDE.md"),
    os.path.join(docs_dir, "WORK_IN_PROGRESS.md"),
]

link_regex = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

broken_links = []
total_links = 0

for md_path in canonical_docs:
    if not os.path.exists(md_path):
        broken_links.append((os.path.relpath(md_path, repo_root), "FILE_MISSING", md_path))
        continue

    with open(md_path, "r", encoding="utf-8") as f:
        content = f.read()

    matches = link_regex.findall(content)
    for text, link in matches:
        if (
            link.startswith("http://")
            or link.startswith("https://")
            or link.startswith("mailto:")
            or link.startswith("#")
        ):
            continue
        clean_link = link.split("#")[0]
        if not clean_link:
            continue
        total_links += 1
        target_path = os.path.normpath(os.path.join(os.path.dirname(md_path), clean_link))
        if not os.path.exists(target_path):
            broken_links.append((os.path.relpath(md_path, repo_root), link, target_path))

print(f"Validated {total_links} relative markdown links across all {len(canonical_docs)} canonical documentation files.")
if broken_links:
    print(f"FAILED: Found {len(broken_links)} broken relative links:")
    for src, link, target in broken_links:
        print(f"  In {src}: link '{link}' -> not found at {target}")
    sys.exit(1)
else:
    print("SUCCESS: All 21 canonical documentation files exist and 100% of relative links are valid!")
